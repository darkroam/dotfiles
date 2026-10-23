#!/usr/bin/env python3
"""Proxy flag lifecycle, a missing hook, and the three session effects."""
import contextlib
import io
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.config import LEGACY_SESSION_FLAG, LEGACY_SYSTEM_FLAG, SESSION_FLAG, SYSTEM_FLAG  # noqa: E402
from axs.proxy import proxy_session, proxy_system, session_value  # noqa: E402


def fail(message):
    raise SystemExit(message)


def capture(func, *args):
    out, err = io.StringIO(), io.StringIO()
    code = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            func(*args)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
    return code, out.getvalue(), err.getvalue()


def check_flags(run):
    code, out, _err = capture(proxy_session, run, ["status"])
    if code != 1 or "disabled" not in out:
        fail(f"disabled {code} {out!r}")
    legacy = run / LEGACY_SESSION_FLAG
    legacy.write_text("old\n", encoding="utf-8")
    code, out, err = capture(proxy_session, run, ["enable"])
    if code or err or "enabled" not in out:
        fail(f"enable {code} {out!r} {err!r}")
    flag = run / SESSION_FLAG
    if not flag.is_file() or oct(flag.stat().st_mode)[-3:] != "600":
        fail("session flag mode")
    if legacy.exists():
        fail("legacy session remains")
    code, out, _err = capture(proxy_session, run, ["status"])
    if code != 1 or "xprofile hook missing" not in out:
        fail(f"hook {code} {out!r}")
    old = run / LEGACY_SYSTEM_FLAG
    old.write_text("old\n", encoding="utf-8")
    code, out, err = capture(proxy_system, run, ["enable"])
    if code or err or "enabled" not in out or old.exists():
        fail(f"system enable {code} {out!r} {err!r}")
    if not (run / SYSTEM_FLAG).is_file():
        fail("system flag")


def check_effects():
    saved = os.environ.get("AXS_SESSION_PID")
    procs = []
    try:
        os.environ["AXS_SESSION_PID"] = "2147483001"
        if session_value("http_proxy")[0] != 2:
            fail("missing pid")
        empty = subprocess.Popen(["/bin/sleep", "30"])
        procs.append(empty)
        os.environ["AXS_SESSION_PID"] = str(empty.pid)
        rc, value = session_value("http_proxy")
        if rc != 1 or value:
            fail(f"empty env {rc} {value!r}")
        live = subprocess.Popen(
            ["/bin/sleep", "30"],
            env={"PATH": os.environ.get("PATH", "/usr/bin"), "http_proxy": "http://127.0.0.1:9"},
        )
        procs.append(live)
        os.environ["AXS_SESSION_PID"] = str(live.pid)
        rc, value = session_value("http_proxy")
        if rc != 0 or value != "http://127.0.0.1:9":
            fail(f"live {rc} {value!r}")
    finally:
        for proc in procs:
            proc.kill()
            proc.wait()
        if saved is None:
            os.environ.pop("AXS_SESSION_PID", None)
        else:
            os.environ["AXS_SESSION_PID"] = saved


def check_status_source():
    source = (ROOT / "lib" / "axs" / "service.py").read_text(encoding="utf-8")
    proxy = (ROOT / "lib" / "axs" / "proxy.py").read_text(encoding="utf-8")
    if "session_env" in source or "pgrep" in source:
        fail("service still reads the session itself")
    if "status_summary" not in source or "def session_value" not in proxy:
        fail("status does not use session_value")


def main():
    os.environ["AXS_COLOR"] = "never"
    os.environ["AXS_XPROFILE"] = "/no/such/xprofile"
    with tempfile.TemporaryDirectory(prefix="axs-proxy-") as tmp:
        check_flags(Path(tmp))
    check_effects()
    check_status_source()
    print("proxy unit")
    return 0


if __name__ == "__main__":
    sys.exit(main())
