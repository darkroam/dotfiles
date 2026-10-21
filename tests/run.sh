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
    export AXS_RUN="$RUN" AXS_FORBID_NET=1 AXS_FAKE_DIR="$RUN/fake" AXS_SYSTEMD=0
    unset AXS_MIXED_PORT AXS_API AXS_FETCH AXS_MIHOMO AXS_SYSTEMCTL COLUMNS AXS_COLOR NO_COLOR || true
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

shellcheck "$ROOT/bin/axs" "$ROOT/bin/mihomo-run" "$ROOT/lib/common.sh" "$ROOT/tests/run.sh" \
    "$ROOT/tests/fake-systemctl" \
    "$ROOT/tests/fake-fetch" "$ROOT/tests/fake-fetch-fail" "$ROOT/tests/fake-fetch-html" \
    "$ROOT/tests/fake-fetch-empty" \
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
if grep -q 'health' "$RUN/err"; then
    fail 'usage still lists health'
fi
assert_code 'rule usage' 1 rule add via

new_run
set +e
"$AXS" >"$RUN/out" 2>"$RUN/err"
bare=$?
set -e
test "$bare" -eq 1 || fail "bare want 1 got $bare"
grep -q '用法' "$RUN/err" || fail "bare usage: $(cat "$RUN/err")"
if grep -q 'shift' "$RUN/err"; then
    fail "bare shift: $(cat "$RUN/err")"
fi
PASS=$((PASS + 1))

new_run
assert_code 'status down' 2 status
grep -q '服务：未运行（来源 手动）' "$RUN/out" || fail "down service: $(cat "$RUN/out")"
grep -q '节点：主代理 → - · GLOBAL = -' "$RUN/out" || fail "down nodes: $(cat "$RUN/out")"
grep -q '最近 net test：-' "$RUN/out" || fail "down net cache: $(cat "$RUN/out")"
grep -q '最近 node test：-' "$RUN/out" || fail "down node cache: $(cat "$RUN/out")"
grep -q '定时刷新：-' "$RUN/out" || fail "down timer: $(cat "$RUN/out")"
if grep -q "$(printf '\033')" "$RUN/out"; then
    fail 'status down colored off a tty'
fi

new_run
now=$(date +%s)
mkdir -p "$RUN/cache"
printf 'ts=%s\nresult=ok\n' "$((now - 180))" >"$RUN/cache/net-test"
printf 'ts=%s\nresult=ok\n' "$((now - 3600))" >"$RUN/cache/node-test"
assert_code 'status cache age' 2 status
grep -q '最近 net test：3 分钟前 全部通' "$RUN/out" || fail "cache net: $(cat "$RUN/out")"
grep -q '最近 node test：1 小时前' "$RUN/out" || fail "cache node: $(cat "$RUN/out")"

new_run
export AXS_SYSTEMD=1 AXS_SYSTEMCTL="$ROOT/tests/fake-systemctl"
assert_code 'systemd start' 0 start
grep -q 'start axs.service' "$RUN/systemctl.log" || fail "start log: $(cat "$RUN/systemctl.log" 2>/dev/null)"
assert_code 'systemd stop' 0 stop
grep -q 'stop axs.service' "$RUN/systemctl.log" || fail "stop log: $(cat "$RUN/systemctl.log")"
assert_code 'systemd restart' 0 restart
grep -q 'restart axs.service' "$RUN/systemctl.log" || fail "restart log: $(cat "$RUN/systemctl.log")"
: >"$RUN/systemctl.log"
printf '%s\n' active >"$RUN/systemctl.active"
assert_code 'systemd ensure active' 0 ensure
if grep -q 'start axs.service' "$RUN/systemctl.log"; then
    fail "active ensure started: $(cat "$RUN/systemctl.log")"
fi
export AXS_MIXED_PORT=7897 AXS_API=127.0.0.1:9097
assert_code 'systemd status' 2 status
grep -q '服务：运行中（systemd: axs.service，MainPID 4242，运行时长 -）' "$RUN/out" || fail "systemd status: $(cat "$RUN/out")"
grep -q '定时刷新：下次 Tue 2026-10-21 02:00:00 CST' "$RUN/out" || fail "timer: $(cat "$RUN/out")"

new_run
assert_code 'status down' 2 status

new_run
printf '%s\n' '$' >"$RUN/mihomo.pid"
assert_code 'status bad pid' 2 status
grep -q '服务：未运行' "$RUN/out" || fail "bad pid out: $(cat "$RUN/out")"
grep -q '告警：mihomo.pid 不是数字' "$RUN/err" || fail "bad pid err: $(cat "$RUN/err")"

new_run
: >"$RUN/mihomo.pid"
assert_code 'status empty pid' 2 status
grep -q '告警：mihomo.pid 不是数字' "$RUN/err" || fail "empty pid err: $(cat "$RUN/err")"

new_run
export AXS_MIHOMO="$ROOT/tests/fake-mihomo"
"$ROOT/bin/mihomo-run" &
child=$!
echo "$child" >>"$PIDS"
i=0
while [ "$i" -lt 20 ] && [ ! -s "$RUN/mihomo.pid" ]; do
    i=$((i + 1))
    sleep 0.05
