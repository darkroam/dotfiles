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
    # shellcheck disable=SC2034 # harness reads ROOT
    ROOT=$repo/.local/lib/access
    # shellcheck disable=SC1091
    . "$TEST/support/harness.sh"
    harness_init
fi

new_run
assert_code 'alias status' 2 s
grep -q '未运行（手动）' "$RUN/out" || fail "alias status: $(cat "$RUN/out")"
assert_code 'alias health' 2 service he
grep -q '未运行' "$RUN/err" || fail "alias health: $(cat "$RUN/err")"
if grep -q '状态' "$RUN/out"; then
    fail 'health alias printed status'
fi
assert_code 'alias stop' 0 service sto
assert_code 'alias start' 3 service sta
grep -q '没有配置' "$RUN/err" || fail "alias start: $(cat "$RUN/err")"
assert_code 'alias ensure' 3 service e
grep -q '没有订阅' "$RUN/err" || fail "alias ensure: $(cat "$RUN/err")"
assert_code 'alias clean' 1 c
grep -q '需要 --yes' "$RUN/err" || fail "alias clean: $(cat "$RUN/err")"
assert_code 'alias help' 0 h
grep -q '别名' "$RUN/out" || fail "alias column: $(cat "$RUN/out")"
assert_code 'alias help question' 0 '?'
grep -q '别名' "$RUN/out" || fail "question help: $(cat "$RUN/out")"
python3 -c 'import os,re,sys
esc=re.compile("\033\\[[0-9;]*m")
rows=[esc.sub("", line) for line in open(os.environ["AXS_RUN"]+"/out",encoding="utf-8") if esc.sub("", line).startswith("axs ")]
want={
 "axs status":"s",
 "axs service status":"s",
 "axs service start":"sta",
 "axs service stop":"sto",
 "axs service restart":"re",
 "axs service ensure":"e",
 "axs service enable":"en",
 "axs service disable":"di",
 "axs subscription status":"s",
 "axs subscription refresh":"r",
 "axs subscription clean":"c",
 "axs rule status":"s",
 "axs rule show":"sh",
 "axs rule add via":"v",
 "axs rule add direct":"d",
 "axs rule add node":"n",
 "axs rule del":"d",
 "axs node status":"s",
 "axs node show":"sh",
 "axs group status":"s",
 "axs group members":"m",
 "axs group switch":"sw",
 "axs group test":"t",
 "axs network test":"t",
 "axs network ip":"i",
 "axs proxy user":"u",
 "axs proxy system":"sy",
 "axs proxy session":"se",
 "axs clean":"c",
}
got={}
for line in rows:
    if len(line)<32 or line[24:26]!="  ":
        sys.stderr.write(line+"\n")
        raise SystemExit(1)
    name=line[:24].rstrip()
    alias=line[26:32].rstrip()
    got[name]=alias
missing=[k for k,v in want.items() if got.get(k)!=v]
if missing:
    sys.stderr.write(str(missing)+"\n"+str(got))
    raise SystemExit(1)
'
assert_code 'alias group status' 2 g s
grep -q '服务：未运行' "$RUN/err" || fail "alias groups: $(cat "$RUN/err")"
assert_code 'alias node show' 2 n s
grep -q '服务：未运行' "$RUN/err" || fail "alias list: $(cat "$RUN/err")"
assert_code 'alias group test' 1 g t
grep -q '用法：axs group test <名称|G#>|--all' "$RUN/err" || fail "alias group test: $(cat "$RUN/err")"
assert_code 'alias group switch' 1 g sw
test "$(grep -c . "$RUN/err")" -eq 1 || fail "alias switch: $(cat "$RUN/err")"
grep -q '用法' "$RUN/err" || fail "alias switch usage: $(cat "$RUN/err")"
assert_code 'alias node bare' 0 n
grep -q 'axs node status' "$RUN/out" || fail "bare node: $(cat "$RUN/out")"
assert_code 'prefix node show' 2 node sh
grep -q '服务：未运行' "$RUN/err" || fail "prefix list: $(cat "$RUN/err")"
set +e
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
    "$AXS" p u status >"$RUN/out" 2>"$RUN/err"
