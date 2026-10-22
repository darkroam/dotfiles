#!/bin/sh
# Lock, atomic install, and controller calls. ROOT is set by bin/axs.
# shortcut: AXS_FETCH / AXS_MIXED_PORT / AXS_API / AXS_DELAY_URL keep tests off the public net; leave them unset in production.
set -eu

: "${ROOT:?}"
PY=$ROOT/lib/merge.py
: "${AXS_RUN:=$ROOT/run}"
: "${AXS_MIHOMO:=$HOME/.local/bin/mihomo}"

# $(color) is a pipe, so [ -t 1 ] inside it is always false. Remember the real fds.
if [ -t 1 ]; then AXS_TTY_OUT=1; else AXS_TTY_OUT=0; fi
if [ -t 2 ]; then AXS_TTY_ERR=1; else AXS_TTY_ERR=0; fi
export AXS_TTY_OUT AXS_TTY_ERR

use_color() {
    case ${AXS_COLOR:-} in
        always) return 0 ;;
        never) return 1 ;;
    esac
    if [ -n "${NO_COLOR+x}" ]; then
        return 1
    fi
    if [ "${1:-1}" -eq 2 ]; then
        [ "$AXS_TTY_ERR" -eq 1 ]
    else
        [ "$AXS_TTY_OUT" -eq 1 ]
    fi
}

tone() {
    code=$1
    text=$2
    if use_color "${AXS_PAINT_FD:-1}"; then
        printf '\033[%sm%s\033[0m' "$code" "$text"
    else
        printf '%s' "$text"
    fi
}

label() { tone 90 "$1"; }
ident() { tone 36 "$1"; }
ok() { tone 32 "$1"; }
warn() { tone 33 "$1"; }
bad() { tone 31 "$1"; }
dim() { tone 90 "$1"; }
bold() { tone 1 "$1"; }
emph() { tone "1;$1" "$2"; }
paint() { tone "$1" "$2"; }

say_err() {
    AXS_PAINT_FD=2
    printf '%s\n' "$(bad "$1")" >&2
}

show_usage() {
    cat >&2 <<'EOF'
用法：axs start|stop|status|restart|ensure|clean
      axs service enable|disable
      axs sub get|refresh|clean
      axs rule list|add|del
      axs node groups|list|test|switch
      axs net test
      axs proxy user on|off|status; system on|off|enable|disable|status; session enable|disable|status
EOF
}

help_row() {
    padded=$(printf '%-22s' "$1")
    printf '%s\n' "$(ident "$padded")  $(dim "$2")" >&"$AXS_HELP_FD"
}

help_note() {
    printf '%s\n' "$(dim "$1")" >&"$AXS_HELP_FD"
}

show_help() {
    AXS_HELP_FD=$1
    AXS_PAINT_FD=$1
    printf '%s\n' "$(bold '用法')" >&"$AXS_HELP_FD"
    printf '\n%s\n' "$(bold '服务')" >&"$AXS_HELP_FD"
    help_row "axs start" "启动服务"
    help_row "axs stop" "停止服务"
    help_row "axs restart" "重启服务"
    help_row "axs status" "查看状态"
    help_row "axs ensure" "保证服务在跑"
    help_row "axs service enable" "打开开机自启"
    help_row "axs service disable" "关闭开机自启"
    help_note "例：axs status"
    printf '\n%s\n' "$(bold '订阅')" >&"$AXS_HELP_FD"
    help_row "axs sub get" "查看订阅剩余"
    help_row "axs sub refresh" "拉取并重载"
    help_row "axs sub clean" "删除订阅缓存"
    help_note "例：axs sub get"
    printf '\n%s\n' "$(bold '规则')" >&"$AXS_HELP_FD"
    help_row "axs rule list" "列出域名规则"
    help_row "axs rule add via" "经策略组，后接域名和组"
    help_row "axs rule add direct" "直连，后接域名"
    help_row "axs rule del" "删除域名规则"
    help_note "例：axs rule list"
    printf '\n%s\n' "$(bold '节点')" >&"$AXS_HELP_FD"
    help_row "axs node groups" "策略组与当前节点"
    help_row "axs node list" "节点列表"
    help_row "axs node test" "测延迟，可接组名"
    help_row "axs node switch" "切换节点，后接组和节点"
    help_note "例：axs node list"
    printf '\n%s\n' "$(bold '网络')" >&"$AXS_HELP_FD"
    help_row "axs net test" "测连通，可接网址"
    help_row "axs net ip" "经代理查出口 IP"
    help_note "例：axs net test"
    printf '\n%s\n' "$(bold '代理')" >"$AXS_HELP_FD"
    help_row "axs proxy user" "当前 shell 环境（on|off|status）"
    help_row "axs proxy system" "运行时 on|off；持久 enable|disable"
    help_row "axs proxy session" "登录持久 enable|disable|status"
    help_note "status 读 dwm 环境，区分持久开关和当前会话是否已生效"
    help_note "session 的 on|off 已移除，改用 enable|disable。system on 不再写标识开关"
    help_note "例：eval \"\$(axs proxy user on)\""
    printf '\n%s\n' "$(bold '清理')" >&"$AXS_HELP_FD"
    help_row "axs clean" "删除本地配置，可加 --yes"
    help_note "例：axs clean --yes"
    help_note "颜色只是增强，管道或 NO_COLOR 下信息仍完整"
}

