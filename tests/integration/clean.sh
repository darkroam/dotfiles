# shellcheck shell=sh
if [ -z "${PASS+x}" ]; then
    ROOT=$(cd "$(dirname "$0")/../.." && pwd)
    # shellcheck disable=SC1091
    . "$ROOT/tests/support/harness.sh"
    harness_init
fi

new_run
export AXS_MIXED_PORT=18080
open_mixed 18080
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
export AXS_FETCH="$ROOT/tests/fixtures/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'ensure busy' 2 service ensure
grep -q '端口已被占用' "$RUN/err" || fail 'ensure busy text'
test ! -f "$RUN/config.yaml" || fail 'ensure refreshed while the port was busy'
test ! -f "$RUN/mihomo.pid" || fail 'ensure launched while the port was busy'

new_run
assert_code 'ensure no url' 3 service ensure
grep -q '没有订阅' "$RUN/err" || fail 'ensure no url text'
test ! -f "$RUN/mihomo.pid" || fail 'ensure launched without a subscription'

new_run
export AXS_MIHOMO="$ROOT/tests/fixtures/fake-mihomo" AXS_MIXED_PORT=18084
printf '%s\n' 'placeholder: true' >"$RUN/config.yaml"
export AXS_FETCH="$ROOT/tests/fixtures/fake-fetch-fail" FIXTURE_SUB="$FIX"
assert_code 'ensure start only' 0 service ensure
test -f "$RUN/mihomo.pid" || fail 'ensure did not start'
cat "$RUN/mihomo.pid" >>"$PIDS"
test ! -s "$RUN/out" || fail 'ensure start printed'

new_run
export AXS_MIHOMO="$ROOT/tests/fixtures/fake-mihomo" AXS_MIXED_PORT=18085
export AXS_FETCH="$ROOT/tests/fixtures/fake-fetch" FIXTURE_SUB="$FIX"
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
chmod 600 "$RUN/subscription.url"
assert_code 'ensure refresh start' 0 service ensure
test -f "$RUN/config.yaml" || fail 'ensure did not refresh'
test -f "$RUN/mihomo.pid" || fail 'ensure did not start after refresh'
cat "$RUN/mihomo.pid" >>"$PIDS"
test ! -s "$RUN/out" || fail 'ensure refresh printed'

new_run
export AXS_FETCH="$ROOT/tests/fixtures/fake-fetch-fail" FIXTURE_SUB="$FIX"
printf '%s\n' "$CANARY" >"$RUN/subscription.url"
assert_code 'ensure fetch fail' 3 service ensure
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
export AXS_FETCH="$ROOT/tests/fixtures/fake-fetch" FIXTURE_SUB="$FIX"
assert_code 'ensure lock' 4 service ensure
grep -q '锁' "$RUN/err" || fail 'ensure lock text'
test ! -f "$RUN/mihomo.pid" || fail 'ensure started while locked'
assert_code 'ensure usage' 1 service ensure extra

new_run
assert_code 'net scheme' 1 network test 'ftp://127.0.0.1/' 'https://www.github.com'
test ! -s "$RUN/out" || fail 'bad scheme still tested'
assert_code 'net defaults forbid' 3 network test
test ! -s "$RUN/out" || fail 'forbid tested a default url'
assert_code 'net forbid partial' 3 network test 'http://127.0.0.1:9/' 'http://example.com/'
test ! -s "$RUN/out" || fail 'forbid tested the legal url'
assert_code 'net mixed down' 2 network test 'http://[::1]/'
grep -q '入站：不通' "$RUN/err" || fail 'net mixed text'
test ! -s "$RUN/out" || fail 'mixed down still tested'
printf '%s\n' '# skip' '' 'http://127.0.0.1:9/' >"$RUN/urls"
chmod 600 "$RUN/urls"
assert_code 'net urls file' 2 network test
printf '%s\n' '# only' >"$RUN/urls"
assert_code 'net urls empty' 3 network test
mark_up
export AXS_MIXED_PORT=18086
open_mixed 18086
assert_code 'net forbid no dial' 3 network test 'https://www.github.com'
test ! -s "$RUN/out" || fail 'forbid dialed'
test ! -e "$RUN/cache/net-test" || fail 'forbid wrote a net cache'

new_run
export AXS_MIXED_PORT=18086 AXS_NET_TIMEOUT_MS=200
open_mixed 18086
assert_code 'net cache fail' 3 network test 'http://127.0.0.1:9/'
test -f "$RUN/cache/net-test" || fail 'network test wrote no cache'
grep -q '^result=fail$' "$RUN/cache/net-test" || fail 'net cache result'
if grep -q '127.0.0.1' "$RUN/cache/net-test"; then
    fail 'net cache stored the url'
fi
test "$(stat -c '%a' "$RUN/cache")" = 700 || fail 'net cache dir mode'




