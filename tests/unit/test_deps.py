#!/usr/bin/env python3
"""Import graph is a layered DAG. Primitives stay in one module."""
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))
LIB = ROOT / "lib" / "axs"

# Lower index is a lower layer. A module may import a strictly lower layer.
LAYERS = (
    ("config", "codes", "catalog"),
    ("core", "render", "mihomo"),
    ("net", "nodes", "rulelist"),
    ("routes", "nodelist"),
    ("leafdelay", "progress"),
    ("subscription", "rules", "proxy"),
    ("tree", "service", "nodeview", "selectview", "nodetest", "grouptest"),
    ("nodecmd",),
    ("cli",),
    ("__main__",),
)
# Same-layer logic edge. render may import only catalog.
APPROVED = {("rules", "subscription")}


def fail(message):
    raise SystemExit(message)


def defined(path):
    tree = ast.parse(path.read_text(encoding="utf-8"))
    names = set()
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            names.add(node.name)
        elif isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    names.add(target.id)
    return names


def locations():
    core = defined(LIB / "core.py")
    for name in ("hold_lock", "read_pid", "alive", "service_up", "_HELD"):
        if name not in core:
            fail("core missing " + name)
    config = defined(LIB / "config.py")
    if "mihomo_path" not in config:
        fail("config missing mihomo_path")
    if "CIDRS" not in config:
        fail("config missing CIDRS")
    if "port_open" not in defined(LIB / "net.py"):
        fail("net missing port_open")
    for name in ("subscription.py", "mihomo.py"):
        if "CIDRS" in defined(LIB / name):
            fail(name + " still defines CIDRS")
    service = defined(LIB / "service.py")
    for name in ("hold_lock", "read_pid", "alive", "service_up", "port_open", "mihomo_path", "_HELD"):
        if name in service:
            fail("service still defines " + name)


def module_name(node):
    if isinstance(node, ast.ImportFrom) and node.module and node.module.startswith("axs."):
        return node.module.split(".", 1)[1]
    return None


def edges():
    found = []
    for path in sorted(LIB.glob("*.py")):
        src = path.stem
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            dst = module_name(node)
            if dst is None and isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name.startswith("axs."):
                        found.append((src, alias.name.split(".", 1)[1], node.lineno))
                continue
            if dst:
                found.append((src, dst, node.lineno))
    return found


def ranks():
    table = {}
    for index, layer in enumerate(LAYERS):
        for name in layer:
            table[name] = index
    return table


def graph():
    rank = ranks()
    found = edges()
    allowed_pairs = set()
    for src, dst, line in found:
        if src == "catalog":
            fail(f"catalog import {line} -> {dst}")
        if src == "render" and dst in rank and dst != "catalog":
            fail(f"render import {line} -> {dst}")
        if src not in rank or dst not in rank:
            fail(f"unlayered {src}:{line} -> {dst}")
        if dst == "render":
            continue
        if rank[dst] < rank[src]:
            allowed_pairs.add((src, dst))
            continue
        if rank[dst] == rank[src] and (src, dst) in APPROVED:
            allowed_pairs.add((src, dst))
            continue
        fail(f"layer {src}:{line} -> {dst}")
    if ("rules", "subscription") not in allowed_pairs:
        fail("approved edge missing")
    if ("render", "catalog") not in {(src, dst) for src, dst, _line in found}:
        fail("render lost catalog")
    seen = {}
    for src, dst, _line in found:
        seen.setdefault(src, set()).add(dst)
    color = {}

    def walk(node, stack):
        color[node] = 1
        for nxt in sorted(seen.get(node, ())):
            state = color.get(nxt, 0)
            if state == 1:
                fail("cycle " + " -> ".join(stack + [node, nxt]))
            if state == 0:
                walk(nxt, stack + [node])
        color[node] = 2

    for node in sorted(seen):
        if color.get(node, 0) == 0:
            walk(node, [])


def service_imports():
    bad = []
    hits = {"cli.py": 0, "nodecmd.py": 0}
    for path in sorted(LIB.glob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            hit = False
            if isinstance(node, ast.ImportFrom) and node.module == "axs.service":
                hit = True
            elif isinstance(node, ast.Import):
                hit = any(
                    alias.name == "axs.service" or alias.name.startswith("axs.service.")
                    for alias in node.names
                )
            if not hit:
                continue
            if path.name in hits:
                hits[path.name] += 1
            else:
                bad.append(f"{path.name}:{node.lineno}")
    if bad:
        fail("service import " + ", ".join(bad))
    if hits["cli.py"] == 0:
        fail("cli lost service")
    if hits["nodecmd.py"] == 0:
        fail("nodecmd lost service")


def auto_set():
    from axs.nodes import AUTO_LABEL, AUTO_TYPES
    from axs import selectview, tree

    if AUTO_TYPES != frozenset(AUTO_LABEL):
        fail("auto label is not the type set")
    if selectview.AUTO_TYPES is not AUTO_TYPES:
        fail("selectview copied the auto set")
    if "AUTO_TYPES" in vars(tree) or "AUTO" in vars(tree):
        fail("tree still has AUTO")


def main():
    locations()
    service_imports()
    graph()
    auto_set()
    print("deps")
    return 0


if __name__ == "__main__":
    sys.exit(main())
