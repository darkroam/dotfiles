#!/usr/bin/env python3
"""proxy lan: --yes, on/off keys, and loopback rollback."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))

from axs.config import OVERRIDE  # noqa: E402


def fail(message):
    raise SystemExit(message)


def capture(argv):
    env = os.environ.copy()
    env["PYTHONPATH"] = str(ROOT)
    proc = subprocess.run(
        [sys.executable, "-c", "import sys; from axs.cli import main; main(sys.argv[1:])", *argv],
        cwd=ROOT, env=env, text=True, capture_output=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


def main():
    body = (
        "mixed-port: 18080\n"
        "external-controller: 127.0.0.1:18081\n"
        "allow-lan: false\n"
        "mode: rule\n"
        "keep: 1\n"
    )
    saved = {key: os.environ.get(key) for key in ("AXS_RUN", "AXS_FAKE_DIR", "AXS_COLOR", "AXS_SYSTEMD")}
    with tempfile.TemporaryDirectory(prefix="axs-lan-") as tmp:
        run = Path(tmp) / "run"
        fake = run / "fake"
        fake.mkdir(parents=True)
        (run / OVERRIDE).write_text(body, encoding="utf-8")
        (run / "secret").write_text("test-secret-value\n", encoding="utf-8")
        (run / "config.yaml").write_text("mode: rule\n", encoding="utf-8")
        (run / "subscription.yaml").write_text(
            (TEST / "fixtures/subscription.yaml").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        (fake / "reload").write_text("204\n", encoding="utf-8")
        os.environ["AXS_RUN"] = str(run)
        os.environ["AXS_FAKE_DIR"] = str(fake)
        os.environ["AXS_COLOR"] = "never"
        os.environ["AXS_SYSTEMD"] = "0"
        try:
            code, _out, err = capture(["proxy", "lan", "on"])
            if code != 1 or "确认后加 --yes" not in err or "用法：axs proxy lan" not in err:
                fail(f"yes {code} {err!r}")
            if (run / OVERRIDE).read_text(encoding="utf-8") != body:
                fail("yes wrote override")
            code, _out, err = capture(["proxy", "lan", "on", "--yes"])
            if code != 3 or "已恢复 override" not in err or (run / OVERRIDE).read_text(encoding="utf-8") != body:
                fail(f"rollback {code} {err!r}")
            if (run / "config.yaml").read_text(encoding="utf-8") != "mode: rule\n":
                fail("rollback config")
            (fake / "open-ports").write_text("18080\n", encoding="utf-8")
            code, out, err = capture(["proxy", "lan", "on", "--yes"])
            data = yaml.safe_load((run / OVERRIDE).read_text(encoding="utf-8"))
            if code or err or data["keep"] != 1 or data["allow-lan"] is not True or data["bind-address"] != "*":
                fail(f"on {code} {err!r} {data!r}")
            if data["mode"] != "rule" or data["mixed-port"] != 18080:
                fail("on dropped keys")
            merged = yaml.safe_load((run / "config.yaml").read_text(encoding="utf-8"))
            if merged.get("allow-lan") is not True or merged.get("bind-address") != "*":
                fail(f"merged {merged.get('allow-lan')!r} {merged.get('bind-address')!r}")
            code, out, err = capture(["proxy", "lan", "status"])
            if code or err or "allow-lan  true" not in out or "bind       *" not in out:
                fail(f"status on {code} {out!r} {err!r}")
            if "端口       18080" not in out or "LAN" not in out or "混合端口无认证" not in out:
                fail(f"status fields {out!r}")
            code, out, err = capture(["proxy", "lan", "off"])
            data = yaml.safe_load((run / OVERRIDE).read_text(encoding="utf-8"))
            if code or err or data["allow-lan"] is not False or data["bind-address"] != "127.0.0.1" or data["keep"] != 1:
                fail(f"off {code} {err!r} {data!r}")
            code, out, _err = capture(["proxy", "status"])
            if code or "lan       off (allow-lan false · bind 127.0.0.1)" not in out:
                fail(f"summary {code} {out!r}")
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
    print("proxylan ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