done
test -s "$RUN/mihomo.pid" || fail 'mihomo-run wrote no pid'
pid=$(cat "$RUN/mihomo.pid")
test "$pid" = "$child" || fail "mihomo-run pid $pid want $child"
case $pid in
    ''|*[!0-9]*) fail "mihomo-run pid not numeric: $pid" ;;
esac
tr '\0' '\n' <"/proc/$pid/cmdline" | grep -Fxq -- "$AXS_MIHOMO" || fail 'mihomo-run did not exec mihomo'
kill "$pid" 2>/dev/null || true
PASS=$((PASS + 1))

if grep -F '$$' "$ROOT/units/axs.service" >/dev/null; then
    fail 'unit still has $$'
fi
grep -q 'ExecStart=%h/.local/lib/access/bin/mihomo-run' "$ROOT/units/axs.service" || fail 'unit ExecStart'
grep -q 'ExecStartPre=/bin/mkdir -p %h/.local/lib/access/run' "$ROOT/units/axs.service" || fail 'unit mkdir'
PASS=$((PASS + 1))

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
printf '%s\n' 'https://example.invalid/link/\?clash\=1' >"$RUN/subscription.url"
assert_code 'refresh backslash' 3 sub refresh
grep -q -F '链接含转义字符（如 \?），请去掉反斜杠' "$RUN/err" || fail "backslash text: $(cat "$RUN/err")"
test ! -f "$RUN/config.yaml" || fail 'backslash left a config'

new_run
printf '%s\n' 'https://example.invalid/has space' >"$RUN/subscription.url"
assert_code 'refresh space' 3 sub refresh
grep -q -F '链接含转义字符（如 \?），请去掉反斜杠' "$RUN/err" || fail "space text: $(cat "$RUN/err")"
test ! -f "$RUN/config.yaml" || fail 'space left a config'

new_run
printf '%s\n' 'https://example.invalid/sub' >"$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fake-fetch-empty"
assert_code 'refresh empty' 3 sub refresh
grep -q -F '订阅返回空内容/非 YAML（HTTP 200, text/html），请检查链接' "$RUN/err" || fail "empty text: $(cat "$RUN/err")"
test ! -f "$RUN/config.yaml" || fail 'empty left a config'

new_run
printf '%s\n' 'https://example.invalid/sub' >"$RUN/subscription.url"
printf '%s\n' 'SENTINEL-OLD' >"$RUN/config.yaml"
printf '%s\n' 'OLD-BAK' >"$RUN/config.yaml.bak"
export AXS_FETCH="$ROOT/tests/fake-fetch-html"
assert_code 'refresh html' 3 sub refresh
grep -q -F '订阅返回空内容/非 YAML（HTTP 200, text/html），请检查链接' "$RUN/err" || fail "html text: $(cat "$RUN/err")"
test "$(cat "$RUN/config.yaml")" = "SENTINEL-OLD" || fail 'html replaced config'
test "$(cat "$RUN/config.yaml.bak")" = "OLD-BAK" || fail 'precheck rewrote bak'

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
assert_code 'status expired' 5 status
grep -q '服务：运行中（手动，MainPID' "$RUN/out" || fail "expired service: $(cat "$RUN/out")"
grep -q '端口：18080 监听' "$RUN/out" || fail "expired port: $(cat "$RUN/out")"
grep -q '控制器：18081 可达' "$RUN/out" || fail "expired api: $(cat "$RUN/out")"
grep -q '节点：主代理 → - · GLOBAL = -' "$RUN/out" || fail "expired nodes: $(cat "$RUN/out")"
grep -q '订阅：已过期，剩余 0 天' "$RUN/out" || fail "expired sub: $(cat "$RUN/out")"

new_run
mark_up
prepare_health 18082
now=$(date +%s)
printf '%s\n' "expire=$((now + 86400))" >"$RUN/userinfo"
assert_code 'status soon' 0 status
grep -q '警告' "$RUN/out" || fail 'warning text'

new_run
mark_up
prepare_health 18083
: >"$RUN/fake/down"
assert_code 'status api down' 3 status

new_run
assert_code 'health down' 2 health
test ! -s "$RUN/out" || fail "health down stdout: $(cat "$RUN/out")"
grep -qx '未运行' "$RUN/err" || fail "health down: $(cat "$RUN/err")"

new_run
mark_up
export AXS_MIXED_PORT=18080
assert_code 'health port' 2 health
test ! -s "$RUN/out" || fail "health port stdout: $(cat "$RUN/out")"
grep -qx '端口不通' "$RUN/err" || fail "health port: $(cat "$RUN/err")"

new_run
mark_up
prepare_health 18083
: >"$RUN/fake/down"
assert_code 'health api' 3 health
test ! -s "$RUN/out" || fail "health api stdout: $(cat "$RUN/out")"
grep -qx '控制器不通' "$RUN/err" || fail "health api: $(cat "$RUN/err")"

new_run
mark_up
prepare_health 18080
now=$(date +%s)
printf '%s\n' "expire=$((now - 10))" >"$RUN/userinfo"
assert_code 'health expired' 5 health
test ! -s "$RUN/out" || fail "health expired stdout: $(cat "$RUN/out")"
grep -qx '订阅过期' "$RUN/err" || fail "health expired: $(cat "$RUN/err")"

