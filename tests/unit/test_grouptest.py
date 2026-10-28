#!/usr/bin/env python3
"""Group test arguments, sections, and a quiet progress bar."""
import contextlib
import io
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.cli import main as cli_main
from axs.codes import DOWN, USAGE
from axs import grouptest


def fail(message):
    raise SystemExit(message)


def _call(argv):
    out, err = io.StringIO(), io.StringIO()
    code = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            cli_main(argv)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
    return code, out.getvalue(), err.getvalue()


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
        "a 12\n"
        "G2 主代理 [Selector]\n"
        "a 12\n"
        "G3 自动 [URLTest]\n"
        "a 12\n"
    )
    if out.getvalue() != text:
        fail(out.getvalue())
    if err.getvalue():
        fail("progress " + err.getvalue())
    log = (fake / "log").read_text(encoding="utf-8")
    if log.count("/group/") != 3:
        fail(log)


def main():
    os.environ["AXS_COLOR"] = "never"
    check_args()
    with tempfile.TemporaryDirectory(prefix="axs-grouptest-") as tmp:
        check_all(tmp)
    print("grouptest ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
