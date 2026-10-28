#!/bin/sh
# Offline entry. Assertions live under this test root.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
TEST=$here
while [ ! -f "$TEST/support/harness.sh" ]; do
    case $TEST in /) echo "no test root" >&2; exit 1 ;; esac
    TEST=$(dirname "$TEST")
done
repo=$TEST
while [ ! -x "$repo/.local/lib/access/bin/axs" ]; do
    case $repo in /) echo "no access root" >&2; exit 1 ;; esac
    repo=$(dirname "$repo")
done
ROOT=$repo/.local/lib/access
shellcheck -x "$ROOT/bin/axs" "$ROOT/bin/mihomo-run" "$TEST/run.sh" "$TEST/support/harness.sh" "$TEST/lab/run.sh" "$TEST/integration/"*.sh "$TEST/fixtures/fake-"*
python3 -m py_compile "$ROOT/axs/"*.py "$TEST/support/"*.py "$TEST/lab/lab.py" "$TEST/lab/audit.py" "$TEST/unit/test_"*.py
PY=0
for unit in "$TEST/unit/"test_*.py; do
    python3 "$unit"
    PY=$((PY + 1))
done
python3 "$TEST/support/snap.py" check
PY=$((PY + 1))
# shellcheck disable=SC1091
. "$TEST/support/harness.sh"
harness_init
for name in service node clean proxy status; do
    # shellcheck disable=SC1090
    . "$TEST/integration/${name}.sh"
done
echo "ok $((PASS + PY))"
