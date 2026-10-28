#!/usr/bin/env python3
"""Delay helper guards."""
import os
import sys
from pathlib import Path

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))

from axs import leafdelay


def fail(message):
    raise SystemExit(message)


def check_workers():
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


def main():
    check_workers()
    check_delay_ms()
    check_delay_timeout()
    check_classify()
    print("leafdelay ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