code=$?
set -e
test "$code" -eq 1 || fail "alias proxy user want 1 got $code" "$(cat "$RUN/out")"
grep -q 'user:' "$RUN/out" || fail "alias proxy user: $(cat "$RUN/out")"
PASS=$((PASS + 1))
assert_code 'alias proxy status' 0 p s
grep -q '^user' "$RUN/out" || fail "proxy status: $(cat "$RUN/out")"
assert_code 'alias proxy system' 0 p sy enable
grep -q 'system：' "$RUN/out" || fail "alias proxy system: $(cat "$RUN/out")"
grep -q 'enabled' "$RUN/out" || fail "alias proxy system enabled: $(cat "$RUN/out")"
assert_code 'prefix proxy system' 0 p sy disable
grep -q 'disabled' "$RUN/out" || fail "prefix proxy system: $(cat "$RUN/out")"
assert_code 'alias proxy session' 1 p se status
grep -q 'session: persist' "$RUN/out" || fail "alias proxy session: $(cat "$RUN/out")"
now=$(date +%s)
printf 'upload=1\nexpire=%s\n' "$((now + 40 * 86400))" >"$RUN/userinfo"
assert_code 'alias subscription status' 0 su s
grep -q '上传' "$RUN/out" || fail "alias subscription status: $(cat "$RUN/out")"
assert_code 'alias subscription refresh' 3 su r
grep -q '没有订阅' "$RUN/err" || fail "alias subscription refresh: $(cat "$RUN/err")"
assert_code 'alias subscription clean' 1 su c
grep -q '需要 --yes' "$RUN/err" || fail "alias subscription clean: $(cat "$RUN/err")"
assert_code 'alias rule show' 2 r s
grep -q '服务：未运行' "$RUN/err" || fail "alias rule show: $(cat "$RUN/err")"
assert_code 'alias rule add' 1 r a
test "$(grep -c . "$RUN/err")" -eq 1 || fail "alias rule add: $(cat "$RUN/err")"
assert_code 'alias rule del' 3 r d example.com
grep -q '规则不存在' "$RUN/err" || fail "alias rule del: $(cat "$RUN/err")"
assert_code 'alias network test' 3 network t
grep -q '禁止外网' "$RUN/err" || fail "alias network test: $(cat "$RUN/err")"
assert_code 'prefix network ip' 2 ne i
grep -q '入站：不通' "$RUN/err" || fail "prefix network ip: $(cat "$RUN/err")"
assert_code 'alias service enable' 3 service en
grep -q '没有 systemd' "$RUN/err" || fail "alias service enable: $(cat "$RUN/err")"
assert_code 'alias service disable' 3 se di
grep -q '没有 systemd' "$RUN/err" || fail "prefix service disable: $(cat "$RUN/err")"
assert_code 'prefix status' 2 stat
grep -q '未运行（手动）' "$RUN/out" || fail "prefix status: $(cat "$RUN/out")"
mark_up
assert_code 'prefix restart' 3 service re
grep -q '没有配置' "$RUN/err" || fail "prefix restart: $(cat "$RUN/err")"
test ! -f "$RUN/mihomo.pid" || fail "prefix restart left the process up"
assert_code 'prefix ambiguous' 1 service st
grep -q '候选：status start stop' "$RUN/err" || fail "ambiguous: $(cat "$RUN/err")"
test "$(grep -c . "$RUN/err")" -eq 1 || fail "ambiguous lines: $(cat "$RUN/err")"
assert_code 'alias sta' 3 service sta
grep -q '没有配置' "$RUN/err" || fail "sta: $(cat "$RUN/err")"
assert_code 'alias he' 2 service he
grep -q '未运行' "$RUN/err" || fail "he: $(cat "$RUN/err")"
assert_code 'retired x' 1 x
test "$(grep -c . "$RUN/err")" -eq 8 || fail "retired x: $(cat "$RUN/err")"
assert_code 'retired o' 1 o
assert_code 'hidden health' 2 health
grep -qx '未运行' "$RUN/err" || fail "hidden health: $(cat "$RUN/err")"
assert_code 'hidden k' 2 k
grep -qx '未运行' "$RUN/err" || fail "hidden k: $(cat "$RUN/err")"
assert_code 'retired u' 1 u
assert_code 'alias unknown' 1 zz
test "$(grep -c . "$RUN/err")" -eq 8 || fail "unknown lines: $(cat "$RUN/err")"
if grep -q '候选：' "$RUN/err"; then
    fail "unknown listed candidates: $(cat "$RUN/err")"