die() {
    code=$1
    shift
    say_err "$*"
    exit "$code"
}

ensure_run() {
    mkdir -p "$AXS_RUN"
    chmod 700 "$AXS_RUN"
}

ensure_override() {
    ensure_run
    if [ -f "$AXS_RUN/override.yaml" ]; then
        return 0
    fi
    mixed=${AXS_MIXED_PORT:-7897}
    api=${AXS_API:-127.0.0.1:9097}
    python3 "$PY" defaults "$AXS_RUN/override.yaml" "$mixed" "$api"
}

ensure_secret() {
    ensure_run
    python3 "$PY" gen-secret "$AXS_RUN/secret"
}

read_ports() {
    ensure_override
    MIXED=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1],encoding="utf-8"))["mixed-port"])' "$AXS_RUN/override.yaml")
    API=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1],encoding="utf-8"))["external-controller"])' "$AXS_RUN/override.yaml")
}

port_open() {
    python3 "$PY" probe 127.0.0.1 "$1"
}

service_up() {
    pidfile=$AXS_RUN/mihomo.pid
    if [ ! -f "$pidfile" ]; then
        return 1
    fi
    pid=$(cat "$pidfile")
    case $pid in
        ''|*[!0-9]*)
            printf '%s\n' "告警：mihomo.pid 不是数字" >&2
            return 1
            ;;
    esac
    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    if [ ! -r "/proc/$pid/cmdline" ]; then
        return 1
    fi
    tr '\0' '\n' <"/proc/$pid/cmdline" | grep -Fxq -- "$AXS_MIHOMO"
}

with_lock() {
    ensure_run
    exec 9>"$AXS_RUN/refresh.lock"
    if ! flock -n 9; then
        die 4 "锁被占用"
    fi
}

install_file() {
    src=$1
    dest=$2
    if [ -f "$dest" ]; then
        cp -p "$dest" "$dest.bak"
        chmod 600 "$dest.bak"
    fi
    # Caller already wrote src with mode 600. Replace within the run dir when possible.
    if [ "$(dirname "$src")" = "$(dirname "$dest")" ]; then
        mv -f "$src" "$dest"
    else
        cp -p "$src" "$dest.tmp"
        chmod 600 "$dest.tmp"
        mv -f "$dest.tmp" "$dest"
    fi
    chmod 600 "$dest"
}

restore_bak() {
    dest=$1
    if [ -f "$dest.bak" ]; then
        cp -p "$dest.bak" "$dest"
        chmod 600 "$dest"
    else
        rm -f "$dest"
    fi
}

snapshot() {
    snap=$AXS_RUN/.snap
    mkdir -p "$snap"
    chmod 700 "$snap"
    for name in config.yaml subscription.yaml rules.list; do
        if [ -f "$AXS_RUN/$name" ]; then
            cp -p "$AXS_RUN/$name" "$snap/$name"
        else
            rm -f "$snap/$name"
        fi
    done
}

restore_snapshot() {
    snap=$AXS_RUN/.snap
    for name in config.yaml subscription.yaml rules.list; do
        if [ -f "$snap/$name" ]; then
            cp -p "$snap/$name" "$AXS_RUN/$name"
            chmod 600 "$AXS_RUN/$name"
        else
            rm -f "$AXS_RUN/$name"
        fi
    done
    if [ -f "$snap/config.yaml" ]; then
        cp -p "$snap/config.yaml" "$AXS_RUN/config.yaml.bak"
        chmod 600 "$AXS_RUN/config.yaml.bak"
    fi
}

cmd_start() {
    if use_systemd; then
        if systemd_active; then
            exit 0
        fi
        axs_systemctl start axs.service || die 3 "启动失败"
        exit 0
    fi
    if service_up; then
        exit 0
    fi
    read_ports
    if port_open "$MIXED"; then
        die 2 "端口已被占用"
    fi
    if [ ! -f "$AXS_RUN/config.yaml" ]; then
        die 3 "没有配置"
    fi
    ensure_secret
    if command -v setsid >/dev/null 2>&1; then
        setsid "$AXS_MIHOMO" -d "$AXS_RUN" </dev/null >/dev/null 2>&1 &
    else
        "$AXS_MIHOMO" -d "$AXS_RUN" </dev/null >/dev/null 2>&1 &
    fi
    printf '%s\n' "$!" >"$AXS_RUN/mihomo.pid"
    sleep 0.1
    if ! service_up; then
        die 3 "启动失败"
    fi
}

