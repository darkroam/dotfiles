#!/bin/sh
# Offline regression. No subscription URL is requested.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
AXS=$ROOT/bin/axs
FIX=$ROOT/tests/fixtures/subscription.yaml
CANARY=http://canary.invalid/secret-path
PASS=0

fail() {
    echo "FAIL: $1" >&2
    if [ -n "${2:-}" ]; then
        printf '%s\n' "$2" >&2
    fi
    exit 1
}

free_port() {
    python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'
}

new_run() {
    RUN=$(mktemp -d)
    export AXS_RUN="$RUN" AXS_FORBID_NET=1
    unset AXS_MIXED_PORT AXS_API AXS_FETCH AXS_MIHOMO || true
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

wait_port() {
    port=$1
    i=0
    while [ "$i" -lt 50 ]; do
        if python3 -c 'import socket,sys
s=socket.socket(); s.settimeout(0.2)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()' "$port"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.05
    done
    fail "port $port did not open"
}

start_api() {
    port=$1
    FAKE_LOG=$RUN/api.log FAKE_GROUPS=${2:-PROXY} FAKE_RELOAD=${3:-204} FAKE_DELAY=${4:-0} \
        python3 "$ROOT/tests/fake_api.py" "$port" &
    echo $! >>"$PIDS"
    wait_port "$port"
}

hold_port() {
    python3 "$ROOT/tests/hold_port.py" "$1" 30 &
    echo $! >>"$PIDS"
    wait_port "$1"
}

mark_up() {
    "$ROOT/tests/fake-mihomo" &
    echo $! >"$RUN/mihomo.pid"
    echo $! >>"$PIDS"
    export AXS_MIHOMO="$ROOT/tests/fake-mihomo"
}

PIDS=$(mktemp)
cleanup() {
    if [ -f "$PIDS" ]; then
        while read -r pid; do
            if [ -n "$pid" ]; then
                kill "$pid" 2>/dev/null || true
            fi
        done <"$PIDS"
    fi
}
trap cleanup EXIT INT TERM

shellcheck "$ROOT/bin/axs" "$ROOT/lib/common.sh" "$ROOT/tests/run.sh" \
    "$ROOT/tests/fake-fetch" "$ROOT/tests/fake-fetch-fail" "$ROOT/tests/fake-fetch-html" \
    "$ROOT/tests/fake-mihomo"
python3 -m py_compile "$ROOT/lib/merge.py" "$ROOT/tests/check_merge.py" "$ROOT/tests/fake_api.py" "$ROOT/tests/prep_run.py"
PASS=$((PASS + 1))

new_run
python3 "$ROOT/tests/check_merge.py" "$RUN"
PASS=$((PASS + 1))

new_run
assert_code usage 1
grep -q '用法' "$RUN/err" || fail 'usage text'
assert_code 'rule usage' 1 rule add via

new_run
assert_code 'health down' 2 health

new_run
mixed=$(free_port)
export AXS_MIXED_PORT="$mixed"
printf '%s\n' 'placeholder: true' >"$RUN/config.yaml"
hold_port "$mixed"
assert_code 'start busy' 2 start
grep -q '端口已被占用' "$RUN/err" || fail 'busy text'
if [ -f "$RUN/mihomo.pid" ]; then
    fail 'start launched while port was busy'
fi

new_run
export AXS_MIHOMO="$ROOT/tests/fake-mihomo"
mixed=$(free_port)
export AXS_MIXED_PORT="$mixed"
printf '%s\n' 'placeholder: true' >"$RUN/config.yaml"
assert_code 'start' 0 start
cat "$RUN/mihomo.pid" >>"$PIDS"
assert_code 'start again' 0 start
kill "$(cat "$RUN/mihomo.pid")" 2>/dev/null || true
assert_code 'stop' 0 stop
assert_code 'stop again' 0 stop

new_run
mark_up
printf '%s\n' 'DOMAIN kept.example DIRECT' >"$RUN/rules.list"
assert_code 'via while down' 0 rule add via .example.com PROXY
grep -q '启动时生效' "$RUN/out" || fail 'down add did not say it waits for start'
grep -q 'DOMAIN-SUFFIX example.com PROXY' "$RUN/rules.list" || fail 'suffix not stored'
grep -q 'kept.example' "$RUN/rules.list" || fail 'old rule dropped'

new_run
mark_up
api=$(free_port)
export AXS_API="127.0.0.1:$api"
start_api "$api" PROXY 204 0
printf '%s\n' 'DOMAIN kept.example DIRECT' >"$RUN/rules.list"
cp "$RUN/rules.list" "$RUN/rules.before"
assert_code 'via unknown group' 3 rule add via example.com OTHER
if ! cmp -s "$RUN/rules.before" "$RUN/rules.list"; then
    fail 'unknown group wrote rules.list'
fi
grep -q 'PUT /configs' "$RUN/api.log" && fail 'unknown group reloaded'
grep -q 'GET /proxies' "$RUN/api.log" || fail 'group was not queried'

new_run
mark_up
api=$(free_port)
export AXS_API="127.0.0.1:$api"
printf '%s\n' 'DOMAIN kept.example DIRECT' >"$RUN/rules.list"
cp "$RUN/rules.list" "$RUN/rules.before"
assert_code 'via api down' 3 rule add via example.com PROXY
if ! cmp -s "$RUN/rules.before" "$RUN/rules.list"; then
    fail 'api failure wrote rules.list'
fi

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
chmod 600 "$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'refresh down' 0 sub refresh
no_secret_text 'refresh down'
if grep -F "$CANARY" "$RUN/config.yaml" >/dev/null 2>&1; then
    fail 'canary stored in config'
fi
test -f "$RUN/config.yaml.bak" && fail 'bak created when there was no previous config'
mode=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["mode"])' "$RUN/config.yaml")
test "$mode" = rule || fail "mode $mode"
assert_code 'sub get' 0 sub get
grep -q '未知' "$RUN/out" && fail 'userinfo missing'
grep -q '剩余' "$RUN/out" || fail 'remaining life not shown'
no_secret_text 'sub get'

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
printf '%s\n' 'SENTINEL-OLD' >"$RUN/config.yaml"
printf '%s\n' 'SENTINEL-SUB' >"$RUN/subscription.yaml"
export AXS_FETCH="$ROOT/tests/fake-fetch-html" FIXTURE_SUB="$FIX"
assert_code 'refresh reject' 3 sub refresh
test "$(cat "$RUN/config.yaml")" = "SENTINEL-OLD" || fail 'bad fetch replaced config'
test "$(cat "$RUN/subscription.yaml")" = "SENTINEL-SUB" || fail 'bad fetch replaced body'
no_secret_text 'refresh reject'

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fake-fetch-fail"
assert_code 'refresh transport' 3 sub refresh
test ! -f "$RUN/config.yaml" || fail 'transport failure left a config'