new_run
mark_up
prepare_health 18082
now=$(date +%s)
printf '%s\n' "expire=$((now + 40 * 86400))" >"$RUN/userinfo"
assert_code 'health ok' 0 health
test ! -s "$RUN/out" || fail "health ok stdout: $(cat "$RUN/out")"
test ! -s "$RUN/err" || fail "health ok stderr: $(cat "$RUN/err")"
test ! -e "$RUN/cache" || fail 'health wrote a cache'

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
python3 "$ROOT/tests/prep_run.py" "$ROOT" "$RUN" "7897" "$AXS_API"
assert_code 'node test' 0 node test PROXY
grep -q ' 0' "$RUN/out" || fail "delay output: $(cat "$RUN/out")"
test "$(stat -c '%a' "$RUN/cache")" = 700 || fail 'cache dir mode'
test -f "$RUN/cache/node-test" || fail 'node test wrote no cache'
grep -q '^result=ok$' "$RUN/cache/node-test" || fail 'node cache result'
if grep -q 'PROXY' "$RUN/cache/node-test"; then
    fail 'node cache stored the group'
fi
test "$(stat -c '%a' "$RUN/cache/node-test")" = 600 || fail 'node cache mode'
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
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
printf '%s\n' '{"a": 12, "b": 5, "PROXY": 9}' >"$RUN/fake/delay.json"
assert_code 'node cache delays' 0 node test PROXY
python3 -c 'import json,os; p=os.environ["AXS_RUN"]+"/cache/node-test"; text=open(p,encoding="utf-8").read();
assert "PROXY" not in text, text
line=[row for row in text.splitlines() if row.startswith("{")][0]
data=json.loads(line)
assert data=={"a":12,"b":5}, data'
grep -q '^ts=' "$RUN/cache/node-test" || fail 'delay cache ts'
grep -q '^result=ok$' "$RUN/cache/node-test" || fail 'delay cache result'

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
assert_code 'node list' 0 node list --full
after=$(find "$RUN" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort)
test "$after" = "$names" || fail "list wrote run: $after"
list_want=$(printf '%s\n' \
    "$(printf '\tDIRECT\tDirect\t-')" \
    "$(printf '*\ta\tShadowsocks\tPROXY')" \
    "$(printf '\ta\tShadowsocks\tRELAY')" \
    "$(printf '\ta b\tShadowsocks\tAUTO')" \
    "$(printf '\ta b\tShadowsocks\tPROXY')" \
    "$(printf '*\tb\tShadowsocks\tAUTO')" \
    "$(printf '\tb\tShadowsocks\tPROXY')" \
    "$(printf '\tlonely\tSocks\t-')")
test "$(cat "$RUN/out")" = "$list_want" || fail "list columns: $(cat "$RUN/out")"
assert_code 'groups columns' 0 node groups
groups_want=$(printf '%s\n' \
    "$(printf 'AUTO\tURLTest\tb')" \
    "$(printf 'PROXY\tSelector\ta')" \
    "$(printf 'RELAY\tRelay\t-')")
test "$(cat "$RUN/out")" = "$groups_want" || fail "groups now: $(cat "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=40
arm_api PROXY 204 0
python3 -c 'import json; json.dump({"proxies": {f"node-{i:02d}": {"type": "Shadowsocks"} for i in range(1, 9)}}, open("'"$RUN"'/fake/proxies.json", "w"))'
assert_code 'list columns 40' 0 node list
test "$(sed -n '1p' "$RUN/out")" = '当前：无' || fail "no selection: $(sed -n '1p' "$RUN/out")"
test "$(sed -n '2p' "$RUN/out")" = '最近测速：-' || fail "no speed: $(sed -n '2p' "$RUN/out")"
want40='    1 node-01 -      2 node-02 -'
test "$(sed -n '3p' "$RUN/out")" = "$want40" || fail "cols 40: $(sed -n '3p' "$RUN/out")"
if grep -F '[*]' "$RUN/out" >/dev/null; then
    fail 'unselected list showed [*]'
fi
test ! -e "$RUN/cache" || fail 'compact list created cache'
COLUMNS=80
assert_code 'list columns 80' 0 node list
want80='    1 node-01 -      2 node-02 -      3 node-03 -      4 node-04 -'
test "$(sed -n '3p' "$RUN/out")" = "$want80" || fail "cols 80: $(sed -n '3p' "$RUN/out")"
COLUMNS=120
assert_code 'list columns 120' 0 node list
want120='    1 node-01 -      2 node-02 -      3 node-03 -      4 node-04 -      5 node-05 -      6 node-06 -      7 node-07 -'
test "$(sed -n '3p' "$RUN/out")" = "$want120" || fail "cols 120: $(sed -n '3p' "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=80
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"主代理":{"all":["a","b"],"now":"a","type":"Selector"},"a":{"type":"Shadowsocks"},"b":{"type":"Shadowsocks"}}}
EOF
assert_code 'list manual' 0 node list
test "$(sed -n '1p' "$RUN/out")" = '当前：主代理 → a（手动）→ a 第1个' || fail "manual head: $(sed -n '1p' "$RUN/out")"
test "$(sed -n '3p' "$RUN/out")" = '[*] 1 a -      2 b -' || fail "manual cells: $(sed -n '3p' "$RUN/out")"
python3 -c 'import json,os; p=os.environ["AXS_RUN"]+"/fake/proxies.json"; d=json.load(open(p)); d["proxies"]["主代理"].pop("now", None); json.dump(d, open(p,"w"))'
assert_code 'list none' 0 node list
test "$(sed -n '1p' "$RUN/out")" = '当前：无' || fail "cleared head: $(sed -n '1p' "$RUN/out")"
if grep -F '[*]' "$RUN/out" >/dev/null; then
    fail 'cleared selection still starred'
