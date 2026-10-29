#!/usr/bin/env python3
"""Leaf delay tests, cache merge, and stable output order."""
import contextlib
import io
import json
import os
import sys
import tempfile
from pathlib import Path

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))

from axs.cli import main as cli_main
from axs.codes import DOWN, FAIL, USAGE
from axs.nodes import load_delays, node_numbers, write_node_cache
import axs.speed as nodetest
import axs.speed as grouptest
import axs.speed as leafdelay
from axs.nodelist import render_test_rows


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
        if nodetest.workers() != 8:
            fail("default workers")
        for raw in ("0", "33", "abc", "-1", ""):
            os.environ["AXS_TEST_WORKERS"] = raw
            if nodetest.workers() != 8:
                fail("bad workers " + raw)
        os.environ["AXS_TEST_WORKERS"] = "3"
        if nodetest.workers() != 3:
            fail("workers 3")
    finally:
        if saved is None:
            os.environ.pop("AXS_TEST_WORKERS", None)
        else:
            os.environ["AXS_TEST_WORKERS"] = saved


def check_order_and_color():
    numbers = {"b": 2, "a": 1}
    rows = [("b", None, "超时"), ("a", 12, "")]
    os.environ["AXS_COLOR"] = "never"
    os.environ["COLUMNS"] = "80"
    wide = render_test_rows(numbers, rows, True)
    if wide != "测速（全部叶子）\nN1 a 12ms  N2 b 超时\n":
        fail(wide)
    os.environ["COLUMNS"] = "10"
    narrow = render_test_rows(numbers, rows, True)
    if narrow != "测速（全部叶子）\nN1 a 12ms\nN2 b 超时\n":
        fail(narrow)
    os.environ["AXS_COLOR"] = "always"
    os.environ["COLUMNS"] = "80"
    colored = render_test_rows(numbers, [("a", 12, ""), ("b", None, "超时")], False)
    if "\033[32m12ms\033[0m" not in colored or "\033[31m超时\033[0m" not in colored:
        fail(colored)
    if colored.startswith("测速"):
        fail("single has title")
    os.environ["AXS_COLOR"] = "never"


def check_filter():
    proxies = {
        "主代理": {"type": "Selector", "all": ["a", "剩余流量：1", "pass"], "now": "a"},
        "a": {"type": "Shadowsocks"},
        "剩余流量：1": {"type": "Shadowsocks"},
        "剩余流量:2": {"type": "Shadowsocks"},
        "网址：z": {"type": "Shadowsocks"},
        "过期时间:z": {"type": "Shadowsocks"},
        "回家页：z": {"type": "Shadowsocks"},
        "pass": {"type": "Pass"},
        "drop": {"type": "RejectDrop"},
        "rej": {"type": "Reject"},
        "comp": {"type": "Compatible"},
        "DIRECT": {"type": "Direct"},
    }
    numbers = node_numbers(proxies)
    kept = [name for name in sorted(numbers, key=numbers.get) if nodetest.testable(name, proxies)]
    if kept != ["DIRECT", "a"]:
        fail(kept)


def check_quiet(tmp):
    fake = Path(tmp) / "fake"
    fake.mkdir()
    (fake / "delay.json").write_text('{"a": 12}\n', encoding="utf-8")
    saved = os.environ.get("AXS_FAKE_DIR")
    os.environ["AXS_FAKE_DIR"] = str(fake)
    proxies = {
        "GLOBAL": {"type": "Selector", "all": ["a", "b"], "now": "a"},
        "主代理": {"type": "Selector", "all": ["a"], "now": "a"},
        "自动": {"type": "URLTest", "all": ["b"], "now": "b"},
        "a": {"type": "Shadowsocks"},
        "b": {"type": "Shadowsocks"},
    }
    err = io.StringIO()
    try:
        chosen, skipped = nodetest.partition(proxies)
        with contextlib.redirect_stderr(err):
            rows = nodetest.run_tests(
                "test-secret-value", "127.0.0.1:9", chosen, "http://127.0.0.1/x", True,
            )
        log = (fake / "log").read_text(encoding="utf-8")
    finally:
        if saved is None:
            os.environ.pop("AXS_FAKE_DIR", None)
        else:
            os.environ["AXS_FAKE_DIR"] = saved
    rows.extend((name, None, "不可选") for name in skipped)
    if chosen != ["a"] or skipped != ["b"] or rows != [("a", 12, ""), ("b", None, "不可选")]:
        fail((chosen, skipped, rows))
    if err.getvalue():
        fail("progress " + err.getvalue())
    if "/proxies/a/delay" not in log or "/group/" in log or "/proxies/b/" in log:
        fail(log)


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


