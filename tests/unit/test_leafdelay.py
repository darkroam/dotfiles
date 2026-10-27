#!/usr/bin/env python3
"""Selector aggregation and HTTP delay reasons."""
import json
import os
import sys
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
    if groups != ["A", "B"] or fallback:
        fail((groups, fallback))
    one, rest = leafdelay.split(proxies, ["b"])
    if one != ["A", "B"] or rest:
        fail((one, rest))
    one, rest = leafdelay.split(proxies, ["DIRECT"])
    if one or rest:
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
    proxies["y"] = {"type": "Shadowsocks"}
    proxies["A"] = {"type": "Selector", "all": ["a", "b", "x", "y"], "now": "a"}
    proxies["U"] = {"type": "URLTest", "all": ["c"], "now": "c"}
    calls = []

    def slow(path):
        calls.append(path)
        if "/group/U/" in path or "/proxies/" in path:
            raise SystemExit(path)
        if "/group/A/" in path:
            time.sleep(0.05)
            return {"a": 1, "b": 3, "x": "no"}
        if "/group/B/" in path:
            return {"b": 9}
        raise SystemExit(path)

    original = _install({"group": slow, "/proxies/": slow})
    try:
        rows = leafdelay.measure(
            "secret-value", "127.0.0.1:9", proxies, ["b", "a", "x", "y", "c"], "http://127.0.0.1/x", 5, 4,
        )
    finally:
        leafdelay.request = original
    wanted = [("b", 3, ""), ("a", 1, ""), ("x", None, "超时"), ("y", None, "未覆盖"), ("c", None, "不可选")]
    if rows != wanted:
        fail(rows)
    if any("/proxies/" in path or "/group/U/" in path for path in calls):
        fail(calls)


def check_no_proxy():
    proxies = mixed()
    calls = []

    def grab(path):
        calls.append(path)
        if "/group/" in path:
            return {"a": 1, "b": 2}
        raise SystemExit(path)

    original = _install({"/group/": grab, "/proxies/": grab})
    try:
        rows = leafdelay.measure(
            "test-secret-value", "127.0.0.1:9", proxies, ["a", "c", "DIRECT"], "http://127.0.0.1/x", 5, 2,
        )
    finally:
        leafdelay.request = original
    if rows != [("a", 1, ""), ("c", None, "不可选"), ("DIRECT", None, "不可选")]:
        fail(rows)
    if any("/proxies/" in path for path in calls):
        fail(calls)


def check_delay_ms():
    saved = os.environ.get("AXS_DELAY_TIMEOUT_MS")
    try:
        os.environ.pop("AXS_DELAY_TIMEOUT_MS", None)
        if leafdelay.delay_ms() != 5000:
            fail("default ms")
        for raw in ("", "abc", "-3", "0", "  "):
            os.environ["AXS_DELAY_TIMEOUT_MS"] = raw
            if leafdelay.delay_ms() != 5000:
                fail("bad ms " + repr(raw))
        os.environ["AXS_DELAY_TIMEOUT_MS"] = "2500"
        if leafdelay.delay_ms() != 2500:
            fail("2500")
        path = leafdelay._group_path("主代理", "http://127.0.0.1/x")
        if "timeout=2500" not in path or "/proxies/" in path:
            fail(path)
    finally:
        if saved is None:
            os.environ.pop("AXS_DELAY_TIMEOUT_MS", None)
        else:
            os.environ["AXS_DELAY_TIMEOUT_MS"] = saved


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
    check_no_proxy()
    check_delay_ms()
    print("leafdelay ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