fi

new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=80
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"主代理":{"all":["自动选择"],"now":"自动选择","type":"Selector"},"自动选择":{"all":["a","b"],"now":"b","type":"URLTest"},"a":{"type":"Shadowsocks"},"b":{"type":"Shadowsocks"}}}
EOF
assert_code 'list auto' 0 node list
test "$(sed -n '1p' "$RUN/out")" = '当前：主代理 → 自动选择（自动，url-test）→ b 第2个' || fail "auto head: $(sed -n '1p' "$RUN/out")"
test "$(sed -n '3p' "$RUN/out")" = '    1 a -  [*] 2 b -' || fail "auto cells: $(sed -n '3p' "$RUN/out")"
python3 -c 'import json,os; p=os.environ["AXS_RUN"]+"/fake/proxies.json"; d=json.load(open(p)); d["proxies"]["自动选择"]["type"]="Fallback"; d["proxies"]["自动选择"].pop("now", None); json.dump(d, open(p,"w"))'
assert_code 'list auto none' 0 node list
test "$(sed -n '1p' "$RUN/out")" = '当前：主代理 → 自动选择（自动，fallback）→ -' || fail "auto none: $(sed -n '1p' "$RUN/out")"
python3 -c 'import json,os; p=os.environ["AXS_RUN"]+"/fake/proxies.json"; d=json.load(open(p)); d["proxies"]["自动选择"]["type"]="LoadBalance"; d["proxies"]["自动选择"]["now"]="a"; json.dump(d, open(p,"w"))'
assert_code 'list balance' 0 node list
test "$(sed -n '1p' "$RUN/out")" = '当前：主代理 → 自动选择（自动，load-balance）→ a 第1个' || fail "balance head: $(sed -n '1p' "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=30
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"ab":{"type":"Shadowsocks"},"香港":{"type":"Shadowsocks"}}}
EOF
assert_code 'list width' 0 node list
test "$(sed -n '3p' "$RUN/out")" = '    1 ab -        2 香港 -' || fail "cjk width: $(sed -n '3p' "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=80
arm_api PROXY 204 0
now=$(date +%s)
mkdir -p "$RUN/cache"
chmod 700 "$RUN/cache"
printf 'ts=%s\nresult=ok\n{"a": 42}\n' "$((now - 180))" >"$RUN/cache/node-test"
chmod 600 "$RUN/cache/node-test"
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"主代理":{"all":["a","b"],"now":"a","type":"Selector"},"PROXY":{"all":["a","b"],"now":"a","type":"Selector"},"a":{"type":"Shadowsocks"},"b":{"type":"Shadowsocks"}}}
EOF
assert_code 'list cache' 0 node list
test "$(sed -n '1p' "$RUN/out")" = '当前：主代理 → a（手动）→ a 第1个' || fail "cache head: $(sed -n '1p' "$RUN/out")"
test "$(sed -n '2p' "$RUN/out")" = '最近测速：3 分钟前' || fail "cache age: $(sed -n '2p' "$RUN/out")"
test "$(sed -n '3p' "$RUN/out")" = '[*] 1 a 42      2 b  -' || fail "cache cells: $(sed -n '3p' "$RUN/out")"
assert_code 'switch cache' 0 node switch PROXY a
test "$(cat "$RUN/out")" = "$(printf 'PROXY\ta\t42')" || fail "switch delay: $(cat "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"OTHER":{"all":["a","b"],"now":"a","type":"Selector"},"PROXY":{"all":["2","a","b"],"now":"a","type":"Selector"},"2":{"type":"Shadowsocks"},"a":{"type":"Shadowsocks"},"b":{"type":"Shadowsocks"}}}
EOF
: >"$RUN/fake/log"
assert_code 'switch digit name' 0 node switch PROXY 2
grep -q '{"name": "2"}' "$RUN/fake/log" || fail "digit name body: $(cat "$RUN/fake/log")"
: >"$RUN/fake/log"
assert_code 'switch number' 0 node switch OTHER 2
grep -q '{"name": "a"}' "$RUN/fake/log" || fail "number body: $(cat "$RUN/fake/log")"
: >"$RUN/fake/log"
assert_code 'switch number missing' 3 node switch OTHER 1
grep -q '节点不存在' "$RUN/err" || fail "number missing text: $(cat "$RUN/err")"
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'number outside group sent select'
fi
: >"$RUN/fake/log"
assert_code 'switch number range' 3 node switch PROXY 9
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'out of range sent select'
fi
assert_code 'list bad flag' 1 node list --nope

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"GLOBAL":{"all":["DIRECT"],"now":"DIRECT","type":"Selector"},"主代理":{"all":["自动选择","a"],"now":"自动选择","type":"Selector"},"自动选择":{"all":["a","新加坡aw1"],"now":"新加坡aw1","type":"URLTest"},"DIRECT":{"type":"Direct"},"a":{"type":"Shadowsocks"},"新加坡aw1":{"type":"Shadowsocks"}}}
EOF
export COLUMNS=80
assert_code 'list leaf' 0 node list
head=$(sed -n '1p' "$RUN/out")
printf '%s\n' "$head" | grep -F '→ 新加坡aw1 第' >/dev/null || fail "leaf missing: $head"
printf '%s\n' "$head" | grep -F '自动选择（自动，url-test）→ 新加坡aw1' >/dev/null || fail "auto leaf: $head"
: >"$RUN/fake/log"
assert_code 'default skips global' 0 node test
python3 -c 'import os,urllib.parse; log=open(os.environ["AXS_RUN"]+"/fake/log",encoding="utf-8").read();
assert "/group/"+urllib.parse.quote("主代理")+"/delay" in log, log
assert "/group/GLOBAL/delay" not in log, log'

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"GLOBAL":{"all":["DIRECT"],"now":"DIRECT","type":"Selector"},"PROXY":{"all":["a"],"now":"a","type":"Selector"},"自动选择":{"all":["a"],"now":"a","type":"URLTest"},"DIRECT":{"type":"Direct"},"a":{"type":"Shadowsocks"}}}
EOF
: >"$RUN/fake/log"
assert_code 'default auto' 0 node test
python3 -c 'import os,urllib.parse; log=open(os.environ["AXS_RUN"]+"/fake/log",encoding="utf-8").read();
assert "/group/"+urllib.parse.quote("自动选择")+"/delay" in log, log
assert "/group/GLOBAL/delay" not in log, log'

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"GLOBAL":{"all":["DIRECT"],"now":"DIRECT","type":"Selector"},"DIRECT":{"type":"Direct"}}}
EOF
: >"$RUN/fake/log"
assert_code 'default none' 3 node test
grep -qx '没有可测组' "$RUN/err" || fail "none text: $(cat "$RUN/err")"
grep -qx 'GLOBAL' "$RUN/err" || fail "none list: $(cat "$RUN/err")"
if grep -q '/delay' "$RUN/fake/log"; then
    fail 'none sent delay'
