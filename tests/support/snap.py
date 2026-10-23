#!/usr/bin/env python3
"""Write or check plain-text golden snapshots. Does not change axs."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOLDEN = ROOT / "tests" / "golden"
DATE = r"""#!/bin/sh
set -eu
if [ "${1:-}" = "+%s" ]; then printf '%s\n' 1700000000; exit 0; fi
spec=${2:-}
case $spec in @*) spec=${spec#@} ;; esac
if [ "${1:-}" = "-d" ] && [ "${3:-}" = "+%H:%M" ]; then exec /bin/date -d "@$spec" +%H:%M; fi
if [ "${1:-}" = "-d" ] && [ "${3:-}" = "+%s" ]; then printf '%s\n' "$spec"; exit 0; fi
printf '%s\n' "frozen-date: $*" >&2
exit 1
"""
PROXIES = (
    '{"proxies":{"主代理":{"all":["a","b"],"now":"a","type":"Selector"},'
    '"a":{"type":"Shadowsocks"},"b":{"type":"Shadowsocks"}}}\n'
)


def record(result):
    return (
        f"exit: {result.returncode}\n--- stdout\n{result.stdout}"
        f"--- stderr\n{result.stderr}"
    )


def prepare(tmp, case):
    base = Path(tmp)
    run, fake, home, bindir = (base / n for n in ("run", "run/fake", "home", "bin"))
    for path in (fake, home, bindir):
        path.mkdir(parents=True)
    date = bindir / "date"
    date.write_text(DATE, encoding="utf-8")
    date.chmod(0o755)
    os.symlink(ROOT / "tests" / "fake-gsettings", bindir / "gsettings")
    env = {
        "PATH": f"{bindir}:{os.environ.get('PATH', '/usr/bin')}",
        "HOME": str(home),
        "TZ": "UTC",
        "LANG": "C.UTF-8",
        "AXS_RUN": str(run),
        "AXS_FAKE_DIR": str(fake),
        "AXS_FORBID_NET": "1",
        "AXS_COLOR": "never",
        "AXS_SYSTEMD": "1" if case.get("systemd") else "0",
        "AXS_MIXED_PORT": "18080",
        "AXS_API": "127.0.0.1:18081",
        "AXS_SESSION_PID": "2147483001",
        "AXS_XPROFILE": str(home / "missing-xprofile"),
        "AXS_GS_DB": str(base / "gs"),
        "COLUMNS": "80",
    }
    (base / "gs").mkdir()
    proc = None
    if case.get("systemd"):
        env["AXS_SYSTEMCTL"] = str(ROOT / "tests" / "fake-systemctl")
    if case.get("up"):
        proc = subprocess.Popen(
            [str(ROOT / "tests" / "fake-mihomo")],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        (run / "mihomo.pid").write_text(f"{proc.pid}\n", encoding="utf-8")
        env["AXS_MIHOMO"] = str(ROOT / "tests" / "fake-mihomo")
        (fake / "proxies.json").write_text(PROXIES, encoding="utf-8")
        (run / "secret").write_text("test-secret-value\n", encoding="utf-8")
    if case.get("expired"):
        (run / "userinfo").write_text("expire=1\n", encoding="utf-8")
    if case.get("session_flag"):
        (run / "proxy-session.flag").write_text("", encoding="utf-8")
    return env, proc


def run_case(case):
    with tempfile.TemporaryDirectory(prefix="axs-golden-") as tmp:
        env, proc = prepare(tmp, case)
        try:
            result = subprocess.run(
                [str(ROOT / "bin" / "axs"), *case["argv"]],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
        finally:
            if proc is not None:
                proc.kill()
                proc.wait()
    return record(result)


def main(argv):
    mode = argv[1] if len(argv) > 1 else "check"
    cases = json.loads((GOLDEN / "cases.json").read_text(encoding="utf-8"))
    failed = 0
    for case in cases:
        got = run_case(case)
        path = GOLDEN / case["name"]
        if mode == "write":
            path.write_text(got, encoding="utf-8")
        elif path.read_text(encoding="utf-8") != got:
            print(f"golden mismatch: {case['name']}", file=sys.stderr)
            failed += 1
    if failed:
        return 1
    print(f"golden {mode} {len(cases)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