cmd_stop() {
    if use_systemd; then
        axs_systemctl stop axs.service || die 3 "停止失败"
        exit 0
    fi
    if ! service_up; then
        rm -f "$AXS_RUN/mihomo.pid"
        exit 0
    fi
    pid=$(cat "$AXS_RUN/mihomo.pid")
    kill "$pid" 2>/dev/null || true
    i=0
    while [ "$i" -lt 20 ] && kill -0 "$pid" 2>/dev/null; do
        i=$((i + 1))
        sleep 0.05
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$AXS_RUN/mihomo.pid"
}

cmd_restart() {
    if use_systemd; then
        axs_systemctl restart axs.service || die 3 "启动失败"
        exit 0
    fi
    cmd_stop
    cmd_start
}

axs_systemctl() {
    "${AXS_SYSTEMCTL:-systemctl}" --user "$@"
}

use_systemd() {
    case ${AXS_SYSTEMD:-} in
        0) return 1 ;;
        1) return 0 ;;
    esac
    state=$(axs_systemctl show axs.service -p LoadState --value 2>/dev/null || true)
    [ "$state" = "loaded" ]
}

systemd_active() {
    axs_systemctl is-active axs.service >/dev/null 2>&1
}

format_span() {
    secs=$1
    suffix=$2
    if [ "$secs" -lt 60 ]; then
        printf '%s' "${secs} 秒${suffix}"
    elif [ "$secs" -lt 3600 ]; then
        printf '%s' "$((secs / 60)) 分钟${suffix}"
    elif [ "$secs" -lt 86400 ]; then
        printf '%s' "$((secs / 3600)) 小时${suffix}"
    else
        printf '%s' "$((secs / 86400)) 天${suffix}"
    fi
}

manual_etime() {
    pid=$1
    secs=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    case $secs in
        ''|*[!0-9]*) printf '%s' '-'; return 0 ;;
    esac
    format_span "$secs" ""
}

systemd_etime() {
    stamp=$(axs_systemctl show axs.service -p ActiveEnterTimestamp --value 2>/dev/null || true)
    case $stamp in
        ''|n/a|N/A) printf '%s' '-'; return 0 ;;
    esac
    start=$(date -d "$stamp" +%s 2>/dev/null || true)
    case $start in
        ''|*[!0-9]*) printf '%s' '-'; return 0 ;;
    esac
    now=$(date +%s)
    secs=$((now - start))
    if [ "$secs" -lt 0 ]; then
        secs=0
    fi
    format_span "$secs" ""
}

write_cache() {
    name=$1
    result=$2
    dir=$AXS_RUN/cache
    mkdir -p "$dir"
    chmod 700 "$dir"
    tmp=$dir/.$name.$$
    printf 'ts=%s\nresult=%s\n' "$(date +%s)" "$result" >"$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$dir/$name"
}

load_status_ports() {
    if [ -n "${AXS_MIXED_PORT:-}" ]; then
        MIXED=$AXS_MIXED_PORT
    elif [ -f "$AXS_RUN/override.yaml" ]; then
        MIXED=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1],encoding="utf-8"))["mixed-port"])' "$AXS_RUN/override.yaml")
    else
        MIXED=7897
    fi
    if [ -n "${AXS_API:-}" ]; then
        API=$AXS_API
    elif [ -f "$AXS_RUN/override.yaml" ]; then
        API=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1],encoding="utf-8"))["external-controller"])' "$AXS_RUN/override.yaml")
    else
        API=127.0.0.1:9097
    fi
}

controller_ok() {
    [ -f "$AXS_RUN/secret" ] || return 1
    python3 "$PY" version "$AXS_RUN/secret" "$API" >/dev/null 2>&1
}

cache_label() {
    case $1 in
        net-test) printf '%s' "net test" ;;
        *) printf '%s' "node test" ;;
    esac
}

cache_line() {
    name=$1
    label=$(cache_label "$name")
    file=$AXS_RUN/cache/$name
    if [ ! -f "$file" ]; then
        printf '%s\n' "$(label "最近 ${label}：")$(dim '-')"
        return 0
    fi
    ts=$(sed -n 's/^ts=//p' "$file" | head -n 1)
    result=$(sed -n 's/^result=//p' "$file" | head -n 1)
    case $ts in
        ''|*[!0-9]*)
            printf '%s\n' "$(label "最近 ${label}：")$(dim '-')"
            return 0
            ;;
    esac
    now=$(date +%s)
    age=$((now - ts))
    if [ "$age" -lt 0 ]; then
        age=0
    fi
    rel=$(format_span "$age" "前")
    if [ "$name" = "net-test" ]; then
        if [ "$result" = "ok" ]; then
            printf '%s\n' "$(label '最近 net test：')$(dim "$rel") $(ok '全部通')"
        else
            printf '%s\n' "$(label '最近 net test：')$(dim "$rel") $(bad '有不通')"
        fi
    else
        printf '%s\n' "$(label '最近 node test：')$(dim "$rel")"
    fi
}

status_node_empty() {
    # same sentence as status_nodes when the main chain is missing
    printf '%s\n' "$(label '节点：')$(ident '主代理') → $(dim '-') · $(ident 'GLOBAL') = $(dim '-')"
}


