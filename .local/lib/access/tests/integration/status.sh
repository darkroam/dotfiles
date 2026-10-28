# shellcheck shell=sh
if [ -z "${PASS+x}" ]; then
    ROOT=$(cd "$(dirname "$0")/../.." && pwd)
    # shellcheck disable=SC1091
    . "$ROOT/tests/support/harness.sh"
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
