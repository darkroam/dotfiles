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
from axs.codes import USAGE  # noqa: E402
from axs.nodes import _show_nodes_full, group_numbers, group_table, node_numbers  # noqa: E402
from axs.render import display_width  # noqa: E402
from axs.tree import render_tree, tree_roots  # noqa: E402


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



def check_select():
    os.environ["AXS_COLOR"] = "never"
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
    with tempfile.TemporaryDirectory(prefix="axs-select-") as tmp:
        root = Path(tmp)
        (root / "config.yaml").write_text(
            "rules:\n"
            "  - DOMAIN,a.example,主代理\n"
            "  - DOMAIN,b.example,DIRECT\n"
            "  - DOMAIN,c.example,国内直连\n"
            "  - IP-CIDR,1.0.0.0/8,负载,no-resolve\n"
            "  - MATCH,国内直连\n",
            encoding="utf-8",
        )
        origin = root / "secret"
        select = render_tree(proxies, width=80, mode="select", origin=origin)
        full = render_tree(proxies, width=80)
        shallow = "\n".join(render_tree(proxies, depth=1, width=80, mode="select", origin=origin).splitlines()[1:])
        mid = "\n".join(render_tree(proxies, depth=2, width=80, mode="select", origin=origin).splitlines()[1:])
    if not select.endswith("\n") or "\t" in select:
        fail("select shape")
    gnums = group_numbers(proxies)
    nnums = node_numbers(proxies)
    for name in ("主代理", "国内直连", "负载", "自动", "回退", "中继"):
        token = f"G{gnums[name]} {name}"
        if token not in select or token not in full:
            fail(f"number {name}\n{select}")
    if f"G{gnums['GLOBAL']}" in select or f"G{gnums['旁路']}" in select or "GLOBAL" in select:
        fail("unreachable\n" + select)
    if "GLOBAL" not in full or "隐藏" not in full:
        fail("full lost a node")
    if f"N{nnums['隐藏']}" in select or f"N{nnums['乙']}" in select or "GONE" in select:
        fail("hidden member\n" + select)
    if f"N{nnums['甲']}" not in select or f"N{nnums['丙']}" not in select:
        fail("leaf missing\n" + select)
    if select.count("甲") != 2:
        fail(f"relay/auto {select.count('甲')}\n{select}")
    if "[URLTest] * 自动·成员不可选" not in select:
        fail("urltest note\n" + select)
    if "[Fallback] 自动·成员不可选" not in select or "[LoadBalance] 自动·成员不可选" not in select:
        fail("auto note\n" + select)
    if "隐藏" in select.split("[URLTest]", 1)[-1].split("[Relay]", 1)[0]:
        fail("urltest expanded")
    if "甲" in shallow or "[URLTest]" in shallow or "隐藏" in shallow or "[LoadBalance] 自动·成员不可选" not in shallow:
        fail("select depth 1\n" + shallow)
    if "隐藏" in mid or "[URLTest] * 自动·成员不可选" not in mid or "甲" not in mid:
        fail("select depth 2\n" + mid)
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


def main():
    check_roots()
    check_tree()
    check_columns()
    check_flat_and_flags()
    check_select()
    print("tree ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
