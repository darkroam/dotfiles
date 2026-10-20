#!/bin/sh
# Offline regression. The controller is a directory double, so the suite never dials out.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
AXS=$ROOT/bin/axs
FIX=$ROOT/tests/fixtures/subscription.yaml
CANARY=http://canary.invalid/secret-path
PASS=0
PIDS=$(mktemp)

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
trap cleanup EXIT INT TERM

new_run() {
    RUN=$(mktemp -d)
    mkdir -p "$RUN/fake"
    export AXS_RUN="$RUN" AXS_FORBID_NET=1 AXS_FAKE_DIR="$RUN/fake"
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

mark_up() {
    "$ROOT/tests/fake-mihomo" &
    echo $! >"$RUN/mihomo.pid"
    echo $! >>"$PIDS"
    export AXS_MIHOMO="$ROOT/tests/fake-mihomo"
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

shellcheck "$ROOT/bin/axs" "$ROOT/lib/common.sh" "$ROOT/tests/run.sh" \
    "$ROOT/tests/fake-fetch" "$ROOT/tests/fake-fetch-fail" "$ROOT/tests/fake-fetch-html" \
    "$ROOT/tests/fake-mihomo" "$ROOT/tests/env/run.sh"
python3 -m py_compile "$ROOT/lib/merge.py" "$ROOT/tests/check_merge.py" "$ROOT/tests/prep_run.py" \
    "$ROOT/tests/env/lab.py"
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
export AXS_MIXED_PORT=18080
printf '%s\n' 'placeholder: true' >"$RUN/config.yaml"
open_mixed 18080
assert_code 'start busy' 2 start
grep -q '端口已被占用' "$RUN/err" || fail 'busy text'
if [ -f "$RUN/mihomo.pid" ]; then
    fail 'start launched while port was busy'
fi

new_run
export AXS_MIHOMO="$ROOT/tests/fake-mihomo" AXS_MIXED_PORT=18080
printf '%s\n' 'placeholder: true' >"$RUN/config.yaml"
assert_code 'start' 0 start
cat "$RUN/mihomo.pid" >>"$PIDS"
assert_code 'start again' 0 start
kill "$(cat "$RUN/mihomo.pid")" 2>/dev/null || true
assert_code 'stop' 0 stop
assert_code 'stop again' 0 stop

new_run
printf '%s\n' 'DOMAIN kept.example DIRECT' >"$RUN/rules.list"
assert_code 'via while down' 0 rule add via .example.com PROXY
grep -q '启动时生效' "$RUN/out" || fail 'down add did not say it waits for start'
grep -q 'DOMAIN-SUFFIX example.com PROXY' "$RUN/rules.list" || fail 'suffix not stored'
grep -q 'kept.example' "$RUN/rules.list" || fail 'old rule dropped'

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
printf '%s\n' 'DOMAIN kept.example DIRECT' >"$RUN/rules.list"
cp "$RUN/rules.list" "$RUN/rules.before"
assert_code 'via unknown group' 3 rule add via example.com OTHER
if ! cmp -s "$RUN/rules.before" "$RUN/rules.list"; then
    fail 'unknown group wrote rules.list'
fi
if [ -f "$RUN/fake/log" ] && grep -q 'PUT /configs' "$RUN/fake/log"; then
    fail 'unknown group reloaded'
fi
grep -q 'GET /proxies' "$RUN/fake/log" || fail 'group was not queried'

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
: >"$RUN/fake/down"
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
mode=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["mode"])' "$RUN/config.yaml")
test "$mode" = rule || fail "mode $mode"
assert_code 'sub get' 0 sub get
if grep -q '未知' "$RUN/out"; then
    fail 'userinfo missing'
fi
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
export AXS_API="127.0.0.1:18081" AXS_MIXED_PORT=18080
arm_api PROXY 500 0
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
grep -q 'PUT /configs' "$RUN/fake/log" || fail 'reload was not attempted'
no_secret_text 'reload rollback'

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 500 0
cp "$FIX" "$RUN/subscription.yaml"
printf '%s\n' 'SENTINEL-OLD' >"$RUN/config.yaml"
printf '%s\n' 'DOMAIN kept.example DIRECT' >"$RUN/rules.list"
python3 "$ROOT/tests/prep_run.py" "$ROOT" "$RUN" "7897" "$AXS_API"
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
if flock -n "$RUN/refresh.lock" -c true; then
    fail 'lock was not held'
fi
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'lock busy' 4 sub refresh
grep -q '锁' "$RUN/err" || fail 'lock text'

prepare_health() {
    mixed=$1
    export AXS_MIXED_PORT="$mixed" AXS_API="127.0.0.1:18081"
    open_mixed "$mixed"
    arm_api PROXY 204 0
    python3 "$ROOT/tests/prep_run.py" "$ROOT" "$RUN" "$mixed" "$AXS_API"
}

new_run
mark_up
prepare_health 18080
now=$(date +%s)
printf '%s\n' "expire=$((now - 10))" >"$RUN/userinfo"
assert_code 'health expired' 5 health
grep -q '已过期' "$RUN/out" || fail 'expired text'
assert_code 'status expired still 0' 0 status
grep -q '已过期' "$RUN/out" || fail 'status expired text'

new_run
mark_up
prepare_health 18082
now=$(date +%s)
printf '%s\n' "expire=$((now + 86400))" >"$RUN/userinfo"
assert_code 'health soon' 0 health
grep -q '警告' "$RUN/out" || fail 'warning text'

new_run
mark_up
prepare_health 18083
: >"$RUN/fake/down"
assert_code 'health api down' 3 health

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
python3 "$ROOT/tests/prep_run.py" "$ROOT" "$RUN" "7897" "$AXS_API"
assert_code 'node test' 0 node test PROXY
grep -q ' 0' "$RUN/out" || fail "delay output: $(cat "$RUN/out")"
grep -q 'auth=yes' "$RUN/fake/log" || fail 'api was not authenticated'
if grep -F 'test-secret-value' "$RUN/fake/log" "$RUN/out" "$RUN/err" >/dev/null 2>&1; then
    fail 'secret reached the log or output'
fi
assert_code 'groups' 0 node groups
test "$(cat "$RUN/out")" = "$(printf 'PROXY\tSelector\ta')" || fail "groups columns: $(cat "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081" AXS_DELAY_URL="http://127.0.0.1:9/204"
arm_api PROXY 204 7
assert_code 'delay url' 0 node test PROXY
grep -q ' 7' "$RUN/out" || fail "delay url output: $(cat "$RUN/out")"
grep -q '127.0.0.1' "$RUN/fake/log" || fail 'delay url was not sent'

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fake-fetch" FIXTURE_SUB="$FIX"
"$AXS" sub refresh >/dev/null
perms=$(stat -c '%a %n' "$RUN" "$RUN/subscription.url" "$RUN/secret" "$RUN/config.yaml" "$RUN/override.yaml" "$RUN/userinfo")
printf '%s\n' "$perms" | grep -q '^700 ' || fail "run perms: $perms"
printf '%s\n' "$perms" | grep -q '^600 ' || fail "file perms: $perms"
test "$(stat -c '%a' "$RUN/secret")" = 600 || fail 'secret mode'
test "$(stat -c '%a' "$RUN/config.yaml")" = 600 || fail 'config mode'


new_run
assert_code 'start no config' 3 start
grep -q '没有配置' "$RUN/err" || fail 'start no config text'
test ! -f "$RUN/mihomo.pid" || fail 'start no config launched'

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'start ignores url' 3 start
test ! -f "$RUN/config.yaml" || fail 'start refreshed without being asked'
test ! -f "$RUN/mihomo.pid" || fail 'start launched without config'

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"AUTO":{"all":["b","a b"],"now":"b","type":"URLTest"},"PROXY":{"all":["a","b","a b"],"now":"a","type":"Selector"},"RELAY":{"all":["a"],"type":"Relay"},"DIRECT":{"type":"Direct"},"a":{"type":"Shadowsocks"},"a b":{"type":"Shadowsocks"},"b":{"type":"Shadowsocks"},"lonely":{"type":"Socks"}}}
EOF
names=$(find "$RUN" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort)
assert_code 'node list' 0 node list
after=$(find "$RUN" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort)
test "$after" = "$names" || fail "list wrote run: $after"
list_want=$(printf '%s\n' \
    "$(printf '*\ta\tShadowsocks\tPROXY')" \
    "$(printf '\ta\tShadowsocks\tRELAY')" \
    "$(printf '\ta b\tShadowsocks\tAUTO')" \
    "$(printf '\ta b\tShadowsocks\tPROXY')" \
    "$(printf '*\tb\tShadowsocks\tAUTO')" \
    "$(printf '\tb\tShadowsocks\tPROXY')" \
    "$(printf '\tDIRECT\tDirect\t-')" \
    "$(printf '\tlonely\tSocks\t-')")