new_run
mark_up
api=$(free_port)
mixed=$(free_port)
export AXS_API="127.0.0.1:$api" AXS_MIXED_PORT="$mixed"
start_api "$api" PROXY 500 0
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
printf '%s\n' 'SENTINEL-OLD' >"$RUN/config.yaml"
printf '%s\n' 'SENTINEL-SUB' >"$RUN/subscription.yaml"
printf '%s\n' 'DOMAIN kept.example DIRECT' >"$RUN/rules.list"
export AXS_FETCH="$ROOT/tests/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'reload rollback' 3 sub refresh
test "$(cat "$RUN/config.yaml")" = "SENTINEL-OLD" || fail 'reload failure kept new config'
test "$(cat "$RUN/subscription.yaml")" = "SENTINEL-SUB" || fail 'reload failure kept new body'
test "$(cat "$RUN/rules.list")" = "DOMAIN kept.example DIRECT" || fail 'reload failure changed rules'
test "$(cat "$RUN/config.yaml.bak")" = "SENTINEL-OLD" || fail 'bak is not the last good config'
grep -q 'PUT /configs' "$RUN/api.log" || fail 'reload was not attempted'
no_secret_text 'reload rollback'

new_run
mark_up
api=$(free_port)
export AXS_API="127.0.0.1:$api"
start_api "$api" PROXY 500 0
cp "$FIX" "$RUN/subscription.yaml"
printf '%s\n' 'SENTINEL-OLD' >"$RUN/config.yaml"
printf '%s\n' 'DOMAIN kept.example DIRECT' >"$RUN/rules.list"
python3 "$ROOT/tests/prep_run.py" "$ROOT" "$RUN" "${AXS_MIXED_PORT:-7897}" "$AXS_API"
assert_code 'rule reload rollback' 3 rule add direct new.example
test "$(cat "$RUN/rules.list")" = "DOMAIN kept.example DIRECT" || fail 'rule add kept a failed edit'
test "$(cat "$RUN/config.yaml")" = "SENTINEL-OLD" || fail 'rule add kept a failed config'

