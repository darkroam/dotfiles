#!/usr/bin/env python3
"""Service exits that do not need a controller."""
import contextlib
import io
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.codes import DOWN, FAIL, USAGE  # noqa: E402
from axs.routes import build  # noqa: E402
from axs.rulelist import status_text  # noqa: E402
from axs.service import (  # noqa: E402
    boot,
    clean,
    ensure,
    health,
    node_status_lines,
    start,
    write_node_status,
)


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


def main():
    os.environ["AXS_COLOR"] = "never"
    os.environ["AXS_SYSTEMD"] = "0"
    os.environ["AXS_MIXED_PORT"] = "9"
    os.environ["AXS_API"] = "127.0.0.1:9"
    with tempfile.TemporaryDirectory(prefix="axs-service-") as tmp:
        run = Path(tmp)
        fake = run / "fake"
        fake.mkdir()
        os.environ["AXS_FAKE_DIR"] = str(fake)
        code, _out, err = capture(health, run)
        if code != DOWN or err != "未运行\n":
            fail(f"health down {code} {err!r}")
        code, _out, err = capture(start, run)
        if code != FAIL or "没有配置" not in err:
            fail(f"start {code} {err!r}")
        code, _out, err = capture(ensure, run, ["extra"])
        if code != USAGE or "用法错误" not in err:
            fail(f"ensure {code} {err!r}")
        code, out, err = capture(clean, run, "config", ["--yes"])
        if code or out or err:
            fail(f"clean {code} {out!r} {err!r}")
        code, _out, err = capture(boot, run, "enable")
        if code != FAIL or "没有 systemd" not in err:
            fail(f"boot {code} {err!r}")
        check_rule_view()
    print("service unit")
    return 0



def check_rule_view():
    proxies = {
        "入口": {"type": "Selector", "now": "自动", "all": ["自动"]},
        "旁路": {"type": "Selector", "now": "自动", "all": ["自动"]},
        "自动": {"type": "URLTest", "now": "乙", "all": ["甲", "乙"]},
        "均衡": {"type": "LoadBalance", "all": ["甲"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Shadowsocks"},
    }
    with tempfile.TemporaryDirectory(prefix="axs-route-view-") as tmp:
        run = Path(tmp)
        (run / "config.yaml").write_text(
            "rules:\n  - MATCH,入口\n  - DOMAIN,a.example,旁路\n",
            encoding="utf-8",
        )
        data = build(proxies, run)
        lines = node_status_lines(proxies, run)
        if lines != status_text(data).splitlines() or len(lines) != 2:
            fail("status lines\n" + "\n".join(lines))
        if any("[*]" in line or "个成员" in line for line in lines):
            fail("status kept members")
        if node_status_lines({}, run):
            fail("empty pool")
        code, out, err = capture(write_node_status, run, "")
        if code or err or "路径    -" not in out or "主代理" in out:
            fail(f"dash {code} {out!r} {err!r}")

if __name__ == "__main__":
    sys.exit(main())