session_env() {
    key=$1
    pid=${AXS_SESSION_PID:-}
    if [ -z "$pid" ]; then
        pid=$(pgrep -x dwm 2>/dev/null | head -n 1 || true)
    fi
    if [ -z "$pid" ] || [ ! -r "/proc/$pid/environ" ]; then
        return 2
    fi
    line=$(tr '\0' '\n' <"/proc/$pid/environ" | grep -m 1 -e "^${key}=" || true)
    if [ -z "$line" ]; then
        return 1
    fi
    printf '%s\n' "${line#"$key"=}"
}

proxy_status_line() {
    read_ports
    port=$MIXED
    u=off
    case ${http_proxy:-${HTTPS_PROXY:-${https_proxy:-}}} in
        "http://127.0.0.1:$port") u=on ;;
    esac
    sys=off
    if command -v gsettings >/dev/null 2>&1; then
        m=$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'" || true)
        h=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null | tr -d "'" || true)
        p=$(gsettings get org.gnome.system.proxy.http port 2>/dev/null | tr -d "'" || true)
        if [ "$m" = "manual" ] && [ "$h" = "127.0.0.1" ] && [ "$p" = "$port" ]; then
            sys=on
        fi
    fi
    sys_flag=off
    if [ -f "$AXS_RUN/proxy-system.flag" ]; then
        sys_flag=on
    fi
    sess_flag=off
    if [ -f "$AXS_RUN/proxy-session.flag" ]; then
        sess_flag=on
    fi
    sess_live=off
    if live=$(session_env http_proxy); then
        if [ "$live" = "http://127.0.0.1:$port" ]; then
            sess_live=on
        fi
    fi
    tone_state() {
        if [ "$1" = on ]; then ok on; else dim off; fi
    }
    printf '%s %s %s · %s %s %s/%s %s · %s %s %s/%s %s\n' \
        "$(label "代理 user")" "$(dim 运行时)" "$(tone_state "$u")" \
        "$(label system)" "$(dim 运行时)" "$(tone_state "$sys")" "$(dim 持久)" "$(tone_state "$sys_flag")" \
        "$(label session)" "$(dim 持久)" "$(tone_state "$sess_flag")" "$(dim 生效)" "$(tone_state "$sess_live")"
}

cmd_status() {
    running=0
    if use_systemd; then
        if systemd_active; then
            pid=$(axs_systemctl show axs.service -p MainPID --value 2>/dev/null | tr -d '[:space:]' || true)
            case $pid in
                ''|*[!0-9]*|0) pid='-' ;;
            esac
            dur=$(systemd_etime)
            printf '%s\n' "$(label '服务：')$(emph 32 '运行中')（systemd: $(ident 'axs.service')，MainPID $(dim "$pid")，运行时长 $(dim "$dur")）"
            running=1
        else
            printf '%s\n' "$(label '服务：')$(emph 31 '未运行')（来源 systemd: $(ident 'axs.service')）"
        fi
    elif service_up; then
        pid=$(cat "$AXS_RUN/mihomo.pid")
        dur=$(manual_etime "$pid")
        printf '%s\n' "$(label '服务：')$(emph 32 '运行中')（手动，MainPID $(dim "$pid")，运行时长 $(dim "$dur")）"
        running=1
    else
        printf '%s\n' "$(label '服务：')$(emph 31 '未运行')（来源 $(dim '手动')）"
    fi
    load_status_ports
    port_ok=0
    if port_open "$MIXED"; then
        port_ok=1
    fi
    api_port=${API##*:}
    api_ok=0
    if controller_ok; then
        api_ok=1
    fi
    if [ "$port_ok" -eq 1 ] && [ "$api_ok" -eq 1 ]; then
        python3 "$PY" status-nodes "$AXS_RUN/secret" "$API" 2>/dev/null || status_node_empty
    else
        status_node_empty
    fi
    sub_out=$(python3 "$PY" status-sub "$AXS_RUN/userinfo" "$(date +%s)" 2>/dev/null) || sub_out='订阅：未知
unknown'
    printf '%s\n' "$sub_out" | head -n 1
    kind=$(printf '%s\n' "$sub_out" | tail -n 1)
    if [ "$port_ok" -eq 1 ]; then
        printf '%s\n' "$(label '端口：')$(dim "$MIXED") $(ok '监听')"
    else
        printf '%s\n' "$(label '端口：')$(dim "$MIXED") $(bad '不通')"
    fi
    if [ "$api_ok" -eq 1 ]; then
        printf '%s\n' "$(label '控制器：')$(dim "$api_port") $(ok '可达')"
    else
        printf '%s\n' "$(label '控制器：')$(dim "$api_port") $(bad '不通')"
    fi
    if use_systemd; then
        if axs_systemctl is-enabled axs.service >/dev/null 2>&1; then
            printf '%s\n' "$(label '开机自启：')$(ok 'enabled')"
        else
            printf '%s\n' "$(label '开机自启：')$(bad 'disabled')"
        fi
        next=$(axs_systemctl list-timers axs-refresh.timer --no-legend 2>/dev/null | head -n 1 || true)
        case $next in
            ''|*'timers listed'*) printf '%s\n' "$(label '定时刷新：')$(dim '-')" ;;
            *) printf '%s\n' "$(label '定时刷新：')$(dim "下次 ${next}")" ;;
        esac
    else
        printf '%s\n' "$(label '开机自启：')$(dim '-')"
        printf '%s\n' "$(label '定时刷新：')$(dim '-')"
    fi
    cache_line net-test
    cache_line node-test
    proxy_status_line
    code=0
    if [ "$running" -eq 0 ] || [ "$port_ok" -eq 0 ]; then
        code=2
    elif [ "$api_ok" -eq 0 ]; then
        code=3
    elif [ "$kind" = "expired" ]; then
        code=5
    fi
    exit "$code"
}

