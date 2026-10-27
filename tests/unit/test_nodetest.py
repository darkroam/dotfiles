#!/usr/bin/env python3
"""Leaf delay tests, cache merge, and stable output order."""
import contextlib
import io
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.cli import main as cli_main
from axs.codes import DOWN, FAIL, USAGE
from axs.nodes import load_delays, write_node_cache
from axs import leafdelay, nodetest


def fail(message):
    raise SystemExit(message)


def check_resolve():
    proxies = {
        "主代理": {"type": "Selector", "now": "a", "all": ["a", "1"]},
        "a": {"type": "Shadowsocks"},
        "1": {"type": "Shadowsocks"},
        "DIRECT": {"type": "Direct"},
    }
    if nodetest.resolve_leaf(proxies, "a") != ("a", ""):
        fail("name")
    if nodetest.resolve_leaf(proxies, "1") != ("1", ""):
        fail("numeric name")
    if nodetest.resolve_leaf(proxies, "N1")[0] not in {"1", "DIRECT", "a"}:
        fail("number")
    name, err = nodetest.resolve_leaf(proxies, "n1")
    if err or name != nodetest.resolve_leaf(proxies, "N1")[0]:
        fail("case")
    if nodetest.resolve_leaf(proxies, "2") != (None, "usage"):
        fail("bare digit")
    if nodetest.resolve_leaf(proxies, "主代理") != (None, "usage"):
        fail("group")
    if nodetest.resolve_leaf(proxies, "nope") != (None, "missing"):
        fail("missing")
    if nodetest.resolve_leaf(proxies, "N9") != (None, "missing"):
        fail("bad number")


def check_workers():
    saved = os.environ.get("AXS_TEST_WORKERS")
    try:
        os.environ.pop("AXS_TEST_WORKERS", None)
        if nodetest._workers() != 8:
            fail("default workers")
        for raw in ("0", "33", "abc", "-1", ""):
            os.environ["AXS_TEST_WORKERS"] = raw
            if nodetest._workers() != 8:
                fail("bad workers " + raw)
        os.environ["AXS_TEST_WORKERS"] = "3"
        if nodetest._workers() != 3:
            fail("workers 3")
    finally:
        if saved is None:
            os.environ.pop("AXS_TEST_WORKERS", None)
        else:
            os.environ["AXS_TEST_WORKERS"] = saved


def check_order_and_color():
    numbers = {"b": 2, "a": 1}
    os.environ["AXS_COLOR"] = "never"
    plain = nodetest.render_rows(numbers, [("b", None, "超时"), ("a", 12, "")], True)
    if plain != "测速（全部叶子）\nN1 a 12ms\nN2 b 超时\n":
        fail(plain)
    os.environ["AXS_COLOR"] = "always"
    colored = nodetest.render_rows(numbers, [( "a", 12, ""), ("b", None, "超时")], False)
    if "\033[32m12ms\033[0m" not in colored or "\033[31m超时\033[0m" not in colored:
        fail(colored)
    if colored.startswith("测速"):
        fail("single has title")
    os.environ["AXS_COLOR"] = "never"


def check_measure(tmp):
    fake = Path(tmp) / "fake"
    fake.mkdir()
    (fake / "delay.json").write_text('{"甲": 12, "乙": "timeout"}\n', encoding="utf-8")
    saved = os.environ.get("AXS_FAKE_DIR")
    os.environ["AXS_FAKE_DIR"] = str(fake)
    try:
        delay, reason = leafdelay.proxy_delay("test-secret-value", "127.0.0.1:9", "甲", "http://127.0.0.1/x", 60)
        if delay != 12 or reason:
            fail(f"measure {delay} {reason}")
        delay, reason = leafdelay.proxy_delay("test-secret-value", "127.0.0.1:9", "乙", "http://127.0.0.1/x", 60)
        if delay is not None or reason != "超时":
            fail(f"timeout {delay} {reason}")
        log = (fake / "log").read_text(encoding="utf-8")
        if "/proxies/" not in log or "delay?timeout=5000" not in log:
            fail(log)
    finally:
        if saved is None:
            os.environ.pop("AXS_FAKE_DIR", None)
        else:
            os.environ["AXS_FAKE_DIR"] = saved


def check_cache(tmp):
    dest = Path(tmp) / "cache" / "node-test"
    write_node_cache(dest, "PROXY", ["a 34", "b 超时", "PROXY 9"])
    write_node_cache(dest, "PROXY", ["a 10"])
    body = dest.read_text(encoding="utf-8")
    if '"b"' in body or '"PROXY"' in body.split("result=", 1)[-1]:
        fail(body)
    data = json.loads([line for line in body.splitlines() if line.startswith("{")][0])
    if data != {"a": 10}:
        fail(data)
    write_node_cache(dest, "", ["c 7"], False)
    body = dest.read_text(encoding="utf-8")
    if "result=fail" not in body:
        fail(body)
    data = json.loads([line for line in body.splitlines() if line.startswith("{")][0])
    if data != {"a": 10, "c": 7}:
        fail(data)
    run = Path(tmp)
    # load_delays reads run/cache/node-test; dest is already there.
    if load_delays(run) != {"a": 10, "c": 7}:
        fail(load_delays(run))


def _call(argv):
    out, err = io.StringIO(), io.StringIO()
    code = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            cli_main(argv)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
    return code, out.getvalue(), err.getvalue()


def check_cli():
    code, _out, err = _call(["node", "test"])
    if code != USAGE or "axs node test" not in err:
        fail(f"bare {code} {err}")
    code, _out, err = _call(["node", "test", "--all"])
    if code != DOWN or err != "服务：未运行\n":
        fail(f"down {code} {err}")
    code, _out, err = _call(["node", "t", "N1", "extra"])
    if code != USAGE or "axs node test" not in err:
        fail(f"extra {code} {err}")


def main():
    os.environ["AXS_COLOR"] = "never"
    check_resolve()
    check_workers()
    check_order_and_color()
    check_cli()
    with tempfile.TemporaryDirectory(prefix="axs-nodetest-") as tmp:
        check_measure(tmp)
        check_cache(tmp)
    print("nodetest ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