fi

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
: >"$RUN/fake/down"
assert_code 'delay one line' 3 node test PROXY
test "$(grep -c . "$RUN/err")" -eq 1 || fail "delay stderr: $(cat "$RUN/err")"
grep -qx '控制器' "$RUN/err" || fail "delay reason: $(cat "$RUN/err")"

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
test "$(cat "$RUN/out")" = "$(printf 'PROXY\ta b\t-')" || fail "switch out: $(cat "$RUN/out")"
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
test ! -e "$RUN/cache/net-test" || fail 'forbid wrote a net cache'

new_run
export AXS_MIXED_PORT=18086 AXS_NET_TIMEOUT_MS=200
open_mixed 18086
assert_code 'net cache fail' 3 net test 'http://127.0.0.1:9/'
test -f "$RUN/cache/net-test" || fail 'net test wrote no cache'
grep -q '^result=fail$' "$RUN/cache/net-test" || fail 'net cache result'
if grep -q '127.0.0.1' "$RUN/cache/net-test"; then
    fail 'net cache stored the url'
fi
test "$(stat -c '%a' "$RUN/cache")" = 700 || fail 'net cache dir mode'


seed_clean() {
    printf '%s\n' drop >"$RUN/config.yaml"
    printf '%s\n' bak >"$RUN/config.yaml.bak"
    printf '%s\n' info >"$RUN/userinfo"
    printf '%s\n' fetch >"$RUN/fetch.yaml"
    printf '%s\n' hdr >"$RUN/fetch.hdr"
    printf '%s\n' 999999 >"$RUN/mihomo.pid"
    printf '%s\n' url >"$RUN/subscription.url"
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

new_run
mark_up
printf '%s\n' drop >"$RUN/config.yaml"
printf '%s\n' url >"$RUN/subscription.url"
assert_code 'clean while up' 2 clean --yes
grep -q 'axs stop' "$RUN/err" || fail "clean up text: $(cat "$RUN/err")"
test -f "$RUN/config.yaml" || fail 'clean deleted while running'
assert_code 'clean up no yes' 2 clean
test -f "$RUN/config.yaml" || fail 'clean no-yes deleted while running'
assert_code 'sub clean while up' 2 sub clean --yes
test -f "$RUN/subscription.url" || fail 'sub clean deleted while running'

new_run
seed_clean
assert_code 'clean no yes' 1 clean
grep -F "$RUN/config.yaml" "$RUN/out" >/dev/null || fail 'clean did not list the path'
test -f "$RUN/config.yaml" || fail 'clean deleted without --yes'
set +e
printf 'y\n' | "$AXS" clean >"$RUN/out" 2>"$RUN/err"
piped=$?
set -e
test "$piped" -eq 1 || fail "piped yes want 1 got $piped"
test -f "$RUN/config.yaml" || fail 'piped yes deleted'
code=0
pty_answer n clean || code=$?
test "$code" -eq 1 || fail "pty no want 1 got $code"
test -f "$RUN/config.yaml" || fail 'pty no deleted'
code=0
pty_answer y clean || code=$?
test "$code" -eq 0 || fail "pty yes want 0 got $code"
test ! -e "$RUN/config.yaml" || fail 'pty yes kept config'
test -f "$RUN/subscription.url" || fail 'pty yes dropped the url'

new_run
seed_clean
assert_code 'clean yes' 0 clean --yes
grep -q '已删除' "$RUN/out" || fail 'clean yes silent'
for name in config.yaml config.yaml.bak userinfo fetch.yaml fetch.hdr mihomo.pid; do
    test ! -e "$RUN/$name" || fail "clean kept $name"
done
for name in subscription.url secret rules.list override.yaml subscription.yaml; do
    test -f "$RUN/$name" || fail "clean dropped $name"
done
assert_code 'clean again' 0 clean --yes

new_run
printf '%s\n' only >"$RUN/config.yaml"
assert_code 'clean partial' 0 clean --yes
test ! -e "$RUN/config.yaml" || fail 'partial clean kept config'
grep -q '已删除' "$RUN/out" || fail 'partial clean silent'

new_run
seed_clean
assert_code 'sub clean yes' 0 sub clean --yes
grep -q '已删除' "$RUN/out" || fail 'sub clean silent'
for name in subscription.url subscription.yaml userinfo fetch.yaml fetch.hdr; do
    test ! -e "$RUN/$name" || fail "sub clean kept $name"
done
for name in config.yaml config.yaml.bak secret rules.list override.yaml mihomo.pid; do
    test -f "$RUN/$name" || fail "sub clean dropped $name"
done
assert_code 'sub clean again' 0 sub clean --yes

new_run
outside=$(mktemp)
printf '%s\n' outside >"$outside"
ln -s "$outside" "$RUN/config.yaml"
printf '%s\n' keep >"$RUN/secret"
printf '%s\n' keep >"$RUN/rules.list"
assert_code 'clean symlink' 3 clean --yes
grep -q '越界' "$RUN/err" || fail "symlink text: $(cat "$RUN/err")"
test -f "$outside" || fail 'clean followed a symlink'
test -L "$RUN/config.yaml" || fail 'clean removed the symlink after refusing'
test "$(cat "$RUN/secret")" = keep || fail 'symlink clean deleted a sibling'
rm -f "$outside"

new_run
printf '%s\n' drop >"$RUN/config.yaml"
printf '%s\n' keep >"$RUN/secret"
chmod 500 "$RUN"
set +e
"$AXS" clean --yes >"$RUN/out" 2>"$RUN/err"
denied=$?
set -e
chmod 700 "$RUN"
test "$denied" -eq 3 || fail "undeletable want 3 got $denied"
grep -q '删除失败' "$RUN/err" || fail "undeletable text: $(cat "$RUN/err")"
test -f "$RUN/config.yaml" || fail 'failed clean removed the file'
test -f "$RUN/secret" || fail 'failed clean removed secret'

new_run
assert_code 'clean usage' 1 clean --no
assert_code 'clean extra' 1 clean --yes extra
assert_code 'sub clean extra' 1 sub clean --yes extra

ESC=$(printf '\033')
new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=200
arm_api PROXY 204 0
python3 -c 'import json; json.dump({"proxies": {f"node-{i:02d}": {"type": "Shadowsocks"} for i in range(1, 11)} | {"主代理": {"all": ["node-01"], "now": "node-01", "type": "Selector"}}}, open("'"$RUN"'/fake/proxies.json", "w"))'
assert_code 'align mark' 0 node list
data=$(sed -n '3p' "$RUN/out")
printf '%s\n' "$data" | grep -q '^\[\*\] ' || fail "mark width: $data"
# units digit of 1 and of 10 sit in the same column of their cells
python3 -c 'import os; line=open(os.environ["AXS_RUN"]+"/out",encoding="utf-8").read().splitlines()[2]
assert line.startswith("[*]  1 "), line
idx=line.index("    10 node-10")
assert line[4:6]==" 1", line
assert line[idx+4:idx+6]=="10", line'
if grep -q "$ESC" "$RUN/out"; then
    fail 'non-tty list has color'
fi

new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=80 AXS_COLOR=always
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"主代理":{"all":["a"],"now":"a","type":"Selector"},"a":{"type":"Shadowsocks"}}}
EOF
mkdir -p "$RUN/cache"
printf 'ts=1\nresult=ok\n{"a": 50}\n' >"$RUN/cache/node-test"
assert_code 'color always' 0 node list
grep -F -q "${ESC}[32m" "$RUN/out" || fail "always green: $(cat "$RUN/out")"
grep -F -q "${ESC}[1m" "$RUN/out" || fail "always bold: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32m[*]" "$RUN/out" || fail "mark green: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32ma" "$RUN/out" || fail "selected name: $(cat "$RUN/out")"
grep -F -q "${ESC}[90m1" "$RUN/out" || fail "number gray: $(cat "$RUN/out")"
assert_code 'groups tone' 0 node groups
grep -F -q "${ESC}[36m主代理" "$RUN/out" || fail "group cyan: $(cat "$RUN/out")"
grep -F -q "${ESC}[90mSelector" "$RUN/out" || fail "type gray: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32ma" "$RUN/out" || fail "now green: $(cat "$RUN/out")"
export AXS_COLOR=never
assert_code 'color never' 0 node list
if grep -q "$ESC" "$RUN/out"; then
    fail 'never still colored'