def check_http():
    def boom(*_args, **_kwargs):
        if not nodetest._QUIET.get():
            raise SystemExit("loud")
        raise SystemExit("控制器失败：HTTP 503")

    original = nodetest.request
    nodetest.request = boom
    try:
        got = nodetest.one_delay("s", "127.0.0.1:9", "a", "http://127.0.0.1/x", 5)
    finally:
        nodetest.request = original
    if got != (None, "不可测"):
        fail(got)


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


def check_leaf_workers():
    os.environ["AXS_TEST_WORKERS"] = "3"
    if leafdelay.workers() != 3:
        fail("workers env")
    for raw in ("", "no", "0", "-1", "33"):
        os.environ["AXS_TEST_WORKERS"] = raw
        if leafdelay.workers() != 8:
            fail("workers fallback " + raw)
    os.environ.pop("AXS_TEST_WORKERS", None)


def check_delay_ms():
    if leafdelay.delay_ms() != 5000:
        fail("delay_ms default")
    os.environ["AXS_DELAY_TIMEOUT_MS"] = "2500"
    if leafdelay.delay_ms() != 2500:
        fail("delay_ms env")
    for raw in ("no", "0", "-3"):
        os.environ["AXS_DELAY_TIMEOUT_MS"] = raw
        if leafdelay.delay_ms() != 5000:
            fail("delay_ms fallback " + raw)
    os.environ.pop("AXS_DELAY_TIMEOUT_MS", None)


def check_delay_timeout():
    if leafdelay.delay_timeout() != 60:
        fail("delay timeout default")
    os.environ["AXS_DELAY_TIMEOUT"] = "15"
    if leafdelay.delay_timeout() != 15:
        fail("delay timeout env")
    for raw in ("no", "0", "-3"):
        os.environ["AXS_DELAY_TIMEOUT"] = raw
        if leafdelay.delay_timeout() != 60:
            fail("delay timeout fallback " + raw)
    os.environ.pop("AXS_DELAY_TIMEOUT", None)


def check_classify():
    if leafdelay.classify("控制器失败：HTTP 503") != "不可测":
        fail("503")
    if leafdelay.classify("控制器失败：HTTP 504") != "超时":
        fail("504")
    if leafdelay.classify("控制器失败：HTTP 500") != "HTTP 500":
        fail("500")
    if leafdelay.classify("") != "超时":
        fail("empty")



def check_args():
    code, _out, err = _call(["group", "test"])
    if code != USAGE or "axs group test" not in err:
        fail(f"bare {code} {err}")
    code, _out, err = _call(["g", "test", "--all", "主代理"])
    if code != USAGE or "axs group test" not in err:
        fail(f"mix {code} {err}")
    code, _out, err = _call(["group", "test", "--all"])
    if code != DOWN or err != "服务：未运行\n":
        fail(f"down {code} {err}")
    proxies = {
        "1": {"type": "Selector", "all": ["a"], "now": "a"},
        "主代理": {"type": "Selector", "all": ["a"], "now": "a"},
        "a": {"type": "Shadowsocks"},
    }
    if grouptest.resolve_test_group(proxies, "1") != ("1", ""):
        fail("digit name")
    if grouptest.resolve_test_group(proxies, "2") != (None, "usage"):
        fail("bare digit")
    if grouptest.resolve_test_group(proxies, "g2")[0] != "主代理":
        fail(grouptest.resolve_test_group(proxies, "g2"))
    if grouptest.resolve_test_group(proxies, "G1") != ("1", ""):
        fail("G1 should be the digit-named group")


def check_all(tmp):
    fake = Path(tmp) / "fake"
    fake.mkdir()
    (fake / "delay.json").write_text('{"a": 12}\n', encoding="utf-8")
    proxies = {
        "GLOBAL": {"type": "Selector", "all": ["a"], "now": "a"},
        "主代理": {"type": "Selector", "all": ["a"], "now": "a"},
        "自动": {"type": "URLTest", "all": ["a"], "now": "a"},
        "a": {"type": "Shadowsocks"},
    }
    saved = os.environ.get("AXS_FAKE_DIR")
    os.environ["AXS_FAKE_DIR"] = str(fake)
    os.environ["AXS_COLOR"] = "never"
    out, err = io.StringIO(), io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            grouptest._all(tmp, "test-secret-value", "127.0.0.1:9", proxies, "http://127.0.0.1/x")
    finally:
        if saved is None:
            os.environ.pop("AXS_FAKE_DIR", None)
        else:
            os.environ["AXS_FAKE_DIR"] = saved
    text = (
        "G1 GLOBAL [Selector]\n"
        "└─ a 12\n"
        "\n"
        "G2 主代理 [Selector]\n"
        "└─ a 12\n"
        "\n"
        "G3 自动 [URLTest]\n"
        "└─ a 12\n"
    )
    if out.getvalue() != text:
        fail(out.getvalue())
    if err.getvalue():
        fail("progress " + err.getvalue())
    log = (fake / "log").read_text(encoding="utf-8")
    if log.count("/group/") != 3:
        fail(log)


