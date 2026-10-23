#!/bin/sh
# Offline entry. Assertions live in tests/integration.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
shellcheck -x bin/axs bin/mihomo-run tests/run.sh tests/support/harness.sh tests/lab/run.sh tests/integration/*.sh tests/fixtures/fake-*
python3 -m py_compile lib/axs/*.py tests/support/*.py tests/lab/lab.py tests/unit/test_*.py
PY=0
for unit in tests/unit/test_*.py; do
    python3 "$unit"
    PY=$((PY + 1))
done
python3 tests/support/snap.py check
PY=$((PY + 1))
# shellcheck disable=SC1091
. tests/support/harness.sh
harness_init
for name in service node clean proxy status; do
    # shellcheck disable=SC1090
    . "tests/integration/${name}.sh"
done
echo "ok $((PASS + PY))"