fi

export AXS_COLOR=always
now=$(date +%s)
printf 'upload=1\nexpire=%s\n' "$((now + 40 * 86400))" >"$RUN/userinfo"
assert_code 'sub color' 0 subscription status
grep -q '剩余' "$RUN/out" || fail "sub line: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32m" "$RUN/out" || fail "sub days: $(cat "$RUN/out")"
grep -q '1.0B' "$RUN/out" || fail "sub bytes: $(cat "$RUN/out")"
export AXS_COLOR=never
assert_code 'sub plain' 0 subscription status
if grep -q "$ESC" "$RUN/out"; then
    fail 'sub never colored'
fi

new_run
mark_up
prepare_health 18084
python3 -c 'import json,os; json.dump({"proxies":{"主代理":{"all":["自动选择"],"now":"自动选择","type":"Selector"},"自动选择":{"all":["a"],"now":"a","type":"URLTest"},"GLOBAL":{"all":["DIRECT"],"now":"DIRECT","type":"Selector"},"a":{"type":"Shadowsocks"},"DIRECT":{"type":"Direct"}}}, open(os.environ["AXS_RUN"]+"/fake/proxies.json","w"))'
printf '%s\n' 'rules:' '  - MATCH,主代理' >"$RUN/config.yaml"
now=$(date +%s)
printf 'upload=1536\nexpire=%s\n' "$((now - 10))" >"$RUN/userinfo"
mkdir -p "$RUN/cache"
printf 'ts=%s\nresult=ok\n' "$((now - 180))" >"$RUN/cache/net-test"
export AXS_COLOR=always
assert_code 'status tone' 5 status
grep -F -q "${ESC}[1m服务" "$RUN/out" || fail "status label: $(cat "$RUN/out")"
grep -F -q "${ESC}[90m状态" "$RUN/out" || fail "status row label: $(cat "$RUN/out")"
grep -F -q "${ESC}[1;32m运行中" "$RUN/out" || fail "status up: $(cat "$RUN/out")"
grep -F -q "${ESC}[32m监听" "$RUN/out" || fail "status port: $(cat "$RUN/out")"
python3 -c 'import os,re,sys
esc=re.compile("\x1b\\[[0-9;]*m")
text=esc.sub("", open(os.environ["AXS_RUN"]+"/out",encoding="utf-8").read())
chain="G2 主代理 [Selector] · 规则 1（MATCH 1） → G3 自动选择 [URLTest] → N2 a"
if chain not in text or "路径" in text or "GLOBAL  " in text or "[*]" in text:
    sys.stderr.write(text)
    raise SystemExit(1)
if "上传 1.5K" not in text or "剩余 已过期" not in text:
    raise SystemExit(2)
want=["服务","订阅","路由","测速","代理"]
got=[line for line in text.splitlines() if line in want]
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
grep -F -q 'G2 主代理 [Selector] · 规则 1（MATCH 1） → G3 自动选择 [URLTest] → N2 a' "$RUN/out" || fail "plain chain: $(cat "$RUN/out")"
grep -q '上传 1.5K' "$RUN/out" || fail "plain bytes: $(cat "$RUN/out")"


new_run
printf '%s\n' drop >"$RUN/config.yaml"
export AXS_COLOR=always
assert_code 'clean tone' 0 clean --yes
grep -F -q "${ESC}[32m已删除" "$RUN/out" || fail "clean green: $(cat "$RUN/out")"

# ---- proxy 三层 ----
new_run
assert_code 'proxy user on' 0 proxy user on
grep -q 'eval' "$RUN/err" || fail "proxy user on hint: $(cat "$RUN/err")"
grep -qx 'export http_proxy=http://127.0.0.1:7897' "$RUN/out" || fail 'proxy user on export'
grep -qx 'export all_proxy=socks5://127.0.0.1:7897' "$RUN/out" || fail 'proxy user on all_proxy'
grep -qx 'export NO_PROXY=localhost,127.0.0.1,::1' "$RUN/out" || fail 'proxy user on NO_PROXY'
assert_code 'proxy user off' 0 proxy user off
grep -q '^unset http_proxy' "$RUN/out" || fail 'proxy user off unset'
assert_code 'proxy user bogus' 1 proxy user bogus
if ! grep -F -q 'axs proxy user' "$RUN/err" || ! grep -F -q 'on|off|status' "$RUN/err"; then fail "proxy user bogus: $(cat "$RUN/err")"; fi