def check_continue(tmp):
    import urllib.parse

    from axs.codes import FAIL
    from axs.mihomo import _fail

    fake = Path(tmp) / "fake"
    fake.mkdir()
    (fake / "delay.json").write_text('{"a": 12}\n', encoding="utf-8")
    cache = Path(tmp) / "cache" / "node-test"
    cache.parent.mkdir()
    cache.write_text("ts=1\nresult=ok\n{\"keep\": 9}\n", encoding="utf-8")
    proxies = {
        "A": {"type": "Selector", "all": ["a"], "now": "a"},
        "B": {"type": "Selector", "all": ["a"], "now": "a"},
        "C": {"type": "URLTest", "all": ["a"], "now": "a"},
        "a": {"type": "Shadowsocks"},
    }
    original = grouptest.request

    def request(secret, api, method, path, body=None, timeout=5):
        pure = path.split("?", 1)[0]
        name = urllib.parse.unquote(pure[len("/group/"): -len("/delay")])
        if name == "B":
            _fail("控制器失败：HTTP 504")
        return original(secret, api, method, path, body, timeout)

    saved = os.environ.get("AXS_FAKE_DIR")
    os.environ["AXS_FAKE_DIR"] = str(fake)
    os.environ["AXS_COLOR"] = "never"
    grouptest.request = request
    out, err = io.StringIO(), io.StringIO()
    code = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            grouptest._all(tmp, "test-secret-value", "127.0.0.1:9", proxies, "http://127.0.0.1/x")
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
    finally:
        grouptest.request = original
        if saved is None:
            os.environ.pop("AXS_FAKE_DIR", None)
        else:
            os.environ["AXS_FAKE_DIR"] = saved
    text = (
        "G1 A [Selector]\n"
        "└─ a 12\n"
        "\n"
        "G2 B [Selector]\n"
        "└─ 控制器失败：HTTP 504\n"
        "\n"
        "G3 C [URLTest]\n"
        "└─ a 12\n"
    )
    if code != FAIL or out.getvalue() != text or err.getvalue():
        fail((code, out.getvalue(), err.getvalue()))
    log = (fake / "log").read_text(encoding="utf-8")
    if "/group/A/" not in log or "/group/C/" not in log:
        fail(log)
    body = cache.read_text(encoding="utf-8")
    if "result=fail" not in body or '"keep": 9' not in body or '"a": 12' not in body:
        fail(body)


def check_columns():
    from axs.nodelist import render_group_block

    numbers = {"child": 1, "主代理": 2}
    members = [("child", 5, True), ("a", 12, False), ("b", 80, False)]
    os.environ["AXS_COLOR"] = "never"
    os.environ["COLUMNS"] = "80"
    wide = render_group_block(numbers, "主代理", "Selector", members)
    if wide != "G2 主代理 [Selector]\n├─ child 5\n└─ a 12  b 80":
        fail(wide)
    os.environ["COLUMNS"] = "12"
    narrow = render_group_block(numbers, "主代理", "Selector", members)
    if narrow != "G2 主代理 [Selector]\n├─ child 5\n└─ a 12\n   b 80":
        fail(narrow)
    os.environ["COLUMNS"] = "80"




def main():
    os.environ["AXS_COLOR"] = "never"
    os.environ["COLUMNS"] = "80"
    check_resolve()
    check_workers()
    check_leaf_workers()
    check_delay_ms()
    check_delay_timeout()
    check_classify()
    check_order_and_color()
    check_http()
    check_cli()
    check_args()
    check_columns()
    with tempfile.TemporaryDirectory(prefix="axs-nodetest-") as tmp:
        check_filter()
        check_quiet(tmp)
        check_cache(tmp)
    with tempfile.TemporaryDirectory(prefix="axs-grouptest-") as tmp:
        check_all(tmp)
    with tempfile.TemporaryDirectory(prefix="axs-grouptest-") as tmp:
        check_continue(tmp)
    print("speed ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
