#!/usr/bin/env python3
"""Alias and prefix matrix. Step 1 will import the resolver instead of spawning axs."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AXS = str(ROOT / "bin" / "axs")


def run(argv):
    with tempfile.TemporaryDirectory(prefix="axs-alias-") as tmp:
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin"),
            "HOME": tmp,
            "LANG": "C.UTF-8",
            "AXS_RUN": tmp + "/run",
            "AXS_FAKE_DIR": tmp + "/fake",
            "AXS_FORBID_NET": "1",
            "AXS_COLOR": "never",
            "AXS_SYSTEMD": "0",
            "AXS_SESSION_PID": "2147483001",
            "AXS_MIXED_PORT": "18080",
            "AXS_API": "127.0.0.1:18081",
        }
        Path(env["AXS_RUN"]).mkdir()
        Path(env["AXS_FAKE_DIR"]).mkdir()
        result = subprocess.run([AXS, *argv], env=env, text=True, capture_output=True, check=False)
    return result.returncode, result.stdout, result.stderr


def expect(argv, code, out="", err="", err_has="", out_has="", err_lacks=""):
    got_code, got_out, got_err = run(argv)
    if got_code != code:
        raise SystemExit(f"{argv} exit {got_code} want {code}\n{got_err}{got_out}")
    if out != "" and got_out != out:
        raise SystemExit(f"{argv} stdout {got_out!r}")
    if err != "" and got_err != err:
        raise SystemExit(f"{argv} stderr {got_err!r}")
    if err_has and err_has not in got_err:
        raise SystemExit(f"{argv} stderr missing {err_has!r}\n{got_err}")
    if out_has and out_has not in got_out:
        raise SystemExit(f"{argv} stdout missing {out_has!r}\n{got_out}")
    if err_lacks and err_lacks in got_err:
        raise SystemExit(f"{argv} stderr has {err_lacks!r}\n{got_err}")


def main():
    # Exact alias wins over the prefix that would be ambiguous.
    expect(["s"], 2, out_has="服务", err_lacks="候选")
    expect(["status"], 2, out_has="服务", err_lacks="候选")
    expect(["k"], 2, out="", err="未运行\n")
    expect(["h"], 0, out_has="用法", err="")
    expect(["?"], 0, out_has="用法", err="")
    expect(["--help"], 0, out_has="用法")
    expect(["-h"], 0, out_has="用法")
    expect(["x"], 3, err_has="没有配置")
    expect(["o"], 0, out="", err="")
    # Full name, then the unique prefix of that name.
    expect(["ens"], 3, err_has="没有订阅")
    expect(["stat"], 2, out_has="服务", err_lacks="候选")
    expect(["n", "g"], 2, err="服务：未运行\n")
    expect(["node", "groups"], 2, err="服务：未运行\n")
    expect(["n", "gro"], 2, err="服务：未运行\n")
    expect(["p", "sy"], 1, err="用法\n")
    expect(["sub", "ge"], 0, out="未知\n")
    # Ambiguous prefix lists candidates and does not print usage.
    expect(["sta"], 1, err="候选：start status\n")
    expect(["st"], 1, err="候选：start stop status\n")
    expect(["he"], 1, err="候选：health help\n")
    # Unknown token prints usage, not candidates. "st" is not a prefix of system.
    expect(["nope"], 1, err_has="用法：axs", err_lacks="候选")
    expect(["p", "st"], 1, err_has="用法：axs", err_lacks="候选")
    print("alias matrix 21")
    return 0


if __name__ == "__main__":
    sys.exit(main())
