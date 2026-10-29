#!/usr/bin/env python3
"""node show: one block per Selector, direct members only."""
import contextlib
import io
import os
import sys
import tempfile
from pathlib import Path

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))

from axs.nodecmd import _list_flags  # noqa: E402
from axs.codes import USAGE  # noqa: E402
from axs.nodes import group_numbers, node_numbers  # noqa: E402
from axs.view import render_select  # noqa: E402
from axs.view import render_tree  # noqa: E402


def fail(message):
    raise SystemExit(message)


def _select(proxies, rules, depth=None, view=False, width=80):
    with tempfile.TemporaryDirectory(prefix="axs-select-") as tmp:
        root = Path(tmp)
        (root / "config.yaml").write_text(rules, encoding="utf-8")
        return render_select(proxies, depth=depth, origin=root / "secret", view=view, width=width)


def _once(text, token):
    if text.count(token) != 1:
        fail(f"once {token}\n{text}")


def check_select():
    os.environ["AXS_COLOR"] = "never"
    note = "自动·手动切换会被覆盖"
    proxies = {
        "GLOBAL": {"type": "Selector", "now": "主代理", "all": ["主代理", "旁路"]},
        "旁路": {"type": "Selector", "all": ["甲"]},
        "主代理": {"type": "Selector", "now": "自动", "all": ["自动", "甲", "中继", "GONE"]},
        "国内直连": {"type": "Selector", "now": "丙", "all": ["丙", "回退"]},
        "自动": {"type": "URLTest", "now": "隐藏", "all": ["隐藏"]},
        "回退": {"type": "Fallback", "now": "乙", "all": ["乙"]},
        "负载": {"type": "LoadBalance", "now": "甲", "all": ["甲"]},
        "中继": {"type": "Relay", "now": "甲", "all": ["甲"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Shadowsocks"},
        "丙": {"type": "Vless"},
        "隐藏": {"type": "Vless"},
    }
    rules = (
        "rules:\n"
        "  - DOMAIN,a.example,主代理\n"
        "  - DOMAIN,b.example,DIRECT\n"
        "  - DOMAIN,c.example,国内直连\n"
        "  - IP-CIDR,1.0.0.0/8,负载,no-resolve\n"
        "  - MATCH,国内直连\n"
    )
    select = _select(proxies, rules)
    full = render_tree(proxies, width=80)
    shallow = _select(proxies, rules, 1)
    mid = _select(proxies, rules, 2)
    if select != (
        "规则入口\n"
        "  G3 主代理 [Selector]\n"
        f"  ├─ G7 自动 [URLTest] [*] {note}\n"
        "  ├─ G2 中继 [Relay]\n"
        "  └─ N3 甲\n"
        "\n"
        "  G5 国内直连 [Selector]\n"
        f"  ├─ G4 回退 [Fallback] {note}\n"
        "  └─ N1 丙 [*]\n"
        "\n"
        f"  G8 负载 [LoadBalance] {note}\n"
    ):
        fail("select\n" + select)
    if mid != select:
        fail("depth>=2 is the member layer\n" + mid)
    if "成员引用" in select or "旁路" in select or "[Shadowsocks]" in select or "当前出口" in select:
        fail("flat direct\n" + select)
    if "  ├─ " not in select or not any(line.startswith("  G") for line in select.splitlines()):
        fail("indent\n" + select)
    if shallow.splitlines() != [
        "规则入口",
        "  G3 主代理 [Selector]",
        "",
        "  G5 国内直连 [Selector]",
        "",
        f"  G8 负载 [LoadBalance] {note}",
    ]:
        fail("select depth 1\n" + shallow)
    gnums = group_numbers(proxies)
    nnums = node_numbers(proxies)
    if f"G{gnums['GLOBAL']}" in select or "GLOBAL" in select or "GONE" in select:
        fail("unreachable\n" + select)
    if f"N{nnums['隐藏']}" in select or f"N{nnums['乙']}" in select:
        fail("hidden member\n" + select)
    if "GLOBAL" not in full or "隐藏" not in full:
        fail("full lost a node")
    for name in ("主代理", "国内直连", "负载", "自动", "回退", "中继"):
        _once(select, f"G{gnums[name]} {name} [")
    zones = {
        "入口": {"type": "Selector", "now": "甲", "all": ["甲", "共享", "中继"]},
        "另一": {"type": "Selector", "now": "共享", "all": ["共享", "中继"]},
        "共享": {"type": "Selector", "now": "乙", "all": ["乙", "入口"]},
        "中继": {"type": "Relay", "now": "甲", "all": ["甲", "入口"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Vless"},
    }
    zrules = "rules:\n  - DOMAIN,a.example,入口\n  - MATCH,另一\n"
    zoned = _select(zones, zrules)
    if zoned != (
        "规则入口\n"
        "  G2 入口 [Selector]\n"
        "  ├─ G3 共享 [Selector] → 见成员引用\n"
        "  ├─ G1 中继 [Relay]\n"
        "  └─ N2 甲 [*]\n"
        "\n"
        "  G4 另一 [Selector]\n"
        "  ├─ G3 共享 [Selector] [*] → 见成员引用\n"
        "  └─ G1 中继 [Relay]\n"
        "成员引用\n"
        "  G3 共享 [Selector]\n"
        "  ├─ G2 入口 [Selector] → 见当前规则目标组\n"
        "  └─ N1 乙 [*]\n"
    ):
        fail("zones\n" + zoned)
    if zoned.count("N2 甲") != 1 or zoned.count("→ 见成员引用") != 2 or zoned.count("G3 共享 [") != 3:
        fail("shared leaf\n" + zoned)
    if "回到上层" in zoned or "甲 [Shadowsocks]" in zoned:
        fail("zone expanded\n" + zoned)
    z1 = _select(zones, zrules, 1)
    if z1 != (
        "规则入口\n"
        "  G2 入口 [Selector]\n"
        "\n"
        "  G4 另一 [Selector]\n"
        "成员引用\n"
        "  G3 共享 [Selector]\n"
    ):
        fail("zone depth 1\n" + z1)
    if _select(zones, zrules, 2) != zoned or _select(zones, zrules, 3) != zoned:
        fail("zone depth stops at members")
    auto = {
        "主代理": {"type": "Selector", "now": "负载", "all": ["自动", "负载"]},
        "自动": {"type": "URLTest", "now": "甲", "all": ["甲", "乙"]},
        "负载": {"type": "LoadBalance", "all": ["乙"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Shadowsocks"},
    }
    shown = _select(auto, "rules:\n  - DOMAIN,a.example,自动\n  - MATCH,负载\n")
    if shown != (
        "规则入口\n"
        f"  G2 自动 [URLTest] {note}\n"
        "\n"
        f"  G3 负载 [LoadBalance] {note}\n"
    ) or "成员引用" in shown or "当前出口" in shown or "甲" in shown.split("规则入口", 1)[-1]:
        fail("auto root\n" + shown)
    ref = {
        "主代理": {"type": "Selector", "now": "甲", "all": ["甲", "手动"]},
        "手动": {"type": "Selector", "now": "乙", "all": ["乙"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Vless"},
    }
    cited = _select(ref, "rules:\n  - MATCH,主代理\n")
    if cited != (
        "规则入口\n"
        "  G1 主代理 [Selector]\n"
        "  ├─ G2 手动 [Selector] → 见成员引用\n"
        "  └─ N2 甲 [*]\n"
        "成员引用\n"
        "  G2 手动 [Selector]\n"
        "  └─ N1 乙 [*]\n"
    ):
        fail("referenced\n" + cited)
    buried = _select(
        {
            "主代理": {"type": "Selector", "now": "自动", "all": ["自动"]},
            "自动": {"type": "URLTest", "now": "甲", "all": ["甲", "手动"]},
            "手动": {"type": "Selector", "all": ["乙"]},
            "甲": {"type": "Shadowsocks"},
            "乙": {"type": "Vless"},
        },
        "rules:\n  - MATCH,自动\n",
    )
    if "成员引用" in buried or "手动 [" in buried:
        fail("auto member\n" + buried)
    if _list_flags([]) != ("", None) or _list_flags(["--depth", "2"]) != ("", 2):
        fail("select flags")
    for args in (["--select"], ["--select", "--full"], ["--depth", "1", "--flat"]):
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                _list_flags(args)
        except SystemExit as exc:
            if exc.code != USAGE:
                fail(f"flag code {args}")
        else:
            fail(f"flag accepted {args}")


def check_reach():
    note = "自动·手动切换会被覆盖"
    nested = {
        "主代理": {"type": "Selector", "now": "子", "all": ["子", "甲"]},
        "子": {"type": "Selector", "now": "乙", "all": ["乙", "孙"]},
        "孙": {"type": "Selector", "now": "丙", "all": ["丙"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Vless"},
        "丙": {"type": "Shadowsocks"},
    }
    text = _select(nested, "rules:\n  - MATCH,主代理\n")
    if text != (
        "规则入口\n"
        "  G1 主代理 [Selector]\n"
        "  ├─ G2 子 [Selector] [*] → 见成员引用\n"
        "  └─ N3 甲\n"
        "成员引用\n"
        "  G2 子 [Selector]\n"
        "  ├─ G3 孙 [Selector] → 见成员引用\n"
        "  └─ N2 乙 [*]\n"
        "\n"
        "  G3 孙 [Selector]\n"
        "  └─ N1 丙 [*]\n"
    ):
        fail("nested\n" + text)
    head, low = text.split("\n成员引用\n", 1)
    if "丙" in head or "乙" in head.split("规则入口", 1)[-1]:
        fail("root inlined a grandchild\n" + text)
    if low.count("N1 丙") != 1 or "甲" in low:
        fail("grandchild repeated\n" + text)
    both = {
        "主代理": {"type": "Selector", "now": "手动", "all": ["自动", "手动"]},
        "自动": {"type": "URLTest", "now": "甲", "all": ["甲", "手动"]},
        "手动": {"type": "Selector", "now": "乙", "all": ["乙"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Vless"},
    }
    reached = _select(both, "rules:\n  - MATCH,主代理\n")
    if reached.count("手动 [Selector]") != 2 or "N1 乙" not in reached:
        fail("direct beats auto\n" + reached)
    if f"G3 自动 [URLTest] {note}" not in reached:
        fail("auto row\n" + reached)
    relay = {
        "主代理": {"type": "Selector", "now": "中继", "all": ["中继"]},
        "中继": {"type": "Relay", "now": "手动", "all": ["手动", "甲"]},
        "手动": {"type": "Selector", "now": "乙", "all": ["乙"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Vless"},
    }
    via = _select(relay, "rules:\n  - MATCH,主代理\n")
    if via != (
        "规则入口\n"
        "  G2 主代理 [Selector]\n"
        "  └─ G1 中继 [Relay] [*]\n"
        "成员引用\n"
        "  G3 手动 [Selector]\n"
        "  └─ N1 乙 [*]\n"
    ):
        fail("relay\n" + via)
    cycle = {
        "甲组": {"type": "Selector", "now": "乙组", "all": ["乙组", "甲"]},
        "乙组": {"type": "Selector", "now": "甲组", "all": ["甲组", "乙"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Vless"},
    }
    ring = _select(cycle, "rules:\n  - MATCH,甲组\n")
    if ring != (
        "规则入口\n"
        "  G2 甲组 [Selector]\n"
        "  ├─ G1 乙组 [Selector] [*] → 见成员引用\n"
        "  └─ N2 甲\n"
        "成员引用\n"
        "  G1 乙组 [Selector]\n"
        "  ├─ G2 甲组 [Selector] [*] → 见当前规则目标组\n"
        "  └─ N1 乙\n"
    ):
        fail("cycle\n" + ring)
    if "回到上层" in ring or ring.count("G2 甲组 [Selector]") != 2:
        fail("cycle recursed\n" + ring)
    heads = _select(nested, "rules:\n  - MATCH,主代理\n", 1)
    if "N2 甲" in heads or "N1 丙" in heads or heads.count("[Selector]") != 3:
        fail("depth 1 headers\n" + heads)


def check_columns():
    names = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛"]
    proxies = {
        "主代理": {"type": "Selector", "now": "甲", "all": ["手动", "中继", *names, "GONE"]},
        "手动": {"type": "Selector", "now": "乙", "all": ["乙"]},
        "中继": {"type": "Relay", "all": ["甲"]},
        "乙": {"type": "Vless"},
    }
    proxies.update({name: {"type": "Shadowsocks"} for name in names})
    rules = "rules:\n  - MATCH,主代理\n"
    os.environ["AXS_COLOR"] = "never"
    narrow = _select(proxies, rules, width=40)
    wide = _select(proxies, rules, width=160)
    block = narrow.split("\n成员引用\n", 1)[0].split("主代理 [Selector]\n", 1)[1]
    lines = [line for line in block.splitlines() if line]
    groups = [line for line in lines if "[Selector]" in line or "[Relay]" in line]
    leaves = [line for line in lines if line not in groups]
    if len(groups) != 2 or any(line.count("G") != 1 or not line.startswith("  ├─ ") for line in groups):
        fail("group lines\n" + narrow)
    if not leaves[0].startswith("  └─ ") or any(not line.startswith("     ") for line in leaves[1:]):
        fail("leaf wrap\n" + narrow)
    if "甲 [*]" not in leaves[0] or "GONE" in narrow or len(leaves) < 2:
        fail("marker\n" + narrow)
    wide_leaf = [line for line in wide.splitlines() if line.startswith("  └─ ") and "甲" in line]
    if len(wide_leaf) != 1 or any(name not in wide_leaf[0] for name in names):
        fail("wide\n" + wide)
    heads = _select(proxies, rules, 1, width=40)
    if "├─" in heads or "└─" in heads:
        fail("depth\n" + heads)
    os.environ["AXS_COLOR"] = "always"
    colored = _select(proxies, rules, width=40)
    os.environ["AXS_COLOR"] = "never"
    if "\033[32m[*]\033[0m" not in colored:
        fail("color\n" + colored)


def main():
    check_select()
    check_reach()
    check_columns()
    print("select ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
