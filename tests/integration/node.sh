# shellcheck shell=sh
if [ -z "${PASS+x}" ]; then
    ROOT=$(cd "$(dirname "$0")/../.." && pwd)
    # shellcheck disable=SC1091
    . "$ROOT/tests/support/harness.sh"
    harness_init
fi

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
python3 "$ROOT/tests/support/prep.py" "$ROOT" "$RUN" "" "$AXS_API"
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
test "$(cat "$RUN/out")" = "1  PROXY  Selector  → a" || fail "groups columns: $(cat "$RUN/out")"

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
export AXS_FETCH="$ROOT/tests/fixtures/fake-fetch" FIXTURE_SUB="$FIX"
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
export AXS_FETCH="$ROOT/tests/fixtures/fake-fetch" FIXTURE_SUB="$FIX"
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
assert_code 'node flat' 0 node list --flat
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
    '1  AUTO   URLTest   → b' \
    '2  PROXY  Selector  → a' \
    '3  RELAY  Relay     -')
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
: >"$RUN/fake/log"
assert_code 'switch group number' 0 node switch 1 b
grep -q 'PUT /proxies/OTHER' "$RUN/fake/log" || fail "group number path: $(cat "$RUN/fake/log")"
grep -q '{"name": "b"}' "$RUN/fake/log" || fail "group number body: $(cat "$RUN/fake/log")"
test "$(cat "$RUN/out")" = "$(printf 'OTHER\tb\t-')" || fail "group number out: $(cat "$RUN/out")"
: >"$RUN/fake/log"
assert_code 'switch group name wins' 3 node switch 2 a
grep -qx '不是策略组' "$RUN/err" || fail "group name wins: $(cat "$RUN/err")"
if grep -q 'PUT /proxies' "$RUN/fake/log"; then
    fail 'node named 2 sent select'
fi
: >"$RUN/fake/log"
assert_code 'test group number' 0 node test 1
grep -q '/group/OTHER/delay' "$RUN/fake/log" || fail "group number delay: $(cat "$RUN/fake/log")"
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
grep -qx '控制器失败' "$RUN/err" || fail "delay reason: $(cat "$RUN/err")"

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
export AXS_FETCH="$ROOT/tests/fixtures/fake-fetch-fail" FIXTURE_SUB="$FIX"
printf '%s\n' 'placeholder: true' >"$RUN/config.yaml"
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
pid=$(cat "$RUN/mihomo.pid")
assert_code 'ensure already' 0 ensure
test "$(cat "$RUN/mihomo.pid")" = "$pid" || fail 'ensure restarted a running service'
test ! -s "$RUN/out" || fail 'ensure printed on success'

