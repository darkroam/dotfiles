#!/usr/bin/env python3
"""Members table and the node status page."""
import contextlib
import io
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.codes import FAIL  # noqa: E402
from axs.nodeview import render_members, show_members, terminal_text  # noqa: E402
from axs.nodes import group_numbers, node_numbers  # noqa: E402
from axs.render import emph, tone  # noqa: E402
from axs.routes import build  # noqa: E402


def fail(message):
    raise SystemExit(message)


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


def check_default():
    proxies = {
        "入口": {"type": "Selector", "now": "自动", "all": ["自动"]},
        "旁路": {"type": "Selector", "now": "自动", "all": ["自动"]},
        "自动": {"type": "URLTest", "now": "乙", "all": ["甲", "乙"]},
        "均衡": {"type": "LoadBalance", "all": ["甲"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Shadowsocks"},
    }
    gnums, nnums = group_numbers(proxies), node_numbers(proxies)
    with tempfile.TemporaryDirectory(prefix="axs-route-view-") as tmp:
        run = Path(tmp)
        (run / "config.yaml").write_text(
            "rules:\n  - MATCH,入口\n  - DOMAIN,a.example,旁路\n",
            encoding="utf-8",
        )
        os.environ["COLUMNS"] = "80"
        data = build(proxies, run)
        tail = terminal_text(proxies, data, run)
        head = f"G{gnums['自动']} 自动 [URLTest] → N{nnums['乙']} 乙 · 2 个成员"
        if tail.count("个成员") != 1 or head not in tail:
            fail("dedup\n" + tail)
        if tail.count("[*]") != 1 or "[*] " + f"N{nnums['乙']}" not in tail:
            fail("current\n" + tail)
        os.environ["COLUMNS"] = "12"
        narrow = [line for line in terminal_text(proxies, data, run).splitlines() if line[:1] in " ["]
        if len(narrow) != 2:
            fail("columns\n" + "\n".join(narrow))
        cache = run / "cache"
        cache.mkdir()
        (cache / "node-test").write_text('ts=1\nresult=ok\n{"乙": 42}\n', encoding="utf-8")
        os.environ["COLUMNS"] = "80"
        cached = terminal_text(proxies, data, run)
        if "42" not in cached:
            fail("delay\n" + cached)
        (run / "config.yaml").write_text("rules:\n  - MATCH,均衡\n", encoding="utf-8")
        shown = terminal_text(proxies, build(proxies, run), run)
        if f"G{gnums['均衡']} 均衡 [LoadBalance] → - · 1 个成员" not in shown or "[*]" in shown:
            fail("balance\n" + shown)


def check_frames():
    from axs.nodes import _show_nodes_full
    from axs.render import view_page
    from axs.rulelist import status_text
    from axs.selectview import render_select
    from axs.tree import render_tree

    proxies = {"G": {"type": "Selector", "now": "a", "all": ["a"]}, "a": {"type": "Direct"}}
    code, flat, _err = _capture(_show_nodes_full, proxies)
    if code or "当前规则路径" in flat or "说明：" in flat or "\t" not in flat:
        fail("flat frame\n" + flat)
    os.environ["AXS_COLOR"] = "never"
    plain = view_page("", [("全部叶子端点（最近测速：-）：", "    N1 a -")], "说明：全部叶子节点；组关系见 --full。叶子含节点与内置策略，不含策略组。")
    if "最近测速：-" not in plain.splitlines()[2] or "当前：" in plain or "当前出口" in plain or "\033" in plain:
        fail("plain page\n" + plain)
    os.environ["AXS_COLOR"] = "always"
    painted = view_page("G1 入口", [], "说明：x")
    os.environ["AXS_COLOR"] = "never"
    if "\033[1m当前规则路径：" not in painted or "\033[90m说明：x" not in painted:
        fail("paint\n" + painted)
    full = render_tree(proxies, width=80, view=True)
    if not full.startswith("当前规则路径：\n\n完整拓扑：\n") or "说明：完整拓扑" not in full:
        fail("full frame\n" + full)
    if "当前规则路径" in render_tree(proxies, width=80):
        fail("view leaked")
    with tempfile.TemporaryDirectory(prefix="axs-frame-") as tmp:
        run = Path(tmp)
        (run / "config.yaml").write_text("rules:\n  - MATCH,G\n", encoding="utf-8")
        (run / "secret").write_text("x\n", encoding="utf-8")
        shown = render_select(proxies, origin=run / "secret", view=True)
        if "当前规则目标组（可切换）：" not in shown or "说明：可手动切换项" not in shown or "当前出口" in shown:
            fail("select frame\n" + shown)
        if "规则入口" in shown or "成员引用（仅被其他组引用的组）" in shown:
            fail("old select label\n" + shown)
        data = build(proxies, run)
        headed = status_text(data, header=True)
        if not headed.startswith("当前规则路径：\n") or "说明：" in headed:
            fail("rule status\n" + headed)
        if headed.split("\n", 1)[1] != status_text(data):
            fail("header changed body")
        from axs.nodeview import rule_page
        auto = {
            "入口": {"type": "Selector", "now": "自动", "all": ["自动"]},
            "自动": {"type": "URLTest", "now": "a", "all": ["a"]},
            "a": {"type": "Direct"},
        }
        (run / "config.yaml").write_text("rules:\n  - MATCH,入口\n", encoding="utf-8")
        page = rule_page(auto, build(auto, run), run)
        note = "说明：当前状态＝当前规则路径＋链尾自动组；node show 查可选树，--full 完整拓扑，--all 全部叶子。"
        if "末端组（链尾自动组）：" not in page or not page.endswith(note + "\n"):
            fail("default note\n" + page)
        for old in ("--select", "group show", "rule show status", "subscription show", "node list", "node groups"):
            if old in note:
                fail("retired footer " + old)
        if not page.startswith("当前规则路径：\n") or "G1 入口" not in page:
            fail("default path\n" + page)


def main():
    os.environ["AXS_COLOR"] = "never"
    check_members()
    check_default()
    check_frames()
    print("nodeview ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