cmd_health() {
    if use_systemd; then
        if ! systemd_active; then
            printf '%s\n' "未运行" >&2
            exit 2
        fi
    elif ! service_up 2>/dev/null; then
        printf '%s\n' "未运行" >&2
        exit 2
    fi
    load_status_ports
    if ! port_open "$MIXED"; then
        printf '%s\n' "端口不通" >&2
        exit 2
    fi
    if ! controller_ok; then
        printf '%s\n' "控制器不通" >&2
        exit 3
    fi
    kind=$(python3 "$PY" classify "$AXS_RUN/userinfo" "$(date +%s)" 2>/dev/null || true)
    if [ "$kind" = "expired" ]; then
        printf '%s\n' "订阅过期" >&2
        exit 5
    fi
    exit 0
}

cmd_sub_get() {
    python3 "$PY" show-userinfo "$AXS_RUN/userinfo" "$(date +%s)"
}

cmd_service_boot() {
    op=$1
    if ! use_systemd; then
        die 3 "没有 systemd"
    fi
    axs_systemctl "$op" axs.service axs-refresh.timer || die 3 "自启失败"
    if [ "$op" = "enable" ]; then
        printf '%s\n' "$(label '开机自启：')$(ok 'enabled')"
    else
        printf '%s\n' "$(label '开机自启：')$(bad 'disabled')"
    fi
}

apply_config() {
    body=$1
    if [ "${2:-}" != "keep" ]; then
        snapshot
    fi
    if ! python3 "$PY" build "$body" "$AXS_RUN/override.yaml" "$AXS_RUN/secret" "$AXS_RUN/rules.list" "$AXS_RUN/config.yaml.new"; then
        restore_snapshot
        die 3 "校验失败"
    fi
    install_file "$AXS_RUN/config.yaml.new" "$AXS_RUN/config.yaml"
    if [ "$body" != "$AXS_RUN/subscription.yaml" ]; then
        install_file "$body" "$AXS_RUN/subscription.yaml"
    fi
    if service_up; then
        if ! python3 "$PY" reload "$AXS_RUN/secret" "$API" "$AXS_RUN/config.yaml"; then
            restore_snapshot
            die 3 "重载失败"
        fi
    fi
}

cmd_refresh() {
    with_lock
    if [ ! -f "$AXS_RUN/subscription.url" ]; then
        die 3 "没有订阅"
    fi
    chmod 600 "$AXS_RUN/subscription.url"
    python3 "$PY" check-url "$AXS_RUN/subscription.url" || exit $?
    body=$AXS_RUN/fetch.yaml
    hdr=$AXS_RUN/fetch.hdr
    if [ -n "${AXS_FETCH:-}" ]; then
        if ! "$AXS_FETCH" "$AXS_RUN/subscription.url" "$body" "$hdr"; then
            die 3 "拉取失败"
        fi
    elif ! python3 "$PY" fetch "$AXS_RUN/subscription.url" "$body" "$hdr"; then
        die 3 "拉取失败"
    fi
    python3 "$PY" check-fetched "$body" "$hdr" || exit $?
    ensure_override
    ensure_secret
    read_ports
    apply_config "$body"
    python3 "$PY" userinfo "$hdr" "$AXS_RUN/userinfo"
    rm -f "$body" "$hdr" "$AXS_RUN/.snap/config.yaml" "$AXS_RUN/.snap/subscription.yaml"
}

cmd_rule_list() {
    if [ -f "$AXS_RUN/rules.list" ]; then
        cat "$AXS_RUN/rules.list"
    fi
}

