#!/usr/bin/env python3
"""Progress stays quiet off a TTY and never paints when color is off."""
import io
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.progress import Progress


def fail(message):
    raise SystemExit(message)


class Tty(io.StringIO):
    def isatty(self):
        return True


def _run(stream, color, progress):
    saved = sys.stderr, os.environ.get("AXS_COLOR"), os.environ.get("AXS_PROGRESS")
    sys.stderr = stream
    os.environ["AXS_COLOR"] = color
    if progress is None:
        os.environ.pop("AXS_PROGRESS", None)
    else:
        os.environ["AXS_PROGRESS"] = progress
    try:
        bar = Progress(2, "测速")
        bar.advance()
        bar.advance()
        bar.finish()
    finally:
        sys.stderr, color_was, progress_was = saved
        if color_was is None:
            os.environ.pop("AXS_COLOR", None)
        else:
            os.environ["AXS_COLOR"] = color_was
        if progress_was is None:
            os.environ.pop("AXS_PROGRESS", None)
        else:
            os.environ["AXS_PROGRESS"] = progress_was
    return stream.getvalue()


def main():
    os.environ["AXS_COLOR"] = "never"
    if _run(io.StringIO(), "never", None) != "":
        fail("non-tty wrote")
    if _run(Tty(), "never", "0") != "":
        fail("disabled wrote")
    plain = _run(Tty(), "never", None)
    if "\033" in plain or "测速 [" not in plain or not plain.endswith("\r"):
        fail(repr(plain))
    painted = _run(Tty(), "always", None)
    if "\033[90m" not in painted or "\033[K" not in painted:
        fail(repr(painted))
    print("progress ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