test "$(cat "$RUN/out")" = "$list_want" || fail "list columns: $(cat "$RUN/out")"
assert_code 'groups columns' 0 node groups
groups_want=$(printf '%s\n' \
    "$(printf 'AUTO\tURLTest\tb')" \
    "$(printf 'PROXY\tSelector\ta')" \
    "$(printf 'RELAY\tRelay\t-')")
test "$(cat "$RUN/out")" = "$groups_want" || fail "groups now: $(cat "$RUN/out")"

new_run
assert_code 'list down' 2 node list

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
: >"$RUN/fake/down"
assert_code 'list api down' 3 node list

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"A B":{"all":["a","a b"],"now":"a","type":"Selector"},"AUTO":{"all":["b"],"now":"b","type":"URLTest"},"PROXY":{"all":["a","a b"],"now":"a","type":"Selector"},"a":{"type":"Shadowsocks"},"a b":{"type":"Shadowsocks"},"b":{"type":"Shadowsocks"}}}
EOF
printf '%s\n' 'SENTINEL' >"$RUN/config.yaml"
printf '%s\n' 'RULE' >"$RUN/rules.list"
: >"$RUN/fake/log"
assert_code 'switch' 0 node switch PROXY 'a b'
test "$(cat "$RUN/out")" = "$(printf 'PROXY\ta b')" || fail "switch out: $(cat "$RUN/out")"
grep -q 'PUT /proxies/PROXY' "$RUN/fake/log" || fail 'select was not sent'
grep -q '{"name": "a b"}' "$RUN/fake/log" || fail "select body: $(cat "$RUN/fake/log")"
test "$(grep -c 'GET /proxies' "$RUN/fake/log")" -eq 1 || fail 'switch queried twice'
test "$(cat "$RUN/config.yaml")" = 'SENTINEL' || fail 'switch edited config'
test "$(cat "$RUN/rules.list")" = 'RULE' || fail 'switch edited rules'
test ! -f "$RUN/refresh.lock" || fail 'switch took the refresh lock'
: >"$RUN/fake/log"
assert_code 'switch urltest' 0 node switch AUTO b
grep -q 'PUT /proxies/AUTO' "$RUN/fake/log" || fail 'urltest select was not sent'
: >"$RUN/fake/log"
assert_code 'switch encode' 0 node switch 'A B' a
grep -q 'PUT /proxies/A%20B' "$RUN/fake/log" || fail "encoded path: $(cat "$RUN/fake/log")"
: >"$RUN/fake/log"
assert_code 'switch missing group' 3 node switch NOPE a
grep -q '组不存在' "$RUN/err" || fail "missing group text: $(cat "$RUN/err")"
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'missing group sent select'
fi
: >"$RUN/fake/log"
assert_code 'switch not group' 3 node switch a b
grep -q '不是策略组' "$RUN/err" || fail "not group text: $(cat "$RUN/err")"
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'non-group sent select'
fi
: >"$RUN/fake/log"
assert_code 'switch missing node' 3 node switch PROXY nope
grep -q '节点不存在' "$RUN/err" || fail "missing node text: $(cat "$RUN/err")"
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'missing node sent select'
fi
: >"$RUN/fake/log"
: >"$RUN/fake/down"
assert_code 'switch api down' 3 node switch PROXY a
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'api down sent select'
fi
rm -f "$RUN/fake/down"
printf '%s\n' '400' >"$RUN/fake/select"
: >"$RUN/fake/log"
assert_code 'switch reject' 3 node switch PROXY a
grep -q 'PUT /proxies/PROXY' "$RUN/fake/log" || fail 'reject did not send select'
test ! -s "$RUN/out" || fail 'reject printed a success line'

