#!/usr/bin/env python3
"""Node commands forward into axs.nodes. Switch and cache stay numeric."""
import os
import sys
import tempfile
from pathlib import Path

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))

from axs.view import group_table  # noqa: E402
from axs.nodes import resolve_group_name, resolve_switch_name, write_node_cache  # noqa: E402


def fail(message):
    raise SystemExit(message)


def check_forward():
    if (ROOT / "lib" / "merge.py").exists():
        fail("merge remains")
    from axs.core import gen_secret
    from axs.mihomo import group_names, reload_core
    from axs.net import egress, net_precheck
    from axs.nodecmd import show_nodes
    if show_nodes.__module__ != "axs.nodecmd" or group_names.__module__ != "axs.mihomo":
        fail("module")
    if reload_core.__module__ != "axs.mihomo" or gen_secret.__module__ != "axs.core":
        fail("debt module")
    if net_precheck.__module__ != "axs.net" or egress.__module__ != "axs.net":
        fail("net module")
    rules = (ROOT / "axs" / "rules.py").read_text(encoding="utf-8")
    if "import merge" in rules or "merge." in rules:
        fail("rules still depends on merge")
    for name in ("mihomo.py", "subscription.py"):
        body = (ROOT / "axs" / name).read_text(encoding="utf-8")
        if "import merge" in body or "merge." in body:
            fail(name + " still depends on merge")



def check_groups():
    os.environ["AXS_COLOR"] = "never"
    proxies = {
        "PROXY": {"type": "Selector", "now": "a", "all": ["a"]},
        "主代理": {"type": "Selector", "now": "甲", "all": ["甲"]},
        "空组": {"type": "URLTest", "all": ["甲"]},
        "甲": {"type": "Shadowsocks"},
        "a": {"type": "Shadowsocks"},
        "2": {"type": "Selector", "now": "a", "all": ["a"]},
    }
    if resolve_group_name(proxies, "2") != ("2", ""):
        fail("group name 2")
    blocked = {"2": {"type": "Shadowsocks"}, "PROXY": {"type": "Selector", "now": "a"}}
    if resolve_group_name(blocked, "2")[1] != "不是策略组":
        fail("node name blocks index")
    del proxies["2"]
    got = group_table(proxies)
    if "\t" in got:
        fail("tab")
    want = [
        "G1  PROXY   Selector  → a",
        "G2  主代理  Selector  → 甲",
        "G3  空组    URLTest   -",
    ]
    if got.splitlines() != want:
        fail("table\n" + got)
    if resolve_group_name(proxies, "G1")[0] != "PROXY" or resolve_group_name(proxies, "g1")[0] != "PROXY":
        fail("index 1")
    if resolve_group_name(proxies, "1")[1] != "组不存在":
        fail("bare digit")
    if resolve_group_name(proxies, "主代理")[0] != "主代理":
        fail("exact")
    if resolve_group_name(proxies, "G9")[1] != "组不存在":
        fail("missing index")
    if resolve_group_name(proxies, "甲")[1] != "不是策略组":
        fail("leaf")
    if resolve_group_name(proxies, "G02")[1] != "组不存在":
        fail("padded index")
    many = {f"g{i:02d}": {"type": "Selector", "now": "a"} for i in range(1, 11)}
    many["a"] = {"type": "Shadowsocks"}
    lines = group_table(many).splitlines()
    if not lines[0].startswith(" G1  g01") or not lines[-1].startswith("G10  g10"):
        fail("wide numbers\n" + lines[0] + "\n" + lines[-1])
    os.environ["AXS_COLOR"] = "always"
    colored = group_table(proxies)
    if "→ \033[1;32m甲" not in colored or "\033[90m-" not in colored:
        fail("color " + colored)
    os.environ["AXS_COLOR"] = "never"


def check_switch():
    proxies = {
        "主代理": {"type": "Selector", "now": "a", "all": ["a", "b"]},
        "a": {"type": "Shadowsocks"},
        "b": {"type": "Shadowsocks"},
    }
    if resolve_switch_name(proxies, ["a", "b"], "N1") != "a" or resolve_switch_name(proxies, ["a", "b"], "n1") != "a":
        fail("number")
    if resolve_switch_name(proxies, ["a", "b"], "1") is not None:
        fail("bare digit")
    if resolve_switch_name(proxies, ["a"], "b") is not None:
        fail("outsider")
    nested = {
        "主代理": {"type": "Selector", "now": "子", "all": ["子", "a"]},
        "子": {"type": "Selector", "now": "a", "all": ["a"]},
        "a": {"type": "Shadowsocks"},
        "b": {"type": "Shadowsocks"},
    }
    if resolve_switch_name(nested, ["子", "a"], "G2") != "子" or resolve_switch_name(nested, ["子", "a"], "g2") != "子":
        fail("nested group")
    if resolve_switch_name(nested, ["a"], "G2") is not None:
        fail("group outside members")


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
    check_groups()
    check_switch()
    with tempfile.TemporaryDirectory(prefix="axs-nodes-") as tmp:
        check_cache(tmp)
    print("nodes ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
