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
mark_up
export AXS_MIXED_PORT=18080
assert_code 'health port' 2 service health
test ! -s "$RUN/out" || fail "health port stdout: $(cat "$RUN/out")"
grep -qx '端口不通' "$RUN/err" || fail "health port: $(cat "$RUN/err")"

new_run
mark_up
prepare_health 18083
: >"$RUN/fake/down"
assert_code 'health api' 3 service health
test ! -s "$RUN/out" || fail "health api stdout: $(cat "$RUN/out")"
grep -qx '控制器不通' "$RUN/err" || fail "health api: $(cat "$RUN/err")"

new_run
mark_up
prepare_health 18080
now=$(date +%s)
printf '%s\n' "expire=$((now - 10))" >"$RUN/userinfo"
assert_code 'health expired' 5 service health
test ! -s "$RUN/out" || fail "health expired stdout: $(cat "$RUN/out")"
grep -qx '订阅过期' "$RUN/err" || fail "health expired: $(cat "$RUN/err")"

new_run
mark_up
prepare_health 18082
now=$(date +%s)
printf '%s\n' "expire=$((now + 40 * 86400))" >"$RUN/userinfo"
assert_code 'health ok' 0 service health
test ! -s "$RUN/out" || fail "health ok stdout: $(cat "$RUN/out")"
test ! -s "$RUN/err" || fail "health ok stderr: $(cat "$RUN/err")"
test ! -e "$RUN/cache" || fail 'health wrote a cache'

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
python3 "$TEST/support/prep.py" "$ROOT" "$RUN" "" "$AXS_API"
assert_code 'group test' 0 group test PROXY
grep -q ' 0' "$RUN/out" || fail "delay output: $(cat "$RUN/out")"
test "$(stat -c '%a' "$RUN/cache")" = 700 || fail 'cache dir mode'
test -f "$RUN/cache/node-test" || fail 'group test wrote no cache'
grep -q '^result=ok$' "$RUN/cache/node-test" || fail 'node cache result'
if grep -q 'PROXY' "$RUN/cache/node-test"; then
    fail 'node cache stored the group'
fi
test "$(stat -c '%a' "$RUN/cache/node-test")" = 600 || fail 'node cache mode'
grep -q 'auth=yes' "$RUN/fake/log" || fail 'api was not authenticated'
if grep -F 'test-secret-value' "$RUN/fake/log" "$RUN/out" "$RUN/err" >/dev/null 2>&1; then
    fail 'secret reached the log or output'
fi
assert_code 'groups' 0 group status
test "$(cat "$RUN/out")" = "G1  PROXY  Selector  → a" || fail "groups columns: $(cat "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081" AXS_DELAY_URL="http://127.0.0.1:9/204"
arm_api PROXY 204 7
assert_code 'delay url' 0 group test PROXY
grep -q ' 7' "$RUN/out" || fail "delay url output: $(cat "$RUN/out")"
grep -q '127.0.0.1' "$RUN/fake/log" || fail 'delay url was not sent'

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
printf '%s\n' '{"a": 12, "b": 5, "PROXY": 9}' >"$RUN/fake/delay.json"
assert_code 'node cache delays' 0 group test PROXY
python3 -c 'import json,os; p=os.environ["AXS_RUN"]+"/cache/node-test"; text=open(p,encoding="utf-8").read();
assert "PROXY" not in text, text
line=[row for row in text.splitlines() if row.startswith("{")][0]
data=json.loads(line)
assert data=={"a":12,"b":5}, data'
grep -q '^ts=' "$RUN/cache/node-test" || fail 'delay cache ts'
grep -q '^result=ok$' "$RUN/cache/node-test" || fail 'delay cache result'

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$TEST/fixtures/fake-fetch" FIXTURE_SUB="$FIX"
"$AXS" subscription refresh >/dev/null
perms=$(stat -c '%a %n' "$RUN" "$RUN/subscriptions.list" "$RUN/secret" "$RUN/config.yaml" "$RUN/override.yaml" "$RUN/userinfo")
test ! -e "$RUN/subscription.url" || fail 'refresh left legacy url'
printf '%s\n' "$perms" | grep -q '^700 ' || fail "run perms: $perms"
printf '%s\n' "$perms" | grep -q '^600 ' || fail "file perms: $perms"
test "$(stat -c '%a' "$RUN/secret")" = 600 || fail 'secret mode'
test "$(stat -c '%a' "$RUN/config.yaml")" = 600 || fail 'config mode'


