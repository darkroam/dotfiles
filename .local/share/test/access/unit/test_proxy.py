#!/usr/bin/env python3
"""Proxy flag lifecycle, a missing hook, and the three session effects."""
import contextlib
import io
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))

from axs.config import LEGACY_SESSION_FLAG, LEGACY_SYSTEM_FLAG, SESSION_FLAG, SYSTEM_FLAG  # noqa: E402
from axs.core import session_value  # noqa: E402
from axs.proxy import proxy_session, proxy_system  # noqa: E402


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
        def spawn(env, ready):
            proc = subprocess.Popen(["/bin/sleep", "30"], env=env)
            procs.append(proc)
            os.environ["AXS_SESSION_PID"] = str(proc.pid)
            deadline = time.monotonic() + 2
            last = None
            while time.monotonic() < deadline:
                if proc.poll() is not None:
                    fail("sleep exited before environ")
                try:
                    last = session_value("http_proxy")
                except OSError:
                    last = None
                if ready(last):
                    return
                time.sleep(0.02)
            fail(f"environ {last}")

        minimal = {"PATH": "/usr/bin"}
        spawn(minimal, lambda got: got == (1, ""))
        spawn({**minimal, "http_proxy": "http://127.0.0.1:9"}, lambda got: got == (0, "http://127.0.0.1:9"))
    finally:
        for proc in procs:
            proc.kill()
            proc.wait()
        if saved is None:
            os.environ.pop("AXS_SESSION_PID", None)
        else:
            os.environ["AXS_SESSION_PID"] = saved


def check_status_source():
    service = (ROOT / "axs" / "service.py").read_text(encoding="utf-8")
    source = (ROOT / "axs" / "status.py").read_text(encoding="utf-8")
    proxy = (ROOT / "axs" / "proxy.py").read_text(encoding="utf-8")
    core = (ROOT / "axs" / "core.py").read_text(encoding="utf-8")
    if "session_env" in service or "pgrep" in service or "session_env" in source or "pgrep" in source:
        fail("service still reads the session itself")
    if "status_summary" in service or "status_summary" in source or "status_summary" in proxy:
        fail("old status summary remains")
    if "proxy_status_rows" not in source or "proxy_status_rows" not in proxy or "session_value(" not in proxy:
        fail("status does not share proxy rows")
    if "def session_value" not in core:
        fail("session probe left proxy")


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