new_run
mark_up
printf '%s\n' drop >"$RUN/config.yaml"
printf '%s\n' url >"$RUN/subscription.url"
assert_code 'clean while up' 2 clean --yes
grep -q 'axs service stop' "$RUN/err" || fail "clean up text: $(cat "$RUN/err")"
test -f "$RUN/config.yaml" || fail 'clean deleted while running'
assert_code 'clean up no yes' 2 clean
test -f "$RUN/config.yaml" || fail 'clean no-yes deleted while running'
assert_code 'subscription clean while up' 2 subscription clean --yes
test -f "$RUN/subscription.url" || fail 'subscription clean deleted while running'

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
assert_code 'subscription clean yes' 0 subscription clean --yes
grep -q '已删除' "$RUN/out" || fail 'subscription clean silent'
for name in subscription.url subscription.yaml userinfo fetch.yaml fetch.hdr; do
    test ! -e "$RUN/$name" || fail "subscription clean kept $name"
done
for name in config.yaml config.yaml.bak secret rules.list override.yaml mihomo.pid; do
    test -f "$RUN/$name" || fail "subscription clean dropped $name"
done
assert_code 'subscription clean again' 0 subscription clean --yes

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
assert_code 'subscription clean extra' 1 subscription clean --yes extra

ESC=$(printf '\033')
new_run
mark_up
export AXS_API="127.0.0.1:18081" COLUMNS=200
arm_api PROXY 204 0
python3 -c 'import json; json.dump({"proxies": {f"node-{i:02d}": {"type": "Shadowsocks"} for i in range(1, 11)} | {"主代理": {"all": ["node-01"], "now": "node-01", "type": "Selector"}}}, open("'"$RUN"'/fake/proxies.json", "w"))'
assert_code 'align mark' 0 node show --all
data=$(sed -n '3p' "$RUN/out")
printf '%s\n' "$data" | grep -q '^\[\*\] ' || fail "mark width: $data"
# units digit of 1 and of 10 sit in the same column of their cells
python3 -c 'import os; line=open(os.environ["AXS_RUN"]+"/out",encoding="utf-8").read().splitlines()[2]
assert line.startswith("[*]  N1 "), line
idx=line.index("    N10 node-10")
assert line[4:7]==" N1", line
assert line[idx+4:idx+7]=="N10", line
assert line[6]=="1" and line[idx+6]=="0", line'
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
assert_code 'color always' 0 node show --all
grep -F -q "${ESC}[32m" "$RUN/out" || fail "always green: $(cat "$RUN/out")"
grep -F -q "${ESC}[1m" "$RUN/out" || fail "always bold: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32m[*]" "$RUN/out" || fail "mark green: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32ma" "$RUN/out" || fail "selected name: $(cat "$RUN/out")"
grep -F -q "${ESC}[90mN1" "$RUN/out" || fail "number gray: $(cat "$RUN/out")"
assert_code 'groups tone' 0 group show
grep -F -q "${ESC}[36m主代理" "$RUN/out" || fail "group cyan: $(cat "$RUN/out")"
grep -F -q "${ESC}[90mSelector" "$RUN/out" || fail "type gray: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32ma" "$RUN/out" || fail "now green: $(cat "$RUN/out")"
grep -F -q "→ ${ESC}[1;32ma" "$RUN/out" || fail "now arrow: $(cat "$RUN/out")"
export AXS_COLOR=never
assert_code 'color never' 0 node show --all
if grep -q "$ESC" "$RUN/out"; then
    fail 'never still colored'
fi

new_run
mark_up
export AXS_API="127.0.0.1:18081" AXS_COLOR=always
arm_api PROXY 204 0
printf '%s\n' '{"a": 50, "b": 150, "c": 300}' >"$RUN/fake/delay.json"
assert_code 'delay colors' 0 group test PROXY
grep -F -q "${ESC}[32m50${ESC}[0m" "$RUN/out" || fail "green delay: $(cat "$RUN/out")"
grep -F -q "${ESC}[33m150${ESC}[0m" "$RUN/out" || fail "yellow delay: $(cat "$RUN/out")"
grep -F -q "${ESC}[31m300${ESC}[0m" "$RUN/out" || fail "red delay: $(cat "$RUN/out")"
python3 -c 'import json,os; p=os.environ["AXS_RUN"]+"/cache/node-test"; text=open(p,encoding="utf-8").read();
line=[row for row in text.splitlines() if row.startswith("{")][0]
assert json.loads(line)=={"a":50,"b":150,"c":300}, text'
printf '%s\n' '{"PROXY": "timeout", "a": 12}' >"$RUN/fake/delay.json"
assert_code 'delay timeout' 0 group test PROXY
grep -F -q "${ESC}[36mPROXY" "$RUN/out" || fail "group name: $(cat "$RUN/out")"
grep -F -q "${ESC}[31m超时" "$RUN/out" || fail "timeout red: $(cat "$RUN/out")"
grep -F -q "${ESC}[32m12" "$RUN/out" || fail "node delay: $(cat "$RUN/out")"
export AXS_COLOR=never
assert_code 'delay plain' 0 group test PROXY
if grep -q "$ESC" "$RUN/out"; then
    fail 'delay never colored'