new_run
assert_code 'start no config' 3 service start
grep -q '没有配置' "$RUN/err" || fail 'start no config text'
test ! -f "$RUN/mihomo.pid" || fail 'start no config launched'

new_run
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$TEST/fixtures/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'start ignores url' 3 service start
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
assert_code 'node flat' 0 node show --flat
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
assert_code 'groups columns' 0 group status
groups_want=$(printf '%s\n' \
    'G1  AUTO   URLTest   → b' \
    'G2  PROXY  Selector  → a' \
    'G3  RELAY  Relay     -')
test "$(cat "$RUN/out")" = "$groups_want" || fail "groups now: $(cat "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=40
arm_api PROXY 204 0
python3 -c 'import json; json.dump({"proxies": {f"node-{i:02d}": {"type": "Shadowsocks"} for i in range(1, 9)}}, open("'"$RUN"'/fake/proxies.json", "w"))'
assert_code 'list columns 40' 0 node show --all
test "$(sed -n '3p' "$RUN/out")" = '全部叶子端点（最近测速：-）：' || fail "no speed: $(sed -n '3p' "$RUN/out")"
if grep -F '当前：' "$RUN/out" >/dev/null || grep -F '当前出口' "$RUN/out" >/dev/null; then
    fail "current line: $(cat "$RUN/out")"
fi
want40='    N1 node-01 -      N2 node-02 -'
test "$(sed -n '4p' "$RUN/out")" = "$want40" || fail "cols 40: $(sed -n '4p' "$RUN/out")"
if grep -F '[*]' "$RUN/out" >/dev/null; then
    fail 'unselected list showed [*]'
fi
test ! -e "$RUN/cache" || fail 'compact list created cache'
COLUMNS=80
assert_code 'list columns 80' 0 node show --all
want80='    N1 node-01 -      N2 node-02 -      N3 node-03 -      N4 node-04 -'
test "$(sed -n '4p' "$RUN/out")" = "$want80" || fail "cols 80: $(sed -n '4p' "$RUN/out")"
COLUMNS=120
assert_code 'list columns 120' 0 node show --all
want120='    N1 node-01 -      N2 node-02 -      N3 node-03 -      N4 node-04 -      N5 node-05 -      N6 node-06 -'
test "$(sed -n '4p' "$RUN/out")" = "$want120" || fail "cols 120: $(sed -n '4p' "$RUN/out")"
test "$(sed -n '5p' "$RUN/out")" = '    N7 node-07 -      N8 node-08 -' || fail "cols 120 wrap: $(sed -n '5p' "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=80
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"主代理":{"all":["a","b"],"now":"a","type":"Selector"},"a":{"type":"Shadowsocks"},"b":{"type":"Shadowsocks"}}}
EOF
assert_code 'list manual' 0 node show --all
test "$(sed -n '3p' "$RUN/out")" = '全部叶子端点（最近测速：-）：' || fail "manual title: $(sed -n '3p' "$RUN/out")"
if grep -F '当前：' "$RUN/out" >/dev/null; then
    fail "manual current: $(cat "$RUN/out")"
