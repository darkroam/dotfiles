#!/usr/bin/env python3
"""Tree shape, shared numbers, depth, and list flags."""
import contextlib
import io
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.cli import _list_flags  # noqa: E402
from axs.codes import FAIL, USAGE  # noqa: E402
from axs.nodes import _show_nodes_full, group_numbers, group_table, node_numbers  # noqa: E402
from axs.render import display_width, emph, tone  # noqa: E402
from axs.tree import render_members, render_tree, show_members, tree_roots  # noqa: E402


def fail(message):
    raise SystemExit(message)


def leaves():
    return {
        "R": {"type": "Selector", "now": "M", "all": ["M", "甲", "乙乙", "c"]},
        "M": {"type": "URLTest", "now": "甲", "all": ["甲", "R"]},
        "甲": {"type": "Shadowsocks"},
        "乙乙": {"type": "Shadowsocks"},
        "c": {"type": "Vless"},
    }


def check_roots():
    solo = {"A": {"type": "Selector", "all": []}, "B": {"type": "Selector", "all": ["A"]}}
    if tree_roots(solo) != ["B"]:
        fail(f"roots {tree_roots(solo)}")
    cycle = {
        "B": {"type": "Selector", "all": ["A"]},
        "A": {"type": "Selector", "all": ["B"]},
    }
    if tree_roots(cycle) != ["A", "B"]:
        fail("cycle roots")
    main = {
        "主代理": {"type": "Selector", "all": ["A"]},
        "A": {"type": "Selector", "all": ["主代理"]},
    }
    if tree_roots(main) != ["主代理"]:
        fail("main root")
    glob = {
        "GLOBAL": {"type": "Selector", "all": ["A"]},
        "A": {"type": "Selector", "all": ["GLOBAL"]},
    }
    if tree_roots(glob) != ["GLOBAL"]:
        fail("global root")


def check_tree():
    os.environ["AXS_COLOR"] = "never"
    proxies = leaves()
    text = render_tree(proxies, width=80)
    if "\t" in text or not text.endswith("\n"):
        fail("tree shape")
    if not text.startswith("当前出口：-"):
        fail(text.splitlines()[0])
    gnums = group_numbers(proxies)
    nnums = node_numbers(proxies)
    if f"G{gnums['R']} R [Selector]" not in text or f"G{gnums['M']} M [URLTest] *" not in text:
        fail("group mark\n" + text)
    if f"N{nnums['甲']} 甲 [Shadowsocks] [*]" not in text:
        fail("leaf mark\n" + text)
    if text.count(f"N{nnums['甲']} 甲") < 2:
        fail("shared leaf\n" + text)
    if f"↩ G{gnums['R']} R（回到上层）" not in text:
        fail("cycle\n" + text)
    shallow = render_tree(proxies, depth=1, width=80)
    if "├" in shallow or "└" in shallow or "甲" in shallow:
        fail("depth 1\n" + shallow)
    mid = render_tree(proxies, depth=2, width=80)
    if "M [URLTest]" not in mid or "乙乙" not in mid or "回到上层" in mid:
        fail("depth 2\n" + mid)
    table = group_table(proxies)
    for name, number in gnums.items():
        if f"G{number} {name}" not in text:
            fail(f"tree number {name}")
        if not any(line.split()[0] == str(number) for line in table.splitlines()):
            fail(f"group table {name}\n{table}")


def check_columns():
    proxies = {
        "G": {"type": "Selector", "now": "a", "all": ["a", "b", "c", "d"]},
        "a": {"type": "Shadowsocks"},
        "b": {"type": "Shadowsocks"},
        "c": {"type": "Shadowsocks"},
        "d": {"type": "Shadowsocks"},
    }
    wide = render_tree(proxies, width=80).splitlines()
    leaf_rows = [line for line in wide if "[Shadowsocks]" in line]
    if len(leaf_rows) != 2 or leaf_rows[0].count("Shadowsocks") != 3:
        fail("wide columns\n" + "\n".join(leaf_rows))
    if leaf_rows[0].count("└─ ") != 1 or "├─" in leaf_rows[0]:
        fail("branch once")
    if display_width(leaf_rows[0].split("N")[0]) != display_width(leaf_rows[1].split("N")[0]):
        fail("column align\n" + "\n".join(leaf_rows))
    narrow = [line for line in render_tree(proxies, width=12).splitlines() if "[Shadowsocks]" in line]
    if len(narrow) != 4 or not narrow[0].startswith("└─ ") or not all(line.startswith("   ") for line in narrow[1:]):
        fail("narrow\n" + "\n".join(narrow))