fi

new_run
export AXS_SYSTEMD=1 AXS_SYSTEMCTL="$ROOT/tests/fixtures/fake-systemctl" AXS_COLOR=always
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
grep -q '自启    enabled（刷新：' "$RUN/out" || fail "status enabled: $(cat "$RUN/out")"
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
assert_code 'service usage' 1 service nope
export AXS_COLOR=always
assert_code 'bare help color' 1
test "$(grep -c . "$RUN/err")" -eq 8 || fail "bare lines: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36msta${ESC}[0m" "$RUN/err" || fail "start alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36msto${ESC}[0m" "$RUN/err" || fail "stop alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36msu${ESC}[0m" "$RUN/err" || fail "sub alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36mse${ESC}[0m" "$RUN/err" || fail "service alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1mnetwork${ESC}[0m" "$RUN/err" || fail "network plain bold: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36mre${ESC}[0m" "$RUN/err" || fail "restart alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36ms${ESC}[0m" "$RUN/err" || fail "status letter: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36msw${ESC}[0m" "$RUN/err" || fail "switch alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36ma${ESC}[0m" "$RUN/err" || fail "add alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36mg${ESC}[0m${ESC}[1mroup${ESC}[0m" "$RUN/err" || fail "group alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36msw${ESC}[0m${ESC}[1mitch${ESC}[0m" "$RUN/err" || fail "switch word: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36men${ESC}[0m${ESC}[1mable${ESC}[0m" "$RUN/err" || fail "enable alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36mr${ESC}[0m${ESC}[1mefresh${ESC}[0m" "$RUN/err" || fail "refresh alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36msy${ESC}[0m" "$RUN/err" || fail "system alias: $(cat "$RUN/err")"
grep -F -q "${ESC}[1;36mse${ESC}[0m${ESC}[1mssion${ESC}[0m" "$RUN/err" || fail "session alias: $(cat "$RUN/err")"
if ! grep -q "$ESC" "$RUN/err"; then
    fail "bare help not colored"
fi
test ! -s "$RUN/out" || fail "bare stdout: $(cat "$RUN/out")"
assert_code 'unknown help' 1 nope
test "$(grep -c . "$RUN/err")" -eq 8 || fail "unknown lines: $(cat "$RUN/err")"
assert_code 'help stdout' 0 help
grep -q '节点' "$RUN/out" || fail "help out: $(cat "$RUN/out")"
grep -q '示例：axs s' "$RUN/out" || fail "help example: $(cat "$RUN/out")"
if grep -q '颜色只是增强' "$RUN/out"; then fail 'help still explains color'; fi
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
assert all(len(line)>=34 and line[24:26]=="  " and (line[26]!=" " or (line[26:34]=="        " and line[34]!=" ")) for line in rows), rows'
assert_code 'help flag' 0 --help
grep -q '清理' "$RUN/out" || fail "flag out: $(cat "$RUN/out")"
assert_code 'help short flag' 0 -h
grep -q 'axs n s' "$RUN/out" || fail "short flag: $(cat "$RUN/out")"
assert_code 'help flag extra' 1 -h extra
test "$(grep -c . "$RUN/err")" -eq 8 || fail "flag extra: $(cat "$RUN/err")"
export AXS_COLOR=never
assert_code 'bare help plain' 1
grep -F -q '用法：axs status|clean|help' "$RUN/err" || fail "bare plain: $(cat "$RUN/err")"
grep -q 'axs network test' "$RUN/err" || fail "bare last: $(cat "$RUN/err")"
grep -q 'session enable|disable|status' "$RUN/err" || fail "usage session: $(cat "$RUN/err")"
if grep -q 'session on|off' "$RUN/err"; then
    fail 'usage still lists session on'
fi
if grep -q 'health' "$RUN/err"; then
    fail 'help lists health'
fi
if grep -q "$ESC" "$RUN/err"; then
    fail "bare help colored: $(cat "$RUN/err")"
fi
assert_code 'help never' 0 help
if grep -q "$ESC" "$RUN/out"; then
    fail 'help never colored'
fi
if grep -q '颜色只是增强' "$RUN/out"; then fail 'help note plain'; fi
grep -q 'axs rule add direct' "$RUN/out" || fail "direct row: $(cat "$RUN/out")"
if grep -q 'direct             a' "$RUN/out"; then
    fail 'direct still shows alias a'
fi