fi
test "$(sed -n '4p' "$RUN/out")" = '[*] N1 a -      N2 b -' || fail "manual cells: $(sed -n '4p' "$RUN/out")"
python3 -c 'import json,os; p=os.environ["AXS_RUN"]+"/fake/proxies.json"; d=json.load(open(p)); d["proxies"]["主代理"].pop("now", None); json.dump(d, open(p,"w"))'
assert_code 'list none' 0 node show --all
if grep -F '当前：' "$RUN/out" >/dev/null; then
    fail "cleared head: $(cat "$RUN/out")"
fi
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
assert_code 'list auto' 0 node show --all
test "$(sed -n '4p' "$RUN/out")" = '    N1 a -  [*] N2 b -' || fail "auto cells: $(sed -n '4p' "$RUN/out")"
python3 -c 'import json,os; p=os.environ["AXS_RUN"]+"/fake/proxies.json"; d=json.load(open(p)); d["proxies"]["自动选择"]["type"]="Fallback"; d["proxies"]["自动选择"].pop("now", None); json.dump(d, open(p,"w"))'
assert_code 'list auto none' 0 node show --all
if grep -F '[*]' "$RUN/out" >/dev/null || grep -F '当前：' "$RUN/out" >/dev/null; then
    fail "auto none: $(cat "$RUN/out")"
fi
python3 -c 'import json,os; p=os.environ["AXS_RUN"]+"/fake/proxies.json"; d=json.load(open(p)); d["proxies"]["自动选择"]["type"]="LoadBalance"; d["proxies"]["自动选择"]["now"]="a"; json.dump(d, open(p,"w"))'
assert_code 'list balance' 0 node show --all
test "$(sed -n '4p' "$RUN/out")" = '[*] N1 a -      N2 b -' || fail "balance cells: $(sed -n '4p' "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=30
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"ab":{"type":"Shadowsocks"},"香港":{"type":"Shadowsocks"}}}
EOF
assert_code 'list width' 0 node show --all
test "$(sed -n '4p' "$RUN/out")" = '    N1 ab -        N2 香港 -' || fail "cjk width: $(sed -n '4p' "$RUN/out")"

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
assert_code 'list cache' 0 node show --all
test "$(sed -n '3p' "$RUN/out")" = '全部叶子端点（最近测速：3 分钟前）：' || fail "cache age: $(sed -n '3p' "$RUN/out")"
test "$(sed -n '4p' "$RUN/out")" = '[*] N1 a 42      N2 b  -' || fail "cache cells: $(sed -n '4p' "$RUN/out")"
assert_code 'switch cache' 0 group switch PROXY a
test "$(cat "$RUN/out")" = "$(printf 'PROXY\ta\t42')" || fail "switch delay: $(cat "$RUN/out")"

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"OTHER":{"all":["a","b"],"now":"a","type":"Selector"},"PROXY":{"all":["2","a","b"],"now":"a","type":"Selector"},"2":{"type":"Shadowsocks"},"a":{"type":"Shadowsocks"},"b":{"type":"Shadowsocks"}}}
EOF
: >"$RUN/fake/log"
assert_code 'switch digit name' 0 group switch PROXY 2
grep -q '{"name": "2"}' "$RUN/fake/log" || fail "digit name body: $(cat "$RUN/fake/log")"
: >"$RUN/fake/log"
assert_code 'switch number' 0 group switch OTHER N2
grep -q '{"name": "a"}' "$RUN/fake/log" || fail "number body: $(cat "$RUN/fake/log")"
: >"$RUN/fake/log"
assert_code 'switch number missing' 3 group switch OTHER N1
grep -q '节点不存在' "$RUN/err" || fail "number missing text: $(cat "$RUN/err")"
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'number outside group sent select'
fi
: >"$RUN/fake/log"
assert_code 'switch number range' 3 group switch PROXY N9
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'out of range sent select'
fi
: >"$RUN/fake/log"
assert_code 'switch group number' 0 group switch G1 b
assert_code 'switch group lower' 0 group switch g1 b
grep -q 'PUT /proxies/OTHER' "$RUN/fake/log" || fail "group number path: $(cat "$RUN/fake/log")"
grep -q '{"name": "b"}' "$RUN/fake/log" || fail "group number body: $(cat "$RUN/fake/log")"
test "$(cat "$RUN/out")" = "$(printf 'OTHER\tb\t-')" || fail "group number out: $(cat "$RUN/out")"
: >"$RUN/fake/log"
assert_code 'switch group name wins' 3 group switch 2 a
grep -qx '不是策略组' "$RUN/err" || fail "group name wins: $(cat "$RUN/err")"
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'node named 2 sent select'
fi
: >"$RUN/fake/log"
assert_code 'test group number' 0 group test G1
assert_code 'test group lower' 0 group test g1
grep -q '/group/OTHER/delay' "$RUN/fake/log" || fail "group number delay: $(cat "$RUN/fake/log")"
assert_code 'list bad flag' 1 node show --nope

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"GLOBAL":{"all":["DIRECT"],"now":"DIRECT","type":"Selector"},"主代理":{"all":["自动选择","a"],"now":"自动选择","type":"Selector"},"自动选择":{"all":["a","新加坡aw1"],"now":"新加坡aw1","type":"URLTest"},"DIRECT":{"type":"Direct"},"a":{"type":"Shadowsocks"},"新加坡aw1":{"type":"Shadowsocks"}}}
EOF
export COLUMNS=80
assert_code 'list leaf' 0 node show --all
if grep -F '当前：' "$RUN/out" >/dev/null || grep -F '当前出口' "$RUN/out" >/dev/null; then
    fail "leaf current: $(cat "$RUN/out")"
