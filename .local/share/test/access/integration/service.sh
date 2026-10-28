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
grep -q '状态    未运行（手动）' "$RUN/out" || fail "down service: $(cat "$RUN/out")"
grep -qx '  -' "$RUN/out" || fail "down route: $(cat "$RUN/out")"
if grep -q 'GLOBAL  ' "$RUN/out"; then fail "down global: $(cat "$RUN/out")"; fi
grep -q 'net     -' "$RUN/out" || fail "down net cache: $(cat "$RUN/out")"
grep -q 'node    -' "$RUN/out" || fail "down node cache: $(cat "$RUN/out")"
grep -q '自启    -' "$RUN/out" || fail "down timer: $(cat "$RUN/out")"
if grep -q "$(printf '\033')" "$RUN/out"; then
    fail 'status down colored off a tty'
fi

new_run
now=$(date +%s)
mkdir -p "$RUN/cache"
printf 'ts=%s\nresult=ok\n' "$((now - 180))" >"$RUN/cache/net-test"
printf 'ts=%s\nresult=ok\n' "$((now - 3600))" >"$RUN/cache/node-test"
assert_code 'status cache age' 2 status
grep -q 'net     3 分钟前 · 全部通' "$RUN/out" || fail "cache net: $(cat "$RUN/out")"
grep -q 'node    1 小时前' "$RUN/out" || fail "cache node: $(cat "$RUN/out")"

new_run
export AXS_SYSTEMD=1 AXS_SYSTEMCTL="$TEST/fixtures/fake-systemctl"
assert_code 'systemd start' 0 service start
grep -q 'start axs.service' "$RUN/systemctl.log" || fail "start log: $(cat "$RUN/systemctl.log" 2>/dev/null)"
assert_code 'systemd stop' 0 service stop
grep -q 'stop axs.service' "$RUN/systemctl.log" || fail "stop log: $(cat "$RUN/systemctl.log")"
assert_code 'systemd restart' 0 service restart
grep -q 'restart axs.service' "$RUN/systemctl.log" || fail "restart log: $(cat "$RUN/systemctl.log")"
: >"$RUN/systemctl.log"
printf '%s\n' active >"$RUN/systemctl.active"
assert_code 'systemd ensure active' 0 service ensure
if grep -q 'start axs.service' "$RUN/systemctl.log"; then
    fail "active ensure started: $(cat "$RUN/systemctl.log")"
fi
export AXS_MIXED_PORT=7897 AXS_API=127.0.0.1:9097
assert_code 'systemd status' 2 status
grep -q '状态    运行中（systemd，pid 4242，-）' "$RUN/out" || fail "systemd status: $(cat "$RUN/out")"
grep -q 'list-timers --output=json axs-refresh.timer' "$RUN/systemctl.log" || fail "timer query: $(cat "$RUN/systemctl.log")"
if grep -q 'NextElapseUSecRealtime' "$RUN/systemctl.log"; then
    fail "timer still uses NextElapseUSecRealtime: $(cat "$RUN/systemctl.log")"
fi
python3 -c 'import os, time, datetime, pathlib, sys
text = pathlib.Path(os.environ["AXS_RUN"] + "/out").read_text(encoding="utf-8")
sec = 4102444800000000 // 1000000
hhmm = datetime.datetime.fromtimestamp(sec).strftime("%H:%M")
delta = sec - int(time.time())
if delta < 0:
    delta = 0
if delta < 60:
    rel = f"{delta} 秒后"
elif delta < 3600:
    rel = f"{delta // 60} 分钟后"
elif delta < 86400:
    rel = f"{delta // 3600} 小时后"
else:
    rel = f"{delta // 86400} 天后"
want = f"下次 {hhmm}（{rel}）"
if want not in text:
    sys.stderr.write(want + "\n" + text)
    raise SystemExit(1)
' || fail "timer parse: $(cat "$RUN/out")"
grep -q 'user    ' "$RUN/out" || fail "status proxy line: $(cat "$RUN/out")"
grep -q 'system  ' "$RUN/out" || fail "status system line: $(cat "$RUN/out")"
grep -q 'session ' "$RUN/out" || fail "status session line: $(cat "$RUN/out")"

new_run
unset AXS_SYSTEMD
export AXS_SYSTEMCTL="$TEST/fixtures/fake-systemctl"
printf '%s\n' active >"$RUN/systemctl.active"
export AXS_MIXED_PORT=7897 AXS_API=127.0.0.1:9097
assert_code 'systemd default leg' 2 status
grep -q '状态    运行中（systemd，pid 4242，' "$RUN/out" || fail "default leg: $(cat "$RUN/out")"
if grep -q 'loaded' "$RUN/out"; then
    fail "default leg clobbered state: $(cat "$RUN/out")"
fi
grep -q '下次 ' "$RUN/out" || fail "default leg timer: $(cat "$RUN/out")"
loads=$(grep -c 'LoadState' "$RUN/systemctl.log" || true)
test "$loads" -eq 1 || fail "LoadState count $loads: $(cat "$RUN/systemctl.log")"