fi

new_run
mark_up
export AXS_API="127.0.0.1:18081" AXS_COLOR=always
arm_api PROXY 204 0
printf '%s\n' '{"a": 50, "b": 150, "c": 300}' >"$RUN/fake/delay.json"
assert_code 'delay colors' 0 node test PROXY
grep -F -q "${ESC}[32m50${ESC}[0m" "$RUN/out" || fail "green delay: $(cat "$RUN/out")"
grep -F -q "${ESC}[33m150${ESC}[0m" "$RUN/out" || fail "yellow delay: $(cat "$RUN/out")"
grep -F -q "${ESC}[31m300${ESC}[0m" "$RUN/out" || fail "red delay: $(cat "$RUN/out")"
python3 -c 'import json,os; p=os.environ["AXS_RUN"]+"/cache/node-test"; text=open(p,encoding="utf-8").read();
line=[row for row in text.splitlines() if row.startswith("{")][0]
assert json.loads(line)=={"a":50,"b":150,"c":300}, text'
printf '%s\n' '{"PROXY": "timeout", "a": 12}' >"$RUN/fake/delay.json"
assert_code 'delay timeout' 0 node test PROXY
grep -F -q "${ESC}[36mPROXY" "$RUN/out" || fail "group name: $(cat "$RUN/out")"
grep -F -q "${ESC}[31m超时" "$RUN/out" || fail "timeout red: $(cat "$RUN/out")"
grep -F -q "${ESC}[32m12" "$RUN/out" || fail "node delay: $(cat "$RUN/out")"
export AXS_COLOR=never
assert_code 'delay plain' 0 node test PROXY
if grep -q "$ESC" "$RUN/out"; then
    fail 'delay never colored'