mutate_rules() {
    # $1 is add or del, remaining args passed through
    op=$1
    shift
    if [ "$op" = "add" ]; then
        line=$(python3 "$PY" parse-rule "$@") || exit 1
    else
        line=$(python3 "$PY" parse-rule direct "$1" "") || exit 1
    fi
    if service_up && [ "${1:-}" = "via" ]; then
        read_ports
        python3 "$PY" has-group "$AXS_RUN/secret" "$API" "$3" || exit 3
    fi
    with_lock
    snapshot
    if [ "$op" = "add" ]; then
        python3 "$PY" rules-add "$AXS_RUN/rules.list" "$line"
    else
        python3 "$PY" rules-del "$AXS_RUN/rules.list" "$1"
    fi
    if service_up; then
        if [ ! -f "$AXS_RUN/subscription.yaml" ]; then
            restore_snapshot
            die 3 "没有订阅"
        fi
        read_ports
        ensure_secret
        apply_config "$AXS_RUN/subscription.yaml" keep
    else
        printf '%s\n' "已写入，启动时生效"
    fi
}

cmd_rule_add() {
    kind=${1:-}
    case $kind in
        via)
            [ $# -eq 3 ] || die 1 "用法"
            mutate_rules add via "$2" "$3"
            ;;
        direct)
            [ $# -eq 2 ] || die 1 "用法"
            mutate_rules add direct "$2"
            ;;
        *) die 1 "用法" ;;
    esac
}

cmd_rule_del() {
    [ $# -eq 1 ] || die 1 "用法"
    mutate_rules del "$1"
}

api_addr() {
    if [ -n "${AXS_API:-}" ]; then
        printf '%s\n' "$AXS_API"
        return 0
    fi
    if [ ! -f "$AXS_RUN/override.yaml" ]; then
        return 1
    fi
    python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1],encoding="utf-8"))["external-controller"])' "$AXS_RUN/override.yaml"
}

cmd_ensure() {
    [ $# -eq 0 ] || die 1 "用法"
    if use_systemd; then
        if systemd_active; then
            exit 0
        fi
        read_ports
        if port_open "$MIXED"; then
            die 2 "端口已被占用"
        fi
        if [ ! -f "$AXS_RUN/config.yaml" ]; then
            if [ ! -f "$AXS_RUN/subscription.url" ]; then
                die 3 "没有订阅"
            fi
            cmd_refresh
        fi
        axs_systemctl start axs.service || die 3 "启动失败"
        exit 0
    fi
    if service_up; then
        exit 0
    fi
    read_ports
    # A busy port must not pull the subscription.
    if port_open "$MIXED"; then
        die 2 "端口已被占用"
    fi
    if [ ! -f "$AXS_RUN/config.yaml" ]; then
        if [ ! -f "$AXS_RUN/subscription.url" ]; then
            die 3 "没有订阅"
        fi
        cmd_refresh
    fi
    cmd_start
}

cmd_node_list() {
    full=0
    for arg in "$@"; do
        case $arg in
            --full|-l) full=1 ;;
            *) die 1 "用法" ;;
        esac
    done
    if ! service_up; then
        die 2 "服务：未运行"
    fi
    api=$(api_addr) || die 3 "控制器"
    if [ "$full" -eq 1 ]; then
        python3 "$PY" node-list "$AXS_RUN/secret" "$api" --full || exit $?
    else
        python3 "$PY" node-list "$AXS_RUN/secret" "$api" "$AXS_RUN" || exit $?
    fi
}

