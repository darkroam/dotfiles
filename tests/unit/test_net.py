#!/usr/bin/env python3
"""net_targets, precheck exits, and egress refusal. No dial."""
import contextlib
import io
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.net import DEFAULT_URLS, _ip_reason, _ip_timeout, _net_reason, _net_table, _net_timeout_ms, egress, net_precheck, net_run, net_targets  # noqa: E402
import ssl
import urllib.error


def fail(message):
    raise SystemExit(message)


def expect(action, code):
    try:
        action()
    except SystemExit as exc:
        if exc.code != code:
            fail(f"exit {exc.code} want {code}")
        return
    if code != 0:
        fail(f"wanted exit {code}")


def check_targets(tmp):
    urls = Path(tmp) / "urls"
    if net_targets(urls, ["http://127.0.0.1/a"]) != ["http://127.0.0.1/a"]:
        fail("given")
    urls.write_text("# skip\n\nhttp://127.0.0.1/b\n", encoding="utf-8")
    if net_targets(urls, []) != ["http://127.0.0.1/b"]:
        fail("file")
    if net_targets(Path(tmp) / "missing", []) != list(DEFAULT_URLS):
        fail("default")


def check_precheck(tmp):
    missing = Path(tmp) / "missing"
    os.environ.pop("AXS_FORBID_NET", None)
    expect(lambda: net_precheck(missing, ["ftp://127.0.0.1/"]), 1)
    expect(lambda: net_precheck(missing, ["https://example.test/"]), 0)
    os.environ["AXS_FORBID_NET"] = "1"
    expect(lambda: net_precheck(missing, ["https://example.test/"]), 3)
    expect(lambda: net_precheck(missing, ["http://127.0.0.1/"]), 0)


def check_table():
    os.environ["AXS_COLOR"] = "never"
    ok = _net_table([("通", "12ms", "http://127.0.0.1/ok", "")])
    golden = (ROOT / "tests" / "golden" / "network-test--ok.txt").read_text(encoding="utf-8")
    if golden != "exit: 0\n--- stdout\n" + ok + "--- stderr\n":
        fail(ok)
    plain = _net_table([
        ("通", "12ms", "http://127.0.0.1/ok", ""),
        ("不通", "-", "http://127.0.0.1/no", "超时"),
    ])
    want = (
        "连通性（经代理）\n"
        "结果  延迟  目标                 原因\n"
        "通    12ms  http://127.0.0.1/ok\n"
        "不通     -  http://127.0.0.1/no  超时\n"
    )
    if plain != want:
        fail(plain)
    os.environ["AXS_COLOR"] = "always"
    colored = _net_table([
        ("通", "3ms", "http://127.0.0.1/ok", ""),
        ("不通", "-", "http://127.0.0.1/no", "超时"),
    ])
    if "\033[32m通\033[0m" not in colored or "\033[31m不通\033[0m" not in colored or "\033[90m-\033[0m" not in colored:
        fail(colored)


def check_egress():
    os.environ["AXS_FORBID_NET"] = "1"
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        expect(lambda: egress("http://127.0.0.1:9", "http://127.0.0.1/"), 3)
    if err.getvalue() != "公网地址查询被禁止（AXS_FORBID_NET=1）\n":
        fail(err.getvalue())
    os.environ.pop("AXS_FORBID_NET", None)
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        expect(lambda: egress("http://127.0.0.1:9", "http://127.0.0.1:9/ip"), 3)
    if err.getvalue() != "公网地址查询失败（http://127.0.0.1:9/ip）：连接失败\n":
        fail(err.getvalue())
    if _net_reason(urllib.error.URLError(TimeoutError())) != "超时":
        fail("timeout class")
    if _net_reason(urllib.error.URLError(ConnectionRefusedError())) != "拒绝":
        fail("refused class")
    if _ip_reason(urllib.error.HTTPError("http://127.0.0.1/", 502, "bad", {}, None)) != "HTTP 502":
        fail("http class")
    if _ip_reason(urllib.error.URLError(TimeoutError())) != "超时":
        fail("ip timeout class")
    if _net_reason(urllib.error.URLError(ssl.SSLError("certificate verify failed"))) != "SSL":
        fail("ssl class")


def check_timeouts():
    saved = os.environ.pop("AXS_NET_TIMEOUT_MS", None)
    try:
        if _net_timeout_ms(5000) != 5000 or _ip_timeout() != 10:
            fail("timeout default")
        for raw in ("abc", "-3", "0"):
            os.environ["AXS_NET_TIMEOUT_MS"] = raw
            if _net_timeout_ms(5000) != 5000 or _ip_timeout() != 10:
                fail(f"timeout fallback {raw}")
        os.environ["AXS_NET_TIMEOUT_MS"] = "2500"
        if _net_timeout_ms(5000) != 2500 or _ip_timeout() != 2.5:
            fail("timeout 2500")
    finally:
        if saved is None:
            os.environ.pop("AXS_NET_TIMEOUT_MS", None)
        else:
            os.environ["AXS_NET_TIMEOUT_MS"] = saved


def check_fake_reason(tmp):
    fake = Path(tmp) / "fake"
    fake.mkdir()
    (fake / "net-result").write_text("拒绝\n", encoding="utf-8")
    os.environ["AXS_FAKE_DIR"] = str(fake)
    os.environ["AXS_COLOR"] = "never"
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        expect(lambda: net_run(Path(tmp) / "missing", "http://127.0.0.1:9", "200", ["http://127.0.0.1:9/"]), 3)
    if "拒绝" not in buf.getvalue():
        fail(buf.getvalue())
    os.environ.pop("AXS_FAKE_DIR", None)


def check_forward():
    if (ROOT / "lib" / "common.sh").exists():
        fail("shell remains")
    from axs.proxy import proxy_user
    if proxy_user.__module__ != "axs.proxy":
        fail("proxy module")


def main():
    saved = os.environ.get("AXS_FORBID_NET")
    try:
        with tempfile.TemporaryDirectory(prefix="axs-net-") as tmp:
            check_targets(tmp)
            check_precheck(tmp)
            check_fake_reason(tmp)
        check_table()
        check_egress()
        check_timeouts()
        check_forward()
    finally:
        if saved is None:
            os.environ.pop("AXS_FORBID_NET", None)
        else:
            os.environ["AXS_FORBID_NET"] = saved
    print("net unit")
    return 0


if __name__ == "__main__":
    sys.exit(main())