fi
grep -F '最近测速：' "$RUN/out" >/dev/null || fail "leaf title: $(cat "$RUN/out")"
grep -F '[*] N3 新加坡aw1' "$RUN/out" >/dev/null || fail "leaf star: $(cat "$RUN/out")"
: >"$RUN/fake/log"
assert_code 'group test bare' 1 group test
grep -q '用法：axs group test <名称|G#>|--all' "$RUN/err" || fail "bare text: $(cat "$RUN/err")"
if grep -q '/delay' "$RUN/fake/log"; then
    fail 'bare sent delay'
fi

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"GLOBAL":{"all":["DIRECT"],"now":"DIRECT","type":"Selector"},"PROXY":{"all":["a"],"now":"a","type":"Selector"},"自动选择":{"all":["a"],"now":"a","type":"URLTest"},"DIRECT":{"type":"Direct"},"a":{"type":"Shadowsocks"}}}
EOF
printf '%s\n' '{"a": 12}' >"$RUN/fake/delay.json"
: >"$RUN/fake/log"
assert_code 'group test all' 0 group test --all
python3 -c 'import os,urllib.parse; log=open(os.environ["AXS_RUN"]+"/fake/log",encoding="utf-8").read();
assert "/group/GLOBAL/delay" in log, log
assert "/group/PROXY/delay" in log, log
assert "/group/"+urllib.parse.quote("自动选择")+"/delay" in log, log
assert log.count("/group/")==3, log'
grep -F 'G1 GLOBAL [Selector]' "$RUN/out" >/dev/null || fail "all head: $(cat "$RUN/out")"
grep -F 'G2 PROXY [Selector]' "$RUN/out" >/dev/null || fail "all proxy: $(cat "$RUN/out")"
grep -F 'G3 自动选择 [URLTest]' "$RUN/out" >/dev/null || fail "all auto: $(cat "$RUN/out")"
if [ -s "$RUN/err" ]; then
    fail "all progress: $(cat "$RUN/err")"
fi

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
cat >"$RUN/fake/proxies.json" <<'EOF'
{"proxies":{"GLOBAL":{"all":["DIRECT"],"now":"DIRECT","type":"Selector"},"DIRECT":{"type":"Direct"}}}
EOF
: >"$RUN/fake/log"
assert_code 'group test digit' 1 group test 9
grep -q '用法：axs group test <名称|G#>|--all' "$RUN/err" || fail "digit text: $(cat "$RUN/err")"
if grep -q '/delay' "$RUN/fake/log"; then
    fail 'digit sent delay'