fi

new_run
export AXS_SYSTEMD=1 AXS_SYSTEMCTL="$ROOT/tests/fake-systemctl" AXS_COLOR=always
assert_code 'service enable' 0 service enable
grep -q 'enable axs.service axs-refresh.timer' "$RUN/systemctl.log" || fail "enable log: $(cat "$RUN/systemctl.log")"
if grep -q 'start axs.service' "$RUN/systemctl.log"; then
    fail 'enable started the service'
fi
grep -F -q "${ESC}[32menabled${ESC}[0m" "$RUN/out" || fail "enable color: $(cat "$RUN/out")"
: >"$RUN/systemctl.log"
assert_code 'service disable' 0 service disable
grep -q 'disable axs.service axs-refresh.timer' "$RUN/systemctl.log" || fail "disable log: $(cat "$RUN/systemctl.log")"
if grep -q 'stop axs.service' "$RUN/systemctl.log"; then
    fail 'disable stopped the service'
fi
grep -F -q "${ESC}[31mdisabled${ESC}[0m" "$RUN/out" || fail "disable color: $(cat "$RUN/out")"
printf '%s\n' enabled >"$RUN/systemctl.enabled"
export AXS_MIXED_PORT=7897 AXS_API=127.0.0.1:9097 AXS_COLOR=never
assert_code 'status enabled' 2 status
grep -q '开机自启：enabled' "$RUN/out" || fail "status enabled: $(cat "$RUN/out")"
if grep -q "$ESC" "$RUN/out"; then
    fail 'status never colored'
fi
rm -f "$RUN/systemctl.enabled"
export AXS_COLOR=always
assert_code 'status disabled color' 2 status
grep -F -q "${ESC}[31mdisabled${ESC}[0m" "$RUN/out" || fail "status disabled color: $(cat "$RUN/out")"

new_run
assert_code 'service no systemd' 3 service enable
grep -q '没有 systemd' "$RUN/err" || fail "no systemd: $(cat "$RUN/err")"
assert_code 'service usage' 1 service start
export AXS_COLOR=always
assert_code 'bare help color' 1
test "$(grep -c . "$RUN/err")" -eq 6 || fail "bare lines: $(cat "$RUN/err")"
grep -q '用法：axs start|stop|status|restart|ensure|clean' "$RUN/err" || fail "bare help: $(cat "$RUN/err")"
grep -q 'axs net test' "$RUN/err" || fail "bare last: $(cat "$RUN/err")"
if grep -q 'health' "$RUN/err"; then
    fail 'help lists health'
fi
if grep -q "$ESC" "$RUN/err"; then
    fail "bare help colored: $(cat "$RUN/err")"
fi
test ! -s "$RUN/out" || fail "bare stdout: $(cat "$RUN/out")"
assert_code 'unknown help' 1 nope
test "$(grep -c . "$RUN/err")" -eq 6 || fail "unknown lines: $(cat "$RUN/err")"
assert_code 'help stdout' 0 help
grep -q '节点' "$RUN/out" || fail "help out: $(cat "$RUN/out")"
grep -q '例：axs status' "$RUN/out" || fail "help example: $(cat "$RUN/out")"
grep -q '颜色只是增强' "$RUN/out" || fail "help color note: $(cat "$RUN/out")"
test ! -s "$RUN/err" || fail "help stderr: $(cat "$RUN/err")"
if grep -q 'health' "$RUN/out"; then
    fail 'long help lists health'
fi
if grep -F -q "${ESC}[31m" "$RUN/out"; then
    fail "help is red: $(cat "$RUN/out")"
