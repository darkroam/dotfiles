#!/usr/bin/env python3
"""Shell literals must stay equal to config while both copies exist."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.config import (  # noqa: E402
    DEFAULT_API,
    DEFAULT_MIXED,
    RUN_FILES,
    SNAP_NAMES,
)

SHELL = ROOT / "lib" / "common.sh"
MERGE = ROOT / "lib" / "merge.py"
MIHOMO = ROOT / "lib" / "axs" / "mihomo.py"
ROUTES = {
    "/configs?force=true",
    "/delay",
    "/group/",
    "/proxies",
    "/version",
}


def fail(message):
    raise SystemExit(message)


def pin_ports(text):
    mixed = re.findall(r"AXS_MIXED_PORT:-(\d+)", text)
    mixed += re.findall(r"(?m)^\s*MIXED=(\d+)\s*$", text)
    api = re.findall(r"AXS_API:-([0-9.]+(?::[0-9]+)?)", text)
    api += re.findall(r"(?m)^\s*API=([0-9.]+(?::[0-9]+)?)\s*$", text)
    if mixed != [str(DEFAULT_MIXED), str(DEFAULT_MIXED)]:
        fail(f"mixed literals {mixed}")
    if api != [DEFAULT_API, DEFAULT_API]:
        fail(f"api literals {api}")


def pin_paths(text):
    found = set(re.findall(r"\$AXS_RUN/([A-Za-z0-9._-]+)", text))
    allowed = set(RUN_FILES)
    if len(allowed) != len(RUN_FILES):
        fail("duplicate run file name")
    extra = found - allowed
    missing = allowed - found
    if extra or missing:
        fail(f"paths extra={sorted(extra)} missing={sorted(missing)}")
    loops = re.findall(r"for name in ([A-Za-z0-9. ]+);", text)
    if tuple(loops) != (" ".join(SNAP_NAMES),) * 2:
        fail(f"snap names {loops}")


def pin_routes(text):
    quoted = set(re.findall(r"""["'](/(?:proxies|version|configs|group|delay)[^"']*)["']""", text))
    if quoted != ROUTES:
        raise SystemExit(f"quoted routes {sorted(quoted)}")
    merge = MERGE.read_text(encoding="utf-8")
    leaked = [route for route in ROUTES if route in merge]
    if leaked:
        raise SystemExit(f"merge still owns {leaked}")


def main():
    shell = SHELL.read_text(encoding="utf-8")
    pin_ports(shell)
    pin_paths(shell)
    pin_routes(MIHOMO.read_text(encoding="utf-8"))
    print("pins")
    return 0


if __name__ == "__main__":
    sys.exit(main())