fi

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
: >"$RUN/fake/down"
assert_code 'delay one line' 3 group test PROXY
test "$(grep -c . "$RUN/err")" -eq 1 || fail "delay stderr: $(cat "$RUN/err")"
grep -qx '控制器失败' "$RUN/err" || fail "delay reason: $(cat "$RUN/err")"

new_run
assert_code 'list down' 2 node status

new_run
mark_up
export AXS_API="127.0.0.1:18081"
arm_api PROXY 204 0
: >"$RUN/fake/down"
assert_code 'list api down' 3 node status

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
assert_code 'switch' 0 group switch PROXY 'a b'
test "$(cat "$RUN/out")" = "$(printf 'PROXY\ta b\t-')" || fail "switch out: $(cat "$RUN/out")"
grep -q 'PUT /proxies/PROXY' "$RUN/fake/log" || fail 'select was not sent'
grep -q '{"name": "a b"}' "$RUN/fake/log" || fail "select body: $(cat "$RUN/fake/log")"
test "$(grep -c 'GET /proxies' "$RUN/fake/log")" -eq 1 || fail 'switch queried twice'
test "$(cat "$RUN/config.yaml")" = 'SENTINEL' || fail 'switch edited config'
test "$(cat "$RUN/rules.list")" = 'RULE' || fail 'switch edited rules'
test ! -f "$RUN/refresh.lock" || fail 'switch took the refresh lock'
: >"$RUN/fake/log"
assert_code 'switch urltest' 0 group switch AUTO b
grep -q 'PUT /proxies/AUTO' "$RUN/fake/log" || fail 'urltest select was not sent'
: >"$RUN/fake/log"
assert_code 'switch encode' 0 group switch 'A B' a
grep -q 'PUT /proxies/A%20B' "$RUN/fake/log" || fail "encoded path: $(cat "$RUN/fake/log")"
: >"$RUN/fake/log"
assert_code 'switch missing group' 3 group switch NOPE a
grep -q '组不存在' "$RUN/err" || fail "missing group text: $(cat "$RUN/err")"
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'missing group sent select'
fi
: >"$RUN/fake/log"
assert_code 'switch not group' 3 group switch a b
grep -q '不是策略组' "$RUN/err" || fail "not group text: $(cat "$RUN/err")"
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'non-group sent select'
fi
: >"$RUN/fake/log"
assert_code 'switch missing node' 3 group switch PROXY nope
grep -q '节点不存在' "$RUN/err" || fail "missing node text: $(cat "$RUN/err")"
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'missing node sent select'
fi
: >"$RUN/fake/log"
: >"$RUN/fake/down"
assert_code 'switch api down' 3 group switch PROXY a
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'api down sent select'
fi
rm -f "$RUN/fake/down"
printf '%s\n' '400' >"$RUN/fake/select"
: >"$RUN/fake/log"
assert_code 'switch reject' 3 group switch PROXY a
grep -q 'PUT /proxies/PROXY' "$RUN/fake/log" || fail 'reject did not send select'
test ! -s "$RUN/out" || fail 'reject printed a success line'

new_run
assert_code 'switch down' 2 group switch PROXY a
assert_code 'switch usage' 1 group switch onlyone

new_run
mark_up
export AXS_FETCH="$TEST/fixtures/fake-fetch-fail" FIXTURE_SUB="$FIX"
printf '%s\n' 'placeholder: true' >"$RUN/config.yaml"
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
pid=$(cat "$RUN/mihomo.pid")
assert_code 'ensure already' 0 service ensure
test "$(cat "$RUN/mihomo.pid")" = "$pid" || fail 'ensure restarted a running service'
test ! -s "$RUN/out" || fail 'ensure printed on success'

