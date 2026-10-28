# Shared by the offline suite. Sourced, not executed.
# shellcheck shell=sh

fail() {
    echo "FAIL: $1" >&2
    if [ -n "${2:-}" ]; then
        printf '%s\n' "$2" >&2
    fi
    exit 1
}


cleanup() {
    if [ -f "$PIDS" ]; then
        while read -r pid; do
            if [ -n "$pid" ]; then
                kill "$pid" 2>/dev/null || true
            fi
        done <"$PIDS"
    fi
}


new_run() {
    RUN=$(mktemp -d)
    mkdir -p "$RUN/fake"
    export AXS_RUN="$RUN" AXS_FORBID_NET=1 AXS_FAKE_DIR="$RUN/fake" AXS_SYSTEMD=0
    unset AXS_MIXED_PORT AXS_API AXS_FETCH AXS_MIHOMO AXS_SYSTEMCTL COLUMNS AXS_COLOR NO_COLOR AXS_SESSION_PID || true
    : >"$RUN/err"
    : >"$RUN/out"
}


code_of() {
    set +e
    "$AXS" "$@" >"$RUN/out" 2>"$RUN/err"
    CODE=$?
    set -e
}


assert_code() {
    name=$1
    want=$2
    shift 2
    code_of "$@"
    if [ "$CODE" -ne "$want" ]; then
        fail "$name want $want got $CODE" "$(cat "$RUN/err"; echo '---'; cat "$RUN/out")"
    fi
    PASS=$((PASS + 1))
}


no_secret_text() {
    name=$1
    if grep -F "$CANARY" "$RUN/out" "$RUN/err" >/dev/null 2>&1; then
        fail "$name printed the subscription url"
    fi
    if [ -f "$RUN/secret" ] && grep -F "$(cat "$RUN/secret")" "$RUN/out" "$RUN/err" >/dev/null 2>&1; then
        fail "$name printed the secret"
    fi
}


mark_up() {
    "$ROOT/tests/fixtures/fake-mihomo" &
    echo $! >"$RUN/mihomo.pid"
    echo $! >>"$PIDS"
    export AXS_MIHOMO="$ROOT/tests/fixtures/fake-mihomo"
}


arm_api() {
    printf '%s\n' "${1:-PROXY}" >"$RUN/fake/groups"
    printf '%s\n' "${2:-204}" >"$RUN/fake/reload"
    printf '%s\n' "${3:-0}" >"$RUN/fake/delay"
    if [ ! -f "$RUN/secret" ]; then
        printf '%s\n' 'test-secret-value' >"$RUN/secret"
        chmod 600 "$RUN/secret"
    fi
}


open_mixed() {
    printf '%s\n' "$1" >"$RUN/fake/open-ports"
}


proxy_status_env() {
    export http_proxy=http://127.0.0.1:7897
    "$AXS" status >"$RUN/out" 2>"$RUN/err" || true
}


prepare_health() {
    mixed=$1
    export AXS_MIXED_PORT="$mixed" AXS_API="127.0.0.1:18081"
    open_mixed "$mixed"
    arm_api PROXY 204 0
    python3 "$ROOT/tests/support/prep.py" "$ROOT" "$RUN" "$mixed" "$AXS_API"
}


seed_clean() {
    printf '%s\n' drop >"$RUN/config.yaml"
    printf '%s\n' bak >"$RUN/config.yaml.bak"
    printf '%s\n' info >"$RUN/userinfo"
    printf '%s\n' fetch >"$RUN/fetch.yaml"
    printf '%s\n' hdr >"$RUN/fetch.hdr"
    printf '%s\n' 999999 >"$RUN/mihomo.pid"
    printf '%s\n' url >"$RUN/subscription.url"
    printf '%s\n' 'axs-subscriptions 1' >"$RUN/subscriptions.list"
    printf '%s\n' secret >"$RUN/secret"
    printf '%s\n' rules >"$RUN/rules.list"
    printf '%s\n' over >"$RUN/override.yaml"
    printf '%s\n' body >"$RUN/subscription.yaml"
}


pty_answer() {
    answer=$1
    shift
    PTY_ANSWER=$answer PTY_CMD=$AXS python3 - "$@" << 'PY'
import os, pty, select, sys
reply = os.environ["PTY_ANSWER"] + "\n"
cmd = [os.environ["PTY_CMD"], *sys.argv[1:]]
pid, fd = pty.fork()
if pid == 0:
    os.execv(cmd[0], cmd)
sent = False
while True:
    ready, _, _ = select.select([fd], [], [], 3)
    if not ready:
        break
    try:
        chunk = os.read(fd, 1024)
    except OSError:
        break
    if not chunk:
        break
    if not sent and "确认删除" in chunk.decode("utf-8", "replace"):
        os.write(fd, reply.encode())
        sent = True
_, status = os.waitpid(pid, 0)
raise SystemExit(os.waitstatus_to_exitcode(status))
PY
}


proxy_status_on() {
    export http_proxy=http://127.0.0.1:7897
    "$AXS" proxy user status >"$RUN/out" 2>"$RUN/err"
}
proxy_status_off() {
    unset http_proxy
    "$AXS" proxy user status >"$RUN/out" 2>"$RUN/err"
}
proxy_eval() {
    eval "$("$AXS" proxy user on)"
    [ "$http_proxy" = 'http://127.0.0.1:7897' ]
}


harness_init() {
    AXS=$ROOT/bin/axs
    # shellcheck disable=SC2034
    FIX=$ROOT/tests/fixtures/subscription.yaml
    CANARY=http://canary.invalid/secret-path
    PASS=0
    PIDS=$(mktemp)
    # shellcheck disable=SC2034
    ESC=$(printf '\033')
    trap cleanup EXIT INT TERM
}