new_run
export AXS_SYSTEMD=1 AXS_SYSTEMCTL="$TEST/fixtures/fake-systemctl"
printf '%s\n' '[{"next":4102444800000000,"left":null,"last":null,"passed":null,"unit":"axs-refresh.timer","activates":"axs-refresh.service"}]' >"$RUN/timer.json"
assert_code 'timer missing left' 2 status
grep -q '刷新：-' "$RUN/out" || fail "missing left: $(cat "$RUN/out")"
if grep -q '下次 ' "$RUN/out"; then
    fail "missing left invented a time: $(cat "$RUN/out")"
fi

new_run
export AXS_SESSION_PID=2147483001
assert_code 'status proxy off' 2 status
grep -q 'user      off (unset)' "$RUN/out" || fail "status proxy off: $(cat "$RUN/out")"
grep -q -E 'system    (on|off) \(mode=' "$RUN/out" || fail "status system line: $(cat "$RUN/out")"
grep -q 'session   persist disabled · effect -' "$RUN/out" || fail "status session line: $(cat "$RUN/out")"
if grep -q 'no-x-session' "$RUN/out"; then
    fail 'disabled effect is no-x-session'
fi
unset AXS_SESSION_PID || true
proxy_status_env
grep -q 'user      on (' "$RUN/out" || fail "status proxy on: $(cat "$RUN/out")"

new_run
assert_code 'status down' 2 status

new_run
printf '%s\n' '$' >"$RUN/mihomo.pid"
assert_code 'status bad pid' 2 status
grep -q '未运行（手动）' "$RUN/out" || fail "bad pid out: $(cat "$RUN/out")"
grep -q '告警：mihomo.pid 不是数字' "$RUN/err" || fail "bad pid err: $(cat "$RUN/err")"

new_run
: >"$RUN/mihomo.pid"
assert_code 'status empty pid' 2 status
grep -q '告警：mihomo.pid 不是数字' "$RUN/err" || fail "empty pid err: $(cat "$RUN/err")"

new_run
export AXS_MIHOMO="$TEST/fixtures/fake-mihomo"
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
assert_code 'start busy' 2 service start
grep -q '端口已被占用' "$RUN/err" || fail 'busy text'
if [ -f "$RUN/mihomo.pid" ]; then
    fail 'start launched while port was busy'
fi

new_run
export AXS_MIHOMO="$TEST/fixtures/fake-mihomo" AXS_MIXED_PORT=18080
printf '%s\n' 'placeholder: true' >"$RUN/config.yaml"
assert_code 'start' 0 service start
cat "$RUN/mihomo.pid" >>"$PIDS"
assert_code 'start again' 0 service start
kill "$(cat "$RUN/mihomo.pid")" 2>/dev/null || true
assert_code 'stop' 0 service stop
assert_code 'stop again' 0 service stop

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
test "$(grep -c 'GET /proxies' "$RUN/fake/log")" -eq 1 || fail "group queries: $(cat "$RUN/fake/log")"

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
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
printf '%s\n' 'DOMAIN kept.example DIRECT' >"$RUN/rules.list"
cp "$RUN/rules.list" "$RUN/rules.before"
: >"$RUN/fake/log"
assert_code 'via one query' 3 rule add via example.com PROXY
if ! cmp -s "$RUN/rules.before" "$RUN/rules.list"; then
    fail 'via one query wrote rules'
fi
grep -q '没有订阅' "$RUN/err" || fail "via one query text: $(cat "$RUN/err")"
test "$(grep -c 'GET /proxies' "$RUN/fake/log")" -eq 1 || fail "via queries: $(cat "$RUN/fake/log")"

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
chmod 600 "$RUN/subscription.url"
export AXS_FETCH="$TEST/fixtures/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'refresh down' 0 subscription refresh
no_secret_text 'refresh down'
if grep -F "$CANARY" "$RUN/config.yaml" >/dev/null 2>&1; then
    fail 'canary stored in config'
fi
test -f "$RUN/config.yaml.bak" && fail 'bak created when there was no previous config'
mode=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["mode"])' "$RUN/config.yaml")
test "$mode" = rule || fail "mode $mode"
assert_code 'subscription status' 0 subscription status
if grep -q '未知' "$RUN/out"; then
    fail 'userinfo missing'
fi
grep -q '剩余' "$RUN/out" || fail 'remaining life not shown'
no_secret_text 'subscription status'

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
printf '%s\n' 'SENTINEL-OLD' >"$RUN/config.yaml"
printf '%s\n' 'SENTINEL-SUB' >"$RUN/subscription.yaml"
export AXS_FETCH="$TEST/fixtures/fake-fetch-html" FIXTURE_SUB="$FIX"
assert_code 'refresh reject' 3 subscription refresh
test "$(cat "$RUN/config.yaml")" = "SENTINEL-OLD" || fail 'bad fetch replaced config'
test "$(cat "$RUN/subscription.yaml")" = "SENTINEL-SUB" || fail 'bad fetch replaced body'
no_secret_text 'refresh reject'

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$TEST/fixtures/fake-fetch-fail"
assert_code 'refresh transport' 3 subscription refresh
test ! -f "$RUN/config.yaml" || fail 'transport failure left a config'