new_run
assert_code 'network ip down' 2 network ip
open_mixed 7897
assert_code 'network ip forbid' 3 network ip
[ ! -s "$RUN/out" ] || fail "network ip forbid stdout: $(cat "$RUN/out")"
grep -q '公网地址查询被禁止（AXS_FORBID_NET=1）' "$RUN/err" || fail "network ip forbid stderr"
proxy_status_on || fail 'proxy user status on'
grep -q 'user: on' "$RUN/out" || fail "user status on: $(cat "$RUN/out")"
if proxy_status_off; then fail 'proxy user status off code'; fi
grep -q 'user: off' "$RUN/out" || fail "user status off: $(cat "$RUN/out")"
proxy_eval || fail 'proxy user eval'

new_run
mkdir -p "$RUN/fakebin"
ln -s "$TEST/fixtures/fake-gsettings" "$RUN/fakebin/gsettings"
export AXS_GS_DB="$RUN/fake/gs"
old_path=$PATH
PATH="$RUN/fakebin:$PATH"
assert_code 'proxy system on' 0 proxy system on
if [ -e "$RUN/proxy-system.flag" ]; then
    fail 'on created flag'
fi
assert_code 'proxy system status on' 0 proxy system status
grep -q 'persist: disabled' "$RUN/out" || fail "runtime on persist: $(cat "$RUN/out")"
assert_code 'proxy system off' 0 proxy system off
assert_code 'proxy system status off' 1 proxy system status
assert_code 'proxy system enable' 0 proxy system enable
test "$(stat -c '%a' "$RUN/proxy-system.flag")" = 600 || fail 'enable mode'
assert_code 'proxy system disable' 0 proxy system disable
if [ -e "$RUN/proxy-system.flag" ]; then
    fail 'disable left flag'
fi
assert_code 'proxy system bogus' 1 proxy system bogus
if ! grep -F -q 'axs proxy system' "$RUN/err" || ! grep -F -q 'on|off|enable|disable|status' "$RUN/err"; then fail "proxy system bogus: $(cat "$RUN/err")"; fi
PATH=$old_path
export PATH

new_run
mkdir -p "$RUN/fakebin"
ln -s "$TEST/fixtures/fake-gsettings" "$RUN/fakebin/gsettings"
export AXS_GS_DB="$RUN/fake/gs" AXS_XPROFILE="$RUN/xprofile"
printf 'test\n' >"$AXS_XPROFILE"
unset XDG_CURRENT_DESKTOP || true
old_path=$PATH
PATH="$RUN/fakebin:$PATH"
: >"$RUN/gsettings-identity"
assert_code 'proxy system enable migrate' 0 proxy system enable
test "$(stat -c '%a' "$RUN/proxy-system.flag")" = 600 || fail 'identity mode'
if [ -e "$RUN/gsettings-identity" ]; then
    fail 'old system flag remains'
fi
grep -q '重登 X 后 libproxy/Edge 才会读取 gsettings' "$RUN/out" || fail 'system enable relogin hint'
assert_code 'proxy system on keeps flag' 0 proxy system on
env -i /bin/sleep 30 &
echo $! >>"$PIDS"
export AXS_SESSION_PID=$!
assert_code 'proxy system status empty' 0 proxy system status
grep -q 'mode=manual' "$RUN/out" || fail "status mode: $(cat "$RUN/out")"
grep -q 'xprofile hook missing' "$RUN/out" || fail "status unhooked: $(cat "$RUN/out")"
grep -q 'desktop: pending' "$RUN/out" || fail "status empty desk: $(cat "$RUN/out")"
env -i XDG_CURRENT_DESKTOP=GNOME /bin/sleep 30 &
echo $! >>"$PIDS"
export AXS_SESSION_PID=$!
printf '%s\n' '# axs proxy system identity (managed)' >>"$AXS_XPROFILE"
assert_code 'proxy system status gnome' 0 proxy system status
grep -q 'desktop: effective' "$RUN/out" || fail "status gnome: $(cat "$RUN/out")"
grep -q 'persist: enabled' "$RUN/out" || fail "status hooked: $(cat "$RUN/out")"
if grep -q 'desktop: pending' "$RUN/out"; then
    fail 'status gnome still cold'