cmd_switch() {
    [ $# -eq 2 ] || die 1 "用法"
    if ! service_up; then
        die 2 "服务：未运行"
    fi
    api=$(api_addr) || die 3 "控制器"
    python3 "$PY" select "$AXS_RUN/secret" "$api" "$1" "$2" "$AXS_RUN" || exit $?
}

cmd_net_ip() {
    [ $# -eq 0 ] || die 1 "用法"
    read_ports
    if ! port_open "$MIXED"; then
        die 2 "入站：不通"
    fi
    python3 "$PY" egress "http://127.0.0.1:$MIXED" || exit $?
}

cmd_net() {
    code=0
    python3 "$PY" net-precheck "$AXS_RUN/urls" "$@" || code=$?
    if [ "$code" -eq 1 ]; then
        die 1 "用法"
    fi
    if [ "$code" -ne 0 ]; then
        die 3 "禁止外网"
    fi
    read_ports
    if ! port_open "$MIXED"; then
        die 2 "入站：不通"
    fi
    timeout=${AXS_NET_TIMEOUT_MS:-5000}
    code=0
    python3 "$PY" net-run "$AXS_RUN/urls" "http://127.0.0.1:$MIXED" "$timeout" "$@" || code=$?
    if [ "$code" -eq 0 ]; then
        write_cache net-test ok
    else
        write_cache net-test fail
    fi
    exit "$code"
}

cmd_groups() {
    if ! service_up; then
        die 2 "服务：未运行"
    fi
    api=$(api_addr) || die 3 "控制器"
    python3 "$PY" groups-show "$AXS_RUN/secret" "$api" || exit $?
}

cmd_test() {
    if ! service_up; then
        die 2 "服务：未运行"
    fi
    read_ports
    group=${1:-}
    if [ -z "$group" ]; then
        group=$(python3 "$PY" default-group "$AXS_RUN/secret" "$API") || exit $?
    fi
    [ -n "$group" ] || die 3 "组名不存在"
    code=0
    tmp=$(mktemp)
    if [ -n "${AXS_DELAY_URL:-}" ]; then
        python3 "$PY" delay "$AXS_RUN/secret" "$API" "$group" "$AXS_DELAY_URL" >"$tmp" || code=$?
    else
        python3 "$PY" delay "$AXS_RUN/secret" "$API" "$group" >"$tmp" || code=$?
    fi
    cat "$tmp"
    if [ "$code" -eq 0 ]; then
        python3 "$PY" cache-node "$AXS_RUN/cache/node-test" "$group" "$tmp"
        rm -f "$tmp"
    else
        rm -f "$tmp"
        write_cache node-test fail
        exit "$code"
    fi
}

clean_run() {
    kind=$1
    shift
    yes=0
    if [ $# -gt 1 ]; then
        die 1 "用法"
    fi
    if [ $# -eq 1 ]; then
        [ "$1" = "--yes" ] || die 1 "用法"
        yes=1
    fi
    if service_up; then
        die 2 "服务在运行，先 axs stop"
    fi
    if [ "$kind" = "config" ]; then
        set -- config.yaml config.yaml.bak userinfo fetch.yaml fetch.hdr mihomo.pid
    else
        set -- subscription.url subscription.yaml userinfo fetch.yaml fetch.hdr
    fi
    if [ -d "$AXS_RUN" ]; then
        root=$(readlink -f -- "$AXS_RUN") || die 3 "越界"
    else
        root=''
    fi
    list=''
    for name in "$@"; do
        case $name in
            */*|*..*) die 3 "越界" ;;
        esac
        path=$AXS_RUN/$name
        if [ -L "$path" ] || [ -e "$path" ]; then
            resolved=$(readlink -f -- "$path") || die 3 "越界"
            case $resolved in
                "$root"/*) ;;
                *) die 3 "越界" ;;
            esac
            list="${list}${path}
"
        fi
    done
    if [ "$yes" -eq 0 ]; then
        if [ -n "$list" ]; then
            printf '%s' "$(dim "$list")"
        fi
        if [ -t 0 ]; then
            AXS_PAINT_FD=2
            printf '%s' "$(bold '确认删除？[y/N] ')" >&2
            AXS_PAINT_FD=1
            IFS= read -r answer || die 1 "需要 --yes"
            case $answer in
                y|Y|yes|YES) ;;
                *) die 1 "需要 --yes" ;;
            esac
        else
            die 1 "需要 --yes"
        fi
    fi
    deleted=0
    for name in "$@"; do
        path=$AXS_RUN/$name
        if [ -L "$path" ] || [ -e "$path" ]; then
            rm -f -- "$path" || die 3 "删除失败"
            deleted=1
        fi
    done
    if [ "$deleted" -eq 1 ]; then
        printf '%s\n' "$(ok '已删除')"
    fi
}

cmd_clean() {
    clean_run config "$@"
}

cmd_sub_clean() {
    clean_run sub "$@"
}

# ---- proxy: three access layers ----
proxy_mixed() {
    read_ports
    printf '%s' "$MIXED"
}

cmd_proxy_user() {
    sub=${1:-}
    [ $# -eq 1 ] || die 1 "用法"
    port=$(proxy_mixed)
    case $sub in
        on)
            printf '%s\n' "提示：需 eval \"\$(axs proxy user on)\" 才会生效" >&2
            printf 'export http_proxy=http://127.0.0.1:%s\n' "$port"
            printf 'export https_proxy=http://127.0.0.1:%s\n' "$port"
            printf 'export all_proxy=socks5://127.0.0.1:%s\n' "$port"
            printf 'export no_proxy=localhost,127.0.0.1,::1\n'
            printf 'export HTTP_PROXY=http://127.0.0.1:%s\n' "$port"
            printf 'export HTTPS_PROXY=http://127.0.0.1:%s\n' "$port"
            printf 'export ALL_PROXY=socks5://127.0.0.1:%s\n' "$port"
            printf 'export NO_PROXY=localhost,127.0.0.1,::1\n'
            ;;
        off)
            printf '%s\n' 'unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY'
            ;;
        status)
            want="http://127.0.0.1:$port"
            cur=${http_proxy:-${HTTPS_PROXY:-${https_proxy:-}}}
            if [ "$cur" = "$want" ]; then
                printf '%s\n' "user：$(ok on)（$cur）"
                exit 0
            fi
            printf '%s\n' "user：$(bad off)（${cur:-未设置}）"
            exit 1
            ;;
        *) die 1 "用法" ;;
    esac
}

cmd_proxy_system() {
    sub=${1:-}
    [ $# -eq 1 ] || die 1 "用法"
    flag=$AXS_RUN/proxy-system.flag
    xp=${AXS_XPROFILE:-$HOME/.config/x11/xprofile}
    case $sub in
        on|off|status)
            command -v gsettings >/dev/null 2>&1 || die 3 "没有 gsettings"
            ;;
    esac
    gs=org.gnome.system.proxy
    case $sub in
        on)
            port=$(proxy_mixed)
            gsettings set "$gs" mode 'manual' || die 3 "gsettings 失败"
            gsettings set "$gs.http" host '127.0.0.1' || die 3 "gsettings 失败"
            gsettings set "$gs.http" port "$port" || die 3 "gsettings 失败"
            gsettings set "$gs.https" host '127.0.0.1' || die 3 "gsettings 失败"
            gsettings set "$gs.https" port "$port" || die 3 "gsettings 失败"
            gsettings set "$gs" ignore-hosts "['localhost','127.0.0.1','::1']" || die 3 "gsettings 失败"
            printf '%s\n' "system：$(ok on)（127.0.0.1:$port）"
            ;;
        off)
            gsettings set "$gs" mode 'none' || die 3 "gsettings 失败"
            printf '%s\n' "system：$(bad off)"
            ;;
        enable)
            mkdir -p "$AXS_RUN"
            ( umask 077; : >"$flag" )
            chmod 600 "$flag"
            rm -f "$AXS_RUN/gsettings-identity"
            printf '%s\n' "system：$(ok enabled)（重登 X 后 libproxy/Edge 才会读取 gsettings）"
            ;;
        disable)
            rm -f "$flag"
            printf '%s\n' "system：$(bad disabled)"
            ;;
        status)
            port=$(proxy_mixed)
            mode=$(gsettings get "$gs" mode 2>/dev/null | tr -d "'" ) || die 3 "gsettings 失败"
            host=$(gsettings get "$gs.http" host 2>/dev/null | tr -d "'" ) || true
            sport=$(gsettings get "$gs.http" port 2>/dev/null | tr -d "'" ) || true
            if [ "$mode" = "manual" ] && [ "$host" = "127.0.0.1" ] && [ "$sport" = "$port" ]; then
                printf '%s\n' "system：$(ok on)（mode=$mode host=$host port=$sport）"
                code=0
            else
                printf '%s\n' "system：$(bad off)（mode=$mode host=$host port=$sport）"
                code=1
            fi
            if [ -f "$flag" ] && { [ ! -f "$xp" ] || ! grep -q 'axs proxy system identity (managed)' "$xp"; }; then
                printf '%s\n' "持久：$(warn enabled)（待挂接）"
            elif [ -f "$flag" ]; then
                printf '%s\n' "持久：$(ok enabled)（xprofile 已挂接）"
            else
                printf '%s\n' "持久：$(bad disabled)"
            fi
            desk_state=off
            desk=$(session_env XDG_CURRENT_DESKTOP) && desk_rc=0 || desk_rc=$?
            if [ "$desk_rc" -eq 0 ]; then
                case ":$desk:" in
                    *:GNOME:*) desk_state=on ;;
                esac
            elif [ "$desk_rc" -eq 2 ]; then
                desk_state=none
            fi
            if [ "$desk_state" = on ]; then
                printf '%s\n' "会话标识：$(ok 生效)"
            elif [ "$desk_state" = none ]; then
                none_msg=$(warn "无 X 会话")
                printf '%s\n' "会话标识：$none_msg"
            else
                printf '%s\n' "会话标识：$(warn 未生效)（重登 X）"
            fi
            exit "$code"
            ;;
        *) die 1 "用法" ;;
    esac
}

cmd_proxy_session() {
    sub=${1:-}
    [ $# -eq 1 ] || die 1 "用法"
    flag=$AXS_RUN/proxy-session.flag
    xp=${AXS_XPROFILE:-$HOME/.config/x11/xprofile}
    case $sub in
        enable)
            mkdir -p "$AXS_RUN"
            ( umask 077; : >"$flag" )
            chmod 600 "$flag"
            rm -f "$AXS_RUN/session-proxy"
            printf '%s\n' "session：$(ok enabled)（下次登录 X 生效）"
            ;;
        disable)
            rm -f "$flag"
            printf '%s\n' "session：$(bad disabled)"
            ;;
        status)
            port=$(proxy_mixed)
            if [ ! -f "$flag" ]; then
                printf '%s\n' "session：$(bad disabled)"
                exit 1
            fi
            if [ ! -f "$xp" ] || ! grep -q 'axs proxy session (managed)' "$xp"; then
                printf '%s\n' "session：$(warn enabled)（待挂接，xprofile 缺托管块）"
                exit 1
            fi
            live=$(session_env http_proxy) && live_rc=0 || live_rc=$?
            if [ "$live_rc" -eq 2 ]; then
                printf '%s\n' "session：$(warn enabled)（无 X 会话）"
                exit 1
            fi
            if [ "$live_rc" -eq 0 ] && [ "$live" = "http://127.0.0.1:$port" ]; then
                printf '%s\n' "session：$(ok enabled)（当前会话已生效）"
                exit 0
            fi
            printf '%s\n' "session：$(warn enabled)（当前会话未生效，重登 X）"
            exit 1
            ;;
        *) die 1 "用法" ;;
    esac
}