new_run
flock "$RUN/refresh.lock" -c 'sleep 15' &
echo $! >>"$PIDS"
i=0
while [ "$i" -lt 30 ]; do
    if ! flock -n "$RUN/refresh.lock" -c true; then
        break
    fi
    i=$((i + 1))
    sleep 0.05
done
flock -n "$RUN/refresh.lock" -c true && fail 'lock was not held'
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'lock busy' 4 sub refresh
grep -q '锁' "$RUN/err" || fail 'lock text'

new_run
mark_up
mixed=$(free_port)
api=$(free_port)
export AXS_MIXED_PORT="$mixed" AXS_API="127.0.0.1:$api"
hold_port "$mixed"
start_api "$api" PROXY 204 0
python3 "$ROOT/tests/prep_run.py" "$ROOT" "$RUN" "$AXS_MIXED_PORT" "$AXS_API"
now=$(date +%s)
printf '%s\n' "expire=$((now - 10))" >"$RUN/userinfo"
assert_code 'health expired' 5 health
grep -q '已过期' "$RUN/out" || fail 'expired text'
assert_code 'status expired still 0' 0 status
grep -q '已过期' "$RUN/out" || fail 'status expired text'

new_run
mark_up
mixed=$(free_port)
api=$(free_port)
export AXS_MIXED_PORT="$mixed" AXS_API="127.0.0.1:$api"
hold_port "$mixed"
start_api "$api" PROXY 204 0
python3 -c 'from pathlib import Path; import os,sys
sys.path.insert(0, sys.argv[1]+"/lib"); import merge
merge.write_defaults(Path(sys.argv[2])/"override.yaml", os.environ["AXS_MIXED_PORT"], os.environ["AXS_API"])
Path(sys.argv[2],"secret").write_text("test-secret-value\n")
' "$ROOT" "$RUN"
now=$(date +%s)
printf '%s\n' "expire=$((now + 86400))" >"$RUN/userinfo"
assert_code 'health soon' 0 health
grep -q '警告' "$RUN/out" || fail 'warning text'

new_run
mark_up
mixed=$(free_port)
export AXS_MIXED_PORT="$mixed"
hold_port "$mixed"
python3 "$ROOT/tests/prep_run.py" "$ROOT" "$RUN" "$AXS_MIXED_PORT" "127.0.0.1:1"
assert_code 'health api down' 3 health

new_run
mark_up
api=$(free_port)
export AXS_API="127.0.0.1:$api"
start_api "$api" PROXY 204 0
python3 "$ROOT/tests/prep_run.py" "$ROOT" "$RUN" "7897" "$AXS_API"
assert_code 'node test' 0 node test PROXY
grep -q ' 0' "$RUN/out" || fail "delay output: $(cat "$RUN/out")"
grep -q 'auth=yes' "$RUN/api.log" || fail 'api was not authenticated'
if grep -F 'test-secret-value' "$RUN/api.log" "$RUN/out" "$RUN/err" >/dev/null 2>&1; then
    fail 'secret reached the log or output'
fi
assert_code 'groups' 0 node groups
grep -q 'PROXY' "$RUN/out" || fail 'group name missing'

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fake-fetch" FIXTURE_SUB="$FIX"
"$AXS" sub refresh >/dev/null
perms=$(stat -c '%a %n' "$RUN" "$RUN/subscription.url" "$RUN/secret" "$RUN/config.yaml" "$RUN/override.yaml" "$RUN/userinfo")
printf '%s\n' "$perms" | grep -q '^700 ' || fail "run perms: $perms"
printf '%s\n' "$perms" | grep -q '^600 ' || fail "file perms: $perms"
test "$(stat -c '%a' "$RUN/secret")" = 600 || fail 'secret mode'
test "$(stat -c '%a' "$RUN/config.yaml")" = 600 || fail 'config mode'

echo "ok $PASS"
