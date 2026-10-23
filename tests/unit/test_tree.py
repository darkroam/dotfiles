#!/usr/bin/env python3
"""Tree shape, shared numbers, depth, and list flags."""
import io
import os
import sys
import contextlib
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


def main():
    check_roots()
    check_tree()
    check_columns()
    check_flat_and_flags()
    print("tree ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