def check_flat_and_flags():
    proxies = {"G": {"type": "Selector", "now": "a", "all": ["a"]}, "a": {"type": "Direct"}}
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        _show_nodes_full(proxies)
    if buf.getvalue() != "*\ta\tDirect\tG\n":
        fail(buf.getvalue())
    if _list_flags(["--full", "--depth", "2"]) != ("full", 2):
        fail("flags")
    if _list_flags(["--depth", "1", "--full"]) != ("full", 1):
        fail("flags order")
    if _list_flags(["-l"]) != ("flat", None) or _list_flags(["--flat"]) != ("flat", None):
        fail("flat")
    for args in (["--depth", "1"], ["--full", "--flat"], ["--depth", "0"], ["--depth", "03"], ["--nope"]):
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                _list_flags(args)
        except SystemExit as exc:
            if exc.code != USAGE:
                fail(f"flag code {args}")
        else:
            fail(f"flag accepted {args}")



def _select(proxies, rules, depth=None):
    with tempfile.TemporaryDirectory(prefix="axs-select-") as tmp:
        root = Path(tmp)
        (root / "config.yaml").write_text(rules, encoding="utf-8")
        return render_tree(proxies, depth=depth, width=80, mode="select", origin=root / "secret")


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
        "当前出口：主代理 → 自动（自动，url-test）→ 隐藏\n"
        "规则入口\n"
        "G3 主代理 [Selector]\n"
        f"├─ G7 自动 [URLTest] * {note}\n"
        "├─ N3 甲 [Shadowsocks]\n"
        "└─ G2 中继 [Relay]\n"
        "   └─ N3 甲 [Shadowsocks] [*]\n"
        "G5 国内直连 [Selector]\n"
        "├─ N1 丙 [Vless] [*]\n"
        f"└─ G4 回退 [Fallback] {note}\n"
        f"G8 负载 [LoadBalance] {note}\n"
    ):
        fail("select\n" + select)
    if "成员引用" in select or "旁路" in select:
        fail("global member\n" + select)
    if shallow.splitlines()[1:] != [
        "规则入口",
        "G3 主代理 [Selector]",
        "G5 国内直连 [Selector]",
        f"G8 负载 [LoadBalance] {note}",
    ]:
        fail("select depth 1\n" + shallow)
    if mid != (
        "当前出口：主代理 → 自动（自动，url-test）→ 隐藏\n"
        "规则入口\n"
        "G3 主代理 [Selector]\n"
        f"├─ G7 自动 [URLTest] * {note}\n"
        "├─ N3 甲 [Shadowsocks]\n"
        "└─ G2 中继 [Relay]\n"
        "G5 国内直连 [Selector]\n"
        "├─ N1 丙 [Vless] [*]\n"
        f"└─ G4 回退 [Fallback] {note}\n"
        f"G8 负载 [LoadBalance] {note}\n"
    ):
        fail("select depth 2\n" + mid)
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
        "当前出口：-\n"
        "规则入口\n"
        "G2 入口 [Selector]\n"
        "├─ N2 甲 [Shadowsocks] [*]\n"
        "├─ → 见 G3 共享（下方）\n"
        "└─ G1 中继 [Relay]\n"
        "   ├─ N2 甲 [Shadowsocks] [*]\n"
        "   └─ ↩ G2 入口（回到上层）\n"
        "G4 另一 [Selector]\n"
        "├─ → 见 G3 共享（下方）\n"
        "└─ → 见 G1 中继（上方）\n"
        "成员引用\n"
        "G3 共享 [Selector]\n"
        "├─ N1 乙 [Vless] [*]\n"
        "└─ → 见 G2 入口（上方）\n"
    ):
        fail("zones\n" + zoned)
    if zoned.count("N2 甲") != 2 or zoned.count("→ 见 G3 共享（下方）") != 2 or zoned.count("G3 共享 [") != 1:
        fail("shared leaf")
    z1 = "\n".join(_select(zones, zrules, 1).splitlines()[1:])
    z2 = _select(zones, zrules, 2)
    if z1 != "规则入口\nG2 入口 [Selector]\nG4 另一 [Selector]\n成员引用\nG3 共享 [Selector]":
        fail("zone depth 1\n" + z1)
    if z2.count("G1 中继 [") != 1 or "回到上层" in z2 or "见 G1 中继（上方）" not in z2 or "见 G3 共享（下方）" not in z2:
        fail("zone depth 2\n" + z2)
    auto = {
        "主代理": {"type": "Selector", "now": "负载", "all": ["自动", "负载"]},
        "自动": {"type": "URLTest", "now": "甲", "all": ["甲", "乙"]},
        "负载": {"type": "LoadBalance", "all": ["乙"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Shadowsocks"},
    }
    shown = _select(auto, "rules:\n  - DOMAIN,a.example,自动\n  - MATCH,负载\n")
    if shown != (
        "当前出口：主代理 → 负载（自动，load-balance）→ -\n"
        "规则入口\n"
        f"G2 自动 [URLTest] {note}\n"
        f"G3 负载 [LoadBalance] {note}\n"
    ) or "成员引用" in shown or "甲" in shown.split("规则入口", 1)[-1]:
        fail("auto root\n" + shown)
    ref = {
        "主代理": {"type": "Selector", "now": "甲", "all": ["甲", "手动"]},
        "手动": {"type": "Selector", "now": "乙", "all": ["乙"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Vless"},
    }
    cited = _select(ref, "rules:\n  - MATCH,主代理\n")
    if cited != (
        "当前出口：主代理 → 甲（手动）→ 甲\n"
        "规则入口\n"
        "G1 主代理 [Selector]\n"
        "├─ N2 甲 [Shadowsocks] [*]\n"
        "└─ → 见 G2 手动（下方）\n"
        "成员引用\n"
        "G2 手动 [Selector]\n"
        "└─ N1 乙 [Vless] [*]\n"
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
    if _list_flags(["--select"]) != ("select", None) or _list_flags(["--depth", "2", "--select"]) != ("select", 2):
        fail("select flags")
    for args in (["--select", "--full"], ["--depth", "1", "--flat"]):
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                _list_flags(args)
        except SystemExit as exc:
            if exc.code != USAGE:
                fail(f"flag code {args}")
        else:
            fail(f"flag accepted {args}")


def _capture(func, *args):
    out, err = io.StringIO(), io.StringIO()
    code = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            func(*args)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
    return code, out.getvalue(), err.getvalue()


def check_members():
    proxies = {
        "主": {"type": "Selector", "now": "子", "all": ["子", "甲", "乙", "GONE"]},
        "子": {"type": "URLTest", "now": "甲", "all": ["甲"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Vless"},
        "空": {"type": "Selector", "all": []},
        "缺": {"type": "Selector"},
    }
    gnums = group_numbers(proxies)
    nnums = node_numbers(proxies)
    text = render_members(proxies, "主", {"甲": 42, "乙": ""})
    want = [
        "G2  子    URLTest      [*]   -",
        "N2  甲    Shadowsocks       42",
        "N1  乙    Vless              -",
        "-   GONE  -                  -",
    ]
    if text.splitlines() != want or not text.endswith("\n") or "\t" in text:
        fail("members\n" + text)
    if f"G{gnums['子']}" != "G2" or f"N{nnums['甲']}" != "N2" or f"N{nnums['乙']}" != "N1":
        fail("numbers moved")
    if "[*]" in text.splitlines()[1]:
        fail("mark leaked")
    if render_members(proxies, "空", {}) != "（无成员）\n":
        fail("empty")
    if render_members(proxies, "缺", {}) != "（无成员）\n":
        fail("missing all")
    os.environ["AXS_COLOR"] = "always"
    mark = emph("32", "[*]")
    painted_name = emph("32", "子")
    fast, mid, slow, dash = tone("32", "42"), tone("33", "150"), tone("31", "300"), tone("90", "-")
    colored = render_members(proxies, "主", {"甲": 42, "乙": 150, "GONE": 300})
    os.environ["AXS_COLOR"] = "never"
    plain = render_members(proxies, "主", {"甲": 42, "乙": 150, "GONE": 300})
    if "\033" in plain or "\033" not in colored:
        fail("color gate")
    stripped = colored
    while "\033[" in stripped:
        start = stripped.find("\033[")
        end = stripped.find("m", start)
        stripped = stripped[:start] + stripped[end + 1 :]
    if stripped != plain:
        fail("color changed plain\n" + stripped)
    if mark not in colored or fast not in colored or mid not in colored or slow not in colored or dash not in colored:
        fail("member colors\n" + colored)
    if painted_name in colored:
        fail("name should stay plain")
    code, out, err = _capture(show_members, proxies, "1", "")
    if code or err or out != render_members(proxies, "主", {}):
        fail(f"index {code} {err!r}\n{out}")
    for token, message in (("甲", "不是策略组"), ("nope", "组不存在"), ("02", "组不存在")):
        code, out, err = _capture(show_members, proxies, token, "")
        if code != FAIL or err != message + "\n" or out:
            fail(f"members {token} {code} {err!r}")


def main():
    check_roots()
    check_tree()
    check_columns()
    check_flat_and_flags()
    check_select()
    check_members()
    print("tree ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