new_run
printf '%s\n' 'https://example.invalid/link/\?clash\=1' >"$RUN/subscription.url"
assert_code 'refresh backslash' 3 subscription refresh
grep -q -F '链接含转义字符（如 \?），请去掉反斜杠' "$RUN/err" || fail "backslash text: $(cat "$RUN/err")"
test ! -f "$RUN/config.yaml" || fail 'backslash left a config'

new_run
printf '%s\n' 'https://example.invalid/has space' >"$RUN/subscription.url"
assert_code 'refresh space' 3 subscription refresh
grep -q -F '链接含转义字符（如 \?），请去掉反斜杠' "$RUN/err" || fail "space text: $(cat "$RUN/err")"
test ! -f "$RUN/config.yaml" || fail 'space left a config'

new_run
printf '%s\n' 'https://example.invalid/sub' >"$RUN/subscription.url"
export AXS_FETCH="$TEST/fixtures/fake-fetch-empty"
assert_code 'refresh empty' 3 subscription refresh
grep -q -F '订阅返回空内容/非 YAML（HTTP 200, text/html），请检查链接' "$RUN/err" || fail "empty text: $(cat "$RUN/err")"
test ! -f "$RUN/config.yaml" || fail 'empty left a config'

new_run
printf '%s\n' 'https://example.invalid/sub' >"$RUN/subscription.url"
printf '%s\n' 'SENTINEL-OLD' >"$RUN/config.yaml"
printf '%s\n' 'OLD-BAK' >"$RUN/config.yaml.bak"
export AXS_FETCH="$TEST/fixtures/fake-fetch-html"
assert_code 'refresh html' 3 subscription refresh
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
export AXS_FETCH="$TEST/fixtures/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'reload rollback' 3 subscription refresh
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
python3 "$TEST/support/prep.py" "$ROOT" "$RUN" "" "$AXS_API"
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
export AXS_FETCH="$TEST/fixtures/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'lock busy' 4 subscription refresh
grep -q '锁' "$RUN/err" || fail 'lock text'


new_run
mark_up
prepare_health 18080
now=$(date +%s)
printf '%s\n' "expire=$((now - 10))" >"$RUN/userinfo"
assert_code 'status expired' 5 status
grep -q '状态    运行中（手动，pid' "$RUN/out" || fail "expired service: $(cat "$RUN/out")"
grep -q '18080 监听' "$RUN/out" || fail "expired port: $(cat "$RUN/out")"
grep -q '控制器 18081 可达' "$RUN/out" || fail "expired api: $(cat "$RUN/out")"
grep -qx '  -' "$RUN/out" || fail "expired route: $(cat "$RUN/out")"
grep -q '剩余 已过期' "$RUN/out" || fail "expired sub: $(cat "$RUN/out")"

new_run
mark_up
prepare_health 18082
now=$(date +%s)
printf '%s\n' "expire=$((now + 2 * 86400))" >"$RUN/userinfo"
assert_code 'status soon' 0 status
grep -E -q '剩余 [12] 天（警告）' "$RUN/out" || fail "soon text: $(cat "$RUN/out")"

new_run
mark_up
prepare_health 18083
: >"$RUN/fake/down"
assert_code 'status api down' 3 status

new_run
assert_code 'health down' 2 service health
test ! -s "$RUN/out" || fail "health down stdout: $(cat "$RUN/out")"
grep -qx '未运行' "$RUN/err" || fail "health down: $(cat "$RUN/err")"


new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
python3 -c 'import json,sys; json.dump({"proxies":{"PROXY":{"type":"Selector"},"leaf":{"type":"Shadowsocks"}}}, open(sys.argv[1],"w",encoding="utf-8"))' "$RUN/fake/proxies.json"
printf '%s\n' 'DOMAIN kept.example DIRECT' >"$RUN/rules.list"
assert_code 'node is group' 3 rule add node leaf.example PROXY
grep -qx '不是节点' "$RUN/err" || fail "node group: $(cat "$RUN/err")"
test "$(cat "$RUN/rules.list")" = "DOMAIN kept.example DIRECT" || fail 'node group wrote'
assert_code 'node missing' 3 rule add node leaf.example gone
grep -qx '节点不存在' "$RUN/err" || fail "node missing: $(cat "$RUN/err")"
test "$(cat "$RUN/rules.list")" = "DOMAIN kept.example DIRECT" || fail 'node missing wrote'
cp "$FIX" "$RUN/subscription.yaml"
python3 "$TEST/support/prep.py" "$ROOT" "$RUN" 18080 "$AXS_API"
assert_code 'node add' 0 rule add n .leaf.example leaf
grep -q 'DOMAIN-SUFFIX leaf.example leaf' "$RUN/rules.list" || fail 'node rule missing'
