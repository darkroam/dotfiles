#!/usr/bin/env python3
"""Node commands forward into axs.nodes. Switch and cache stay numeric."""
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.nodes import resolve_switch_name, write_node_cache  # noqa: E402


def fail(message):
    raise SystemExit(message)


def check_forward():
    if (ROOT / "lib" / "merge.py").exists():
        fail("merge remains")
    from axs.core import gen_secret
    from axs.mihomo import group_names, reload_core
    from axs.net import egress, net_precheck
    from axs.nodes import show_nodes
    if show_nodes.__module__ != "axs.nodes" or group_names.__module__ != "axs.mihomo":
        fail("module")
    if reload_core.__module__ != "axs.mihomo" or gen_secret.__module__ != "axs.core":
        fail("debt module")
    if net_precheck.__module__ != "axs.net" or egress.__module__ != "axs.net":
        fail("net module")
    rules = (ROOT / "lib" / "axs" / "rules.py").read_text(encoding="utf-8")
    if "import merge" in rules or "merge." in rules:
        fail("rules still depends on merge")
    for name in ("mihomo.py", "subscription.py"):
        body = (ROOT / "lib" / "axs" / name).read_text(encoding="utf-8")
        if "import merge" in body or "merge." in body:
            fail(name + " still depends on merge")


def check_switch():
    proxies = {
        "主代理": {"type": "Selector", "now": "a", "all": ["a", "b"]},
        "a": {"type": "Shadowsocks"},
        "b": {"type": "Shadowsocks"},
    }
    if resolve_switch_name(proxies, ["a", "b"], "1") != "a":
        fail("number")
    if resolve_switch_name(proxies, ["a"], "b") is not None:
        fail("outsider")


def check_cache(tmp):
    dest = Path(tmp) / "node-test"
    write_node_cache(
        dest,
        "PROXY",
        ["\033[36mPROXY\033[0m \033[32m12\033[0m", "a 34", "PROXY 1"],
    )
    body = dest.read_text(encoding="utf-8")
    if '"a": 34' not in body or "PROXY" in body.split("result=ok\n", 1)[-1]:
        fail(body)
    if oct(dest.stat().st_mode)[-3:] != "600":
        fail("cache mode")


def main():
    check_forward()
    check_switch()
    with tempfile.TemporaryDirectory(prefix="axs-nodes-") as tmp:
        check_cache(tmp)
    print("nodes ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