new_run
assert_code 'switch down' 2 node switch PROXY a
assert_code 'switch usage' 1 node switch onlyone

new_run
mark_up
export AXS_FETCH="$ROOT/tests/fake-fetch-fail" FIXTURE_SUB="$FIX"
printf '%s\n' 'placeholder: true' >"$RUN/config.yaml"
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
pid=$(cat "$RUN/mihomo.pid")
assert_code 'ensure already' 0 ensure
test "$(cat "$RUN/mihomo.pid")" = "$pid" || fail 'ensure restarted a running service'
test ! -s "$RUN/out" || fail 'ensure printed on success'

new_run
export AXS_MIXED_PORT=18080
open_mixed 18080
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'ensure busy' 2 ensure
grep -q '端口已被占用' "$RUN/err" || fail 'ensure busy text'
test ! -f "$RUN/config.yaml" || fail 'ensure refreshed while the port was busy'
test ! -f "$RUN/mihomo.pid" || fail 'ensure launched while the port was busy'

new_run
assert_code 'ensure no url' 3 ensure
grep -q '没有订阅' "$RUN/err" || fail 'ensure no url text'
test ! -f "$RUN/mihomo.pid" || fail 'ensure launched without a subscription'

new_run
export AXS_MIHOMO="$ROOT/tests/fake-mihomo" AXS_MIXED_PORT=18084
printf '%s\n' 'placeholder: true' >"$RUN/config.yaml"
export AXS_FETCH="$ROOT/tests/fake-fetch-fail" FIXTURE_SUB="$FIX"
assert_code 'ensure start only' 0 ensure
test -f "$RUN/mihomo.pid" || fail 'ensure did not start'
cat "$RUN/mihomo.pid" >>"$PIDS"
test ! -s "$RUN/out" || fail 'ensure start printed'

