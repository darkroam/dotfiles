#!/usr/bin/env python3
"""Members table and the default node show page."""
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


def main():
    os.environ["AXS_COLOR"] = "never"
    check_members()
    check_default()
    print("nodeview ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
