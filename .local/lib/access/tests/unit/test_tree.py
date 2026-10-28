#!/usr/bin/env python3
"""Tree shape, shared numbers, depth, and list flags."""
import contextlib
import io
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.nodecmd import _list_flags  # noqa: E402
from axs.codes import USAGE  # noqa: E402
from axs.nodelist import _show_nodes_full  # noqa: E402
from axs.nodes import group_numbers, node_numbers  # noqa: E402
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
    if "当前出口" in text:
        fail(text.splitlines()[0])
    nnums = node_numbers(proxies)
    if "M [URLTest] *" in text or text.count("R [Selector]") != 1 or "回到上层" in text:
        fail("once\n" + text)
    if "→ 见 G2 R（下方）" not in text or "→ 见 G1 M（上方）" not in text:
        fail("side\n" + text)
    if text.count(f"N{nnums['甲']} 甲") < 2 or "[*]" not in text:
        fail("leaves\n" + text)
    shallow = render_tree(proxies, depth=1, width=80)
    if "├" in shallow or "└" in shallow or "甲" in shallow or "→ 见" in shallow:
        fail("depth 1\n" + shallow)
    mid = render_tree(proxies, depth=2, width=80)
    if mid != text:
        fail("depth 2\n" + mid)
    shared = {"左": {"type": "Selector", "now": "共享", "all": ["共享", "甲"]}, "右": {"type": "Selector", "now": "乙", "all": ["共享", "乙"]}, "共享": {"type": "Selector", "now": "丙", "all": ["丙"]}, "甲": {"type": "Shadowsocks"}, "乙": {"type": "Shadowsocks"}, "丙": {"type": "Vless"}}
    once = render_tree(shared, width=80)
    if once.count("共享 [Selector]") != 1 or once.count("→ 见 G1 共享（上方）") != 1 or once.count("丙") != 1:
        fail("shared\n" + once)
    ring = {"A": {"type": "Selector", "now": "B", "all": ["B", "甲"]}, "B": {"type": "Selector", "now": "A", "all": ["A", "甲"]}, "甲": {"type": "Shadowsocks"}}
    got = render_tree(ring, width=80)
    if got.count("B [Selector]") != 1 or "回到上层" in got or got.count("N1 甲") < 2:
        fail("ring\n" + got)
    if "→ 见 G2 B（下方）" not in got or "→ 见 G1 A（上方）" not in got:
        fail("ring side\n" + got)


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
    if _list_flags(["--full", "--depth", "2"]) != ("full", 2) or _list_flags(["--depth", "1"]) != ("", 1):
        fail("flags")
    if _list_flags(["--depth", "1", "--full"]) != ("full", 1):
        fail("flags order")
    if _list_flags(["-l"]) != ("flat", None) or _list_flags(["--flat"]) != ("flat", None) or _list_flags(["--all"]) != ("all", None):
        fail("flat")
    for args in (["--full", "--flat"], ["--depth", "0"], ["--depth", "03"], ["--nope"], ["--all", "--depth", "1"], ["--select"]):
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                _list_flags(args)
        except SystemExit as exc:
            if exc.code != USAGE:
                fail(f"flag code {args}")
        else:
            fail(f"flag accepted {args}")



def check_min_depth():
    deep = {
        "根": {"type": "Selector", "all": ["深", "浅"]},
        "深": {"type": "Selector", "all": ["中"]},
        "中": {"type": "Selector", "all": ["目标"]},
        "浅": {"type": "Selector", "all": ["目标"]},
        "目标": {"type": "Selector", "all": ["甲"]},
        "甲": {"type": "Shadowsocks"},
    }
    full = render_tree(deep, width=80)
    if full != (
        "G2 根 [Selector]\n"
        "├─ G4 深 [Selector]\n"
        "│  └─ G1 中 [Selector]\n"
        "│     └─ → 见 G5 目标（下方）\n"
        "└─ G3 浅 [Selector]\n"
        "   └─ G5 目标 [Selector]\n"
        "      └─ N1 甲 [Shadowsocks]\n"
    ):
        fail("deep first\n" + full)
    if full.count("G5 目标 [") != 1:
        fail("deep expanded twice")
    cut = render_tree(deep, depth=3, width=80)
    if "下方" in cut or "甲" in cut or cut.count("G5 目标 [") != 1:
        fail("depth keeps site\n" + cut)
    if render_tree(deep, depth=4, width=80) != full:
        fail("depth 4 moved the site")
    same = {
        "根": {"type": "Selector", "all": ["甲组", "乙组"]},
        "甲组": {"type": "Selector", "all": ["目标"]},
        "乙组": {"type": "Selector", "all": ["目标"]},
        "目标": {"type": "Selector", "all": ["叶"]},
        "叶": {"type": "Shadowsocks"},
    }
    tied = render_tree(same, width=80)
    if tied.count("G4 目标 [") != 1 or "→ 见 G4 目标（上方）" not in tied or tied.find("G3 甲组") > tied.find("G4 目标 ["):
        fail("member tie\n" + tied)
    roots = {
        "左": {"type": "Selector", "all": ["目标"]},
        "右": {"type": "Selector", "all": ["目标"]},
        "目标": {"type": "Selector", "all": ["叶"]},
        "叶": {"type": "Shadowsocks"},
    }
    ordered = render_tree(roots, width=80)
    if ordered.count("G3 目标 [") != 1 or "→ 见 G3 目标（上方）" not in ordered or ordered.find("G1 右") > ordered.find("G3 目标 ["):
        fail("root tie\n" + ordered)
    cycle = {
        "根": {"type": "Selector", "all": ["A"]},
        "A": {"type": "Selector", "now": "B", "all": ["B", "甲"]},
        "B": {"type": "Selector", "now": "A", "all": ["A", "甲"]},
        "甲": {"type": "Shadowsocks"},
    }
    got = render_tree(cycle, width=80)
    if got.count("↩ G1 A（回到上层）") != 1 or got.count("N1 甲") != 2 or "→ 见" in got:
        fail("inner cycle\n" + got)


def main():
    check_roots()
    check_tree()
    check_columns()
    check_flat_and_flags()
    check_min_depth()
    print("tree ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
