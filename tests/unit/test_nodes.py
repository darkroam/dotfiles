#!/usr/bin/env python3
"""Node commands forward into axs.nodes. Switch and cache stay numeric."""
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

import merge  # noqa: E402
from axs.nodes import resolve_switch_name, write_node_cache  # noqa: E402


def fail(message):
    raise SystemExit(message)


def check_forward():
    if merge.show_nodes.__module__ != "axs.nodes" or merge.group_names.__module__ != "axs.mihomo":
        fail("forward module")
    if merge.reload_core.__module__ != "axs.mihomo" or merge.gen_secret.__module__ != "axs.core":
        fail("debt module")
    source = (ROOT / "lib" / "merge.py").read_text(encoding="utf-8")
    for name in ("def show_nodes", "def select_proxy", "def group_names", "def delay", "def reload_core"):
        if name in source:
            fail("merge still defines " + name)
    rules = (ROOT / "lib" / "axs" / "rules.py").read_text(encoding="utf-8")
    if "import merge" in rules or "merge." in rules:
        fail("rules still depends on merge")
    if merge.net_precheck.__module__ != "axs.net" or merge.egress.__module__ != "axs.net":
        fail("net forward")
    for name in ("def net_precheck", "def net_run", "def egress", "def net_targets"):
        if name in source:
            fail("merge still defines " + name)
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
