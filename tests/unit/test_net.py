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

from axs.net import DEFAULT_URLS, egress, net_precheck, net_targets  # noqa: E402


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


def check_egress():
    os.environ["AXS_FORBID_NET"] = "1"
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        expect(lambda: egress("http://127.0.0.1:9", "http://127.0.0.1/"), 3)
    if err.getvalue() != "出口查询失败\n":
        fail(err.getvalue())


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
        check_egress()
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