fi
env -i XDG_CURRENT_DESKTOP=dwm:GNOME /bin/sleep 30 &
echo $! >>"$PIDS"
export AXS_SESSION_PID=$!
assert_code 'proxy system status gnome list' 0 proxy system status
grep -q 'desktop: effective' "$RUN/out" || fail "status gnome list: $(cat "$RUN/out")"
export AXS_SESSION_PID=2147483001
assert_code 'proxy system status no session' 0 proxy system status
grep -q 'desktop: no x session' "$RUN/out" || fail "system no session: $(cat "$RUN/out")"
assert_code 'proxy system off keeps flag' 0 proxy system off
if [ ! -f "$RUN/proxy-system.flag" ]; then
    fail 'off removed flag'
fi
assert_code 'proxy system status still enabled' 1 proxy system status
grep -q 'persist: enabled' "$RUN/out" || fail "off kept persist: $(cat "$RUN/out")"
assert_code 'proxy system disable' 0 proxy system disable
if [ -e "$RUN/proxy-system.flag" ]; then
    fail 'identity file remains'
fi
assert_code 'proxy system status identity off' 1 proxy system status
grep -q 'persist: disabled' "$RUN/out" || fail "status identity off: $(cat "$RUN/out")"
PATH=$old_path
export PATH
unset AXS_XPROFILE AXS_GS_DB XDG_CURRENT_DESKTOP || true

new_run
export AXS_XPROFILE="$RUN/xprofile"
printf 'test\n' >"$AXS_XPROFILE"
assert_code 'proxy session on removed' 1 proxy session on
assert_code 'proxy session off removed' 1 proxy session off
: >"$RUN/session-proxy"
assert_code 'proxy session enable' 0 proxy session enable
test "$(stat -c '%a' "$RUN/proxy-session.flag")" = 600 || fail 'session flag mode'
if [ -e "$RUN/session-proxy" ]; then
    fail 'old session flag remains'
fi
assert_code 'proxy session status unhooked' 1 proxy session status
grep -q 'xprofile hook missing' "$RUN/out" || fail "session unhooked: $(cat "$RUN/out")"
printf '# axs proxy session (managed)\n' >>"$AXS_XPROFILE"
export AXS_SESSION_PID=2147483001
assert_code 'proxy session status no-dwm' 1 proxy session status
grep -q 'effect no-x-session' "$RUN/out" || fail "session no dwm: $(cat "$RUN/out")"
"$AXS" status >"$RUN/status" 2>"$RUN/err" || true
grep -q 'session   persist enabled · effect no-x-session' "$RUN/status" || fail "summary no-x: $(cat "$RUN/status")"
env -i /bin/sleep 30 &
echo $! >>"$PIDS"
export AXS_SESSION_PID=$!
assert_code 'proxy session status cold' 1 proxy session status
grep -q 'effect pending' "$RUN/out" || fail "session cold: $(cat "$RUN/out")"
env -i http_proxy=http://127.0.0.1:7897 /bin/sleep 30 &
echo $! >>"$PIDS"
export AXS_SESSION_PID=$!
assert_code 'proxy session status live' 0 proxy session status
grep -q 'effect active' "$RUN/out" || fail "session live: $(cat "$RUN/out")"
if grep -q 'pending' "$RUN/out"; then
    fail 'session live still cold'
fi
"$AXS" status >"$RUN/out" 2>"$RUN/err" || true
grep -q 'session   persist enabled · effect active' "$RUN/out" || fail "status line live: $(cat "$RUN/out")"
assert_code 'proxy session disable' 0 proxy session disable
assert_code 'proxy session status off' 1 proxy session status
grep -q 'effect -' "$RUN/out" || fail "session disabled: $(cat "$RUN/out")"
unset AXS_SESSION_PID || true
assert_code 'proxy session bogus' 1 proxy session bogus
if ! grep -F -q 'axs proxy session' "$RUN/err" || ! grep -F -q 'enable|disable|status' "$RUN/err"; then fail "proxy session bogus: $(cat "$RUN/err")"; fi

printf '%s\n' drop >"$RUN/config.yaml"
export AXS_COLOR=never
assert_code 'clean tone plain' 0 clean --yes
if grep -q "$ESC" "$RUN/out"; then
    fail 'clean never colored'
fi
grep -q '已删除' "$RUN/out" || fail 'clean plain text'

