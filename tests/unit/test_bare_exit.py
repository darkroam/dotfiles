#!/usr/bin/env python3
# count: grep -cE 'die [0-9]+' over bin/axs and bin/mihomo-run; grep -cE 'SystemExit\([0-9]+' over lib/axs/*.py. The regexes below count occurrences. Ceiling only shrinks.
"""Bare numeric exits may only shrink. Baseline is the step 0 tree."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHELL_LIMIT = 67
PYTHON_LIMIT = 19
SHELL = re.compile(r"\bdie [0-9]+\b")
PYTHON = re.compile(r"SystemExit\([0-9]+")


def count(pattern, paths):
    found = 0
    for path in paths:
        found += len(pattern.findall(path.read_text(encoding="utf-8")))
    return found


def main():
    shell = count(SHELL, [ROOT / "bin/axs", ROOT / "bin/mihomo-run"])
    python_files = sorted((ROOT / "lib" / "axs").glob("*.py"))
    python = count(PYTHON, python_files)
    if shell > SHELL_LIMIT or python > PYTHON_LIMIT:
        print(f"bare exits grew: shell {shell}>{SHELL_LIMIT} python {python}>{PYTHON_LIMIT}", file=sys.stderr)
        return 1
    print(f"bare exits shell {shell} python {python}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
