# shellcheck shell=sh
if [ -z "${PASS+x}" ]; then
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
    # shellcheck disable=SC1091
    . "$TEST/support/harness.sh"
    harness_init
fi

new_run
python3 -c 'import os, pty, select, subprocess, time, sys
root, run = sys.argv[1], sys.argv[2]
env = os.environ.copy()
env.pop("AXS_COLOR", None)
env.pop("NO_COLOR", None)
env["AXS_RUN"] = run
env["AXS_SYSTEMD"] = "0"
env["AXS_FORBID_NET"] = "1"
env["AXS_FAKE_DIR"] = run + "/fake"
master, slave = pty.openpty()
proc = subprocess.Popen([root + "/bin/axs", "status"], stdin=slave, stdout=slave, stderr=slave, env=env, close_fds=True)
os.close(slave)
data = b""
deadline = time.time() + 5
while time.time() < deadline:
    ready, _, _ = select.select([master], [], [], 0.2)
    if ready:
        try:
            chunk = os.read(master, 4096)
        except OSError:
            break
        if not chunk:
            break
        data += chunk
    elif proc.poll() is not None:
        break
code = proc.wait(timeout=5)
os.close(master)
text = data.decode("utf-8", "replace")
open(run + "/pty", "w", encoding="utf-8").write(text)
if code != 2 or "\033[1;31m未运行" not in text:
    sys.stderr.write(text)
    raise SystemExit(1)
' "$ROOT" "$RUN" || fail "pty status color"
PASS=$((PASS + 1))
