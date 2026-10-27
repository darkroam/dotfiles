#!/usr/bin/env python3
"""Group aggregation, fallback, and HTTP delay reasons."""
import json
import os
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs import leafdelay
from axs.mihomo import _QUIET


def fail(message):
    raise SystemExit(message)


PROXIES = {
    "主代理": {"type": "Selector", "all": ["a", "b"], "now": "a"},
    "a": {"type": "Shadowsocks"},
    "b": {"type": "Shadowsocks"},
}


def mixed():
    return {
        "A": {"type": "Selector", "all": ["a", "b"], "now": "a"},
        "B": {"type": "Selector", "all": ["b"], "now": "b"},
        "a": {"type": "Shadowsocks"},
        "b": {"type": "Shadowsocks"},
        "c": {"type": "Shadowsocks"},
        "DIRECT": {"type": "Direct"},
    }


def check_coverage():
    if leafdelay.coverage(PROXIES) != (2, 2):
        fail(leafdelay.coverage(PROXIES))
    proxies = mixed()
    if leafdelay.coverage(proxies) != (2, 4):
        fail(leafdelay.coverage(proxies))
    groups, fallback = leafdelay.split(proxies, ["a", "b", "c", "DIRECT"])
    if groups != ["A", "B"] or fallback != ["c", "DIRECT"]:
        fail((groups, fallback))
    one, rest = leafdelay.split(proxies, ["b"])
    if one != ["A", "B"] or rest:
        fail((one, rest))
    one, rest = leafdelay.split(proxies, ["DIRECT"])
    if one or rest != ["DIRECT"]:
        fail((one, rest))


def _install(table):
    def request(secret, api, method, path, timeout=5):
        for key, action in table.items():
            if key in path:
                if isinstance(action, BaseException):
                    raise action
                value = action(path) if callable(action) else action
                return value if isinstance(value, bytes) else json.dumps(value).encode()
        raise SystemExit("missing " + path)

    original = leafdelay.request
    leafdelay.request = request
    return original


def check_pick():
    proxies = mixed()
    proxies["x"] = {"type": "Shadowsocks"}
    proxies["A"] = {"type": "Selector", "all": ["a", "b", "x"], "now": "a"}
    calls = []

    def slow(path):
        calls.append(path)
        if "/group/A/" in path:
            time.sleep(0.05)
            return {"a": 1, "b": 3, "x": "no"}
        if "/group/B/" in path:
            return {"b": 9}
        raise SystemExit(path)

    original = _install({"group": slow})
    try:
        rows = leafdelay.measure("secret-value", "127.0.0.1:9", proxies, ["b", "a", "x"], "http://127.0.0.1/x", 5, 4)
    finally:
        leafdelay.request = original
    if rows != [("b", 3, ""), ("a", 1, ""), ("x", None, "超时")]:
        fail(rows)
    if any("/proxies/" in path for path in calls):
        fail(calls)


def check_fallback(tmp):
    proxies = mixed()
    fake = Path(tmp) / "fake"
    fake.mkdir()
    (fake / "delay.json").write_text('{"c": 4, "DIRECT": 8, "a": 1}\n', encoding="utf-8")
    saved = os.environ.get("AXS_FAKE_DIR")
    os.environ["AXS_FAKE_DIR"] = str(fake)
    try:
        rows = leafdelay.measure(
            "test-secret-value", "127.0.0.1:9", proxies, ["a", "c", "DIRECT"], "http://127.0.0.1/x", 5, 2,
        )
        log = (fake / "log").read_text(encoding="utf-8")
    finally:
        if saved is None:
            os.environ.pop("AXS_FAKE_DIR", None)
        else:
            os.environ["AXS_FAKE_DIR"] = saved
    if rows[0] != ("a", 1, "") or rows[1][0] != "c" or rows[2][0] != "DIRECT":
        fail(rows)
    if "/group/" not in log or "/proxies/c/" not in log or "/proxies/DIRECT/" not in log:
        fail(log)
    if "/proxies/a/" in log:
        fail("covered leaf fell back\n" + log)


def check_http():
    proxies = {"A": {"type": "Selector", "all": ["a"], "now": "a"}, "a": {"type": "Shadowsocks"}}

    def once(code):
        original = _install({"/group/": SystemExit(f"控制器失败：HTTP {code}")})
        try:
            return leafdelay.measure("s", "127.0.0.1:9", proxies, ["a"], "http://127.0.0.1/x", 5, 1)[0]
        finally:
            leafdelay.request = original

    if once(503) != ("a", None, "不可测"):
        fail(once(503))
    if once(504) != ("a", None, "超时"):
        fail(once(504))
    if once(500) != ("a", None, "HTTP 500"):
        fail(once(500))
    if _QUIET.get():
        fail("quiet leaked")


def check_steps():
    seen = []
    original = _install({"/group/": {"a": 3, "b": 4}, "/proxies/": {"delay": 6}})
    try:
        leafdelay.measure(
            "s", "127.0.0.1:9", PROXIES, ["a", "b"], "http://127.0.0.1/x", 5, 1,
            on_step=lambda: seen.append(1),
        )
    finally:
        leafdelay.request = original
    if seen != [1]:
        fail(seen)


def main():
    check_coverage()
    check_pick()
    check_http()
    check_steps()
    with tempfile.TemporaryDirectory(prefix="axs-leafdelay-") as tmp:
        check_fallback(tmp)
    print("leafdelay ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
