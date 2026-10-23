#!/usr/bin/env python3
"""Only cli may import the service orchestrator. Primitives stay in one module."""
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))
LIB = ROOT / "lib" / "axs"


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
    if "mihomo_path" not in defined(LIB / "config.py"):
        fail("config missing mihomo_path")
    if "port_open" not in defined(LIB / "net.py"):
        fail("net missing port_open")
    service = defined(LIB / "service.py")
    for name in ("hold_lock", "read_pid", "alive", "service_up", "port_open", "mihomo_path", "_HELD"):
        if name in service:
            fail("service still defines " + name)


def service_imports():
    bad = []
    cli_hits = 0
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
            if path.name == "cli.py":
                cli_hits += 1
            else:
                bad.append(f"{path.name}:{node.lineno}")
    if bad:
        fail("service import " + ", ".join(bad))
    if cli_hits == 0:
        fail("cli lost service")


def auto_set():
    from axs.nodes import AUTO_LABEL, AUTO_TYPES
    from axs import tree

    if AUTO_TYPES != frozenset(AUTO_LABEL):
        fail("auto label is not the type set")
    if tree.AUTO_TYPES is not AUTO_TYPES:
        fail("tree copied the auto set")
    if "AUTO" in vars(tree):
        fail("tree still has AUTO")


def main():
    locations()
    service_imports()
    auto_set()
    print("deps")
    return 0


if __name__ == "__main__":
    sys.exit(main())