fi
grep -F -q "${ESC}[36m" "$RUN/out" || fail "help command color: $(cat "$RUN/out")"
grep -F -q "${ESC}[90m" "$RUN/out" || fail "help desc color: $(cat "$RUN/out")"
grep -F -q "${ESC}[1m" "$RUN/out" || fail "help title: $(cat "$RUN/out")"
python3 -c 'import os,re
esc=re.compile("\033\\[[0-9;]*m")
text=open(os.environ["AXS_RUN"]+"/out",encoding="utf-8").read()
rows=[esc.sub("", line) for line in text.splitlines() if esc.sub("", line).startswith("axs ")]
assert rows, text
assert all(len(line)>=24 and line[22:24]=="  " and line[24]!=" " for line in rows), rows'
assert_code 'help flag' 0 --help
grep -q '清理' "$RUN/out" || fail "flag out: $(cat "$RUN/out")"
assert_code 'help short flag' 0 -h
grep -q '例：axs node list' "$RUN/out" || fail "short flag: $(cat "$RUN/out")"
assert_code 'help flag extra' 1 -h extra
test "$(grep -c . "$RUN/err")" -eq 6 || fail "flag extra: $(cat "$RUN/err")"
export AXS_COLOR=never
assert_code 'help never' 0 help
if grep -q "$ESC" "$RUN/out"; then
    fail 'help never colored'
fi
grep -q '颜色只是增强，管道或 NO_COLOR 下信息仍完整' "$RUN/out" || fail "help note plain: $(cat "$RUN/out")"
export AXS_COLOR=always
now=$(date +%s)
printf 'upload=1\nexpire=%s\n' "$((now + 40 * 86400))" >"$RUN/userinfo"
assert_code 'sub color' 0 sub get
grep -F -q "${ESC}[90m上传:" "$RUN/out" || fail "sub label: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32m" "$RUN/out" || fail "sub days: $(cat "$RUN/out")"
grep -q '1.0B' "$RUN/out" || fail "sub bytes: $(cat "$RUN/out")"
export AXS_COLOR=never
assert_code 'sub plain' 0 sub get
if grep -q "$ESC" "$RUN/out"; then
    fail 'sub never colored'
fi

new_run
mark_up
prepare_health 18084
python3 -c 'import json,os; json.dump({"proxies":{"主代理":{"all":["自动选择"],"now":"自动选择","type":"Selector"},"自动选择":{"all":["a"],"now":"a","type":"URLTest"},"GLOBAL":{"all":["DIRECT"],"now":"DIRECT","type":"Selector"},"a":{"type":"Shadowsocks"},"DIRECT":{"type":"Direct"}}}, open(os.environ["AXS_RUN"]+"/fake/proxies.json","w"))'
now=$(date +%s)
printf 'upload=1536\nexpire=%s\n' "$((now - 10))" >"$RUN/userinfo"
mkdir -p "$RUN/cache"
printf 'ts=%s\nresult=ok\n' "$((now - 180))" >"$RUN/cache/net-test"
export AXS_COLOR=always
assert_code 'status tone' 5 status
grep -F -q "${ESC}[90m服务：" "$RUN/out" || fail "status label: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32m运行中" "$RUN/out" || fail "status up: $(cat "$RUN/out")"
grep -F -q "${ESC}[32m监听" "$RUN/out" || fail "status port: $(cat "$RUN/out")"
grep -F -q "${ESC}[36m主代理" "$RUN/out" || fail "status group: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32ma" "$RUN/out" || fail "status now: $(cat "$RUN/out")"
python3 -c 'import os,re,sys
esc=re.compile("\x1b\\[[0-9;]*m")
text=esc.sub("", open(os.environ["AXS_RUN"]+"/out",encoding="utf-8").read())
chain="节点：主代理 → 自动选择（自动，url-test）→ a · GLOBAL = DIRECT"
if chain not in text:
    sys.stderr.write(text)
    raise SystemExit(1)
if "上传 1.5K" not in text:
    raise SystemExit(2)
want=["服务：","节点：","订阅：","端口：","控制器：","开机自启：","定时刷新：","最近 net test：","最近 node test："]
got=[line.split("：",1)[0]+"：" for line in text.splitlines() if "：" in line]
if got!=want:
    sys.stderr.write(repr(got))
    raise SystemExit(3)
' || fail "status plain shape: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;31m已过期" "$RUN/out" || fail "status sub: $(cat "$RUN/out")"
grep -F -q "${ESC}[32m全部通" "$RUN/out" || fail "status net: $(cat "$RUN/out")"
export AXS_COLOR=never
assert_code 'status tone plain' 5 status
if grep -q "$ESC" "$RUN/out"; then
    fail 'status never colored'
fi
grep -q '节点：主代理 → 自动选择（自动，url-test）→ a · GLOBAL = DIRECT' "$RUN/out" || fail "plain chain: $(cat "$RUN/out")"
grep -q '上传 1.5K' "$RUN/out" || fail "plain bytes: $(cat "$RUN/out")"


new_run
printf '%s\n' drop >"$RUN/config.yaml"
export AXS_COLOR=always
assert_code 'clean tone' 0 clean --yes
grep -F -q "${ESC}[32m已删除" "$RUN/out" || fail "clean green: $(cat "$RUN/out")"
printf '%s\n' drop >"$RUN/config.yaml"
export AXS_COLOR=never
assert_code 'clean tone plain' 0 clean --yes
if grep -q "$ESC" "$RUN/out"; then
    fail 'clean never colored'
fi
grep -q '已删除' "$RUN/out" || fail 'clean plain text'

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

echo "ok $PASS"
