#!/usr/bin/env python3
"""Shell literals stay inside config names. Snapshot names now live in core."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.config import (  # noqa: E402
    CONFIG_BAK,
    DEFAULT_API,
    DEFAULT_MIXED,
    LEGACY_SESSION_FLAG,
    LEGACY_SYSTEM_FLAG,
    LOOPBACK,
    LOOPBACK_HOSTS,
    RUN_FILES,
    SNAP,
)

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


def pin_defaults():
    if (ROOT / "lib" / "common.sh").exists() or (ROOT / "lib" / "merge.py").exists():
        fail("forwarding layer remains")
    if len(set(RUN_FILES)) != len(RUN_FILES):
        fail("duplicate run file name")
    for path in sorted((ROOT / "lib" / "axs").glob("*.py")):
        if path.name == "config.py":
            continue
        body = path.read_text(encoding="utf-8")
        if "7897" in body or DEFAULT_API in body:
            fail(path.name + " repeats a default")
    config = (ROOT / "lib" / "axs" / "config.py").read_text(encoding="utf-8")
    if str(DEFAULT_MIXED) not in config or LOOPBACK not in config or ":9097" not in config:
        fail("config lost the defaults")
    for path in sorted((ROOT / "lib" / "axs").glob("*.py")):
        if path.name == "config.py":
            continue
        body = path.read_text(encoding="utf-8")
        hit = [mark for mark in LOOPBACK_HOSTS if mark in body]
        if hit:
            fail(path.name + " has loopback literal")


def pin_routes(text):
    quoted = set(re.findall(r"""["'](/(?:proxies|version|configs|group|delay)[^"']*)["']""", text))
    if quoted != ROUTES:
        raise SystemExit(f"quoted routes {sorted(quoted)}")
    for path in sorted((ROOT / "lib" / "axs").glob("*.py")):
        if path.name == "mihomo.py":
            continue
        leaked = [route for route in ROUTES if route in path.read_text(encoding="utf-8")]
        if leaked:
            raise SystemExit(f"{path.name} owns {leaked}")


def main():
    pin_defaults()
    pin_routes(MIHOMO.read_text(encoding="utf-8"))
    print("pins")
    return 0


if __name__ == "__main__":
    sys.exit(main())