new_run
export AXS_MIHOMO="$ROOT/tests/fake-mihomo" AXS_MIXED_PORT=18085
export AXS_FETCH="$ROOT/tests/fake-fetch" FIXTURE_SUB="$FIX"
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
chmod 600 "$RUN/subscription.url"
assert_code 'ensure refresh start' 0 ensure
test -f "$RUN/config.yaml" || fail 'ensure did not refresh'
test -f "$RUN/mihomo.pid" || fail 'ensure did not start after refresh'
cat "$RUN/mihomo.pid" >>"$PIDS"
test ! -s "$RUN/out" || fail 'ensure refresh printed'

new_run
export AXS_FETCH="$ROOT/tests/fake-fetch-fail" FIXTURE_SUB="$FIX"
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
assert_code 'ensure fetch fail' 3 ensure
test ! -f "$RUN/mihomo.pid" || fail 'ensure started after a failed refresh'
test ! -f "$RUN/config.yaml" || fail 'failed ensure left a config'

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
if flock -n "$RUN/refresh.lock" -c true; then
    fail 'ensure lock was not held'
fi
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'ensure lock' 4 ensure
grep -q '锁' "$RUN/err" || fail 'ensure lock text'
test ! -f "$RUN/mihomo.pid" || fail 'ensure started while locked'
assert_code 'ensure usage' 1 ensure extra

new_run
assert_code 'net scheme' 1 net test 'ftp://127.0.0.1/' 'https://www.github.com'
test ! -s "$RUN/out" || fail 'bad scheme still tested'
assert_code 'net defaults forbid' 3 net test
test ! -s "$RUN/out" || fail 'forbid tested a default url'
assert_code 'net forbid partial' 3 net test 'http://127.0.0.1:9/' 'http://example.com/'
test ! -s "$RUN/out" || fail 'forbid tested the legal url'
assert_code 'net mixed down' 2 net test 'http://[::1]/'
grep -q '入站：不通' "$RUN/err" || fail 'net mixed text'
test ! -s "$RUN/out" || fail 'mixed down still tested'
printf '%s\n' '# skip' '' 'http://127.0.0.1:9/' >"$RUN/urls"
chmod 600 "$RUN/urls"
assert_code 'net urls file' 2 net test
printf '%s\n' '# only' >"$RUN/urls"
assert_code 'net urls empty' 3 net test
mark_up
export AXS_MIXED_PORT=18086
open_mixed 18086
assert_code 'net forbid no dial' 3 net test 'https://www.github.com'
test ! -s "$RUN/out" || fail 'forbid dialed'

echo "ok $PASS"
