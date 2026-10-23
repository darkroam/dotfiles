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

resolve_token() {
    word=$1
    words=$2
    aliases=$3
    rest=$aliases
    while [ -n "$rest" ]; do
        pair=${rest%% *}
        rest=${rest#"$pair"}
        rest=${rest# }
        key=${pair%%=*}
        val=${pair#*=}
        if [ "$word" = "$key" ]; then
            printf '%s\n' "$val"
            return 0
        fi
    done
    rest=$words
    while [ -n "$rest" ]; do
        name=${rest%% *}
        rest=${rest#"$name"}
        rest=${rest# }
        if [ "$word" = "$name" ]; then
            printf '%s\n' "$name"
            return 0
        fi
    done
    hit=
    n=0
    rest=$words
    while [ -n "$rest" ]; do
        name=${rest%% *}
        rest=${rest#"$name"}
        rest=${rest# }
        if [ "${name#"$word"}" != "$name" ]; then
            if [ -z "$hit" ]; then
                hit=$name
            else
                hit="$hit $name"
            fi
            n=$((n + 1))
        fi
    done
    if [ "$n" -eq 1 ]; then
        printf '%s\n' "$hit"
        return 0
    fi
    if [ "$n" -gt 1 ]; then
        printf '%s\n' "候选：$hit" >&2
        return 1
    fi
    return 2
}

help_row() {
    padded=$(printf '%-22s' "$1")
    alias=$(printf '%-6s' "$2")
    printf '%s\n' "$(ident "$padded")  $(dim "$alias")  $(dim "$3")" >&"$AXS_HELP_FD"
}

help_note() {
    printf '%s\n' "$(dim "$1")" >&"$AXS_HELP_FD"
}

# health 是低调入口（内部入口）：不在帮助与用法列出，可用 health 或 k 调用，候选可含。
show_help() {
    AXS_HELP_FD=$1
    AXS_PAINT_FD=$1
    printf '%s\n' "$(bold '用法')" >&"$AXS_HELP_FD"
    printf '%s\n' "$(bold "$(printf '%-22s  %s' '命令' '别名')")" >&"$AXS_HELP_FD"
    help_note "单字符精确优先；未命中则唯一前缀。多个候选退出 1 并列出。h 与 ? 是这份帮助"
    printf '\n%s\n' "$(bold '服务')" >&"$AXS_HELP_FD"
    help_row "axs start" "x" "启动服务"
    help_row "axs stop" "o" "停止服务"
    help_row "axs restart" "-" "重启服务"
    help_row "axs status" "s" "查看状态"
    help_row "axs ensure" "e" "保证服务在跑"
    help_row "axs service enable" "e" "打开开机自启"
    help_row "axs service disable" "d" "关闭开机自启"
    help_note "例：axs status"
    printf '\n%s\n' "$(bold '订阅')" >&"$AXS_HELP_FD"
    help_row "axs sub get" "g" "查看订阅剩余"
    help_row "axs sub refresh" "r" "拉取并重载"
    help_row "axs sub clean" "c" "删除订阅缓存"
    help_note "例：axs sub get"
    printf '\n%s\n' "$(bold '规则')" >&"$AXS_HELP_FD"
    help_row "axs rule list" "l" "列出域名规则"
    help_row "axs rule add via" "a" "经策略组，后接域名和组"
    help_row "axs rule add direct" "a" "直连，后接域名"
    help_row "axs rule del" "d" "删除域名规则"
    help_note "例：axs rule list"
    printf '\n%s\n' "$(bold '节点')" >&"$AXS_HELP_FD"
    help_row "axs node groups" "g" "策略组与当前节点"
    help_row "axs node list" "l" "节点列表"
    help_row "axs node test" "t" "测延迟，可接组名"
    help_row "axs node switch" "s" "切换节点，后接组和节点"
    help_note "例：axs node list"
    printf '\n%s\n' "$(bold '网络')" >&"$AXS_HELP_FD"
    help_row "axs net test" "t" "测连通，可接网址"
    help_row "axs net ip" "i" "经代理查出口 IP"
    help_note "例：axs net test"
    printf '\n%s\n' "$(bold '代理')" >&"$AXS_HELP_FD"
    help_row "axs proxy user" "u" "当前 shell 环境（on|off|status）"
    help_row "axs proxy system" "s" "运行时 on|off；持久 enable|disable"
    help_row "axs proxy session" "e" "登录持久 enable|disable|status"
    help_note "status 分五节：服务、节点、订阅、测试、代理。标签对齐，节标题加粗"
    help_note "会话 effect：active、pending、-、no-x-session。persist disabled 时 effect 为 -"
    help_note "session 的 on|off 已移除，改用 enable|disable。system on 不再写标识开关"
    help_note "例：eval \"\$(axs proxy user on)\""
    printf '\n%s\n' "$(bold '清理')" >&"$AXS_HELP_FD"
    help_row "axs clean" "c" "删除本地配置，可加 --yes"
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

cache_systemd_mode() {
    case ${AXS_SYSTEMD:-} in
        0|1)
            AXS_SYSTEMD_MODE=$AXS_SYSTEMD
            return 0
            ;;
    esac
    if [ "$(axs_systemctl show axs.service -p LoadState --value 2>/dev/null | tr -d '[:space:]' || true)" = "loaded" ]; then
        AXS_SYSTEMD_MODE=1
    else
        AXS_SYSTEMD_MODE=0
    fi
}

use_systemd() {
    [ "${AXS_SYSTEMD_MODE:-0}" = 1 ]
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


cache_value() {
    name=$1
    file=$AXS_RUN/cache/$name
    if [ ! -f "$file" ]; then
        printf '%s' "$(dim '-')"
        return 0
    fi
    ts=$(sed -n 's/^ts=//p' "$file" | head -n 1)
    result=$(sed -n 's/^result=//p' "$file" | head -n 1)
    case $ts in
        ''|*[!0-9]*)
            printf '%s' "$(dim '-')"
            return 0
            ;;
    esac
    now=$(date +%s)
    age=$((now - ts))
    if [ "$age" -lt 0 ]; then
        age=0
    fi
    rel=$(format_span "$age" '前')
    if [ "$name" = "net-test" ]; then
        if [ "$result" = "ok" ]; then
            printf '%s' "$(dim "$rel") · $(ok '全部通')"
        else
            printf '%s' "$(dim "$rel") · $(bad '有不通')"
        fi
    else
        printf '%s' "$(dim "$rel")"
    fi
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

status_head() {
    printf '%s\n' "$(bold "$1")"
}

status_row() {
    printf '%s%s%s\n' '  ' "$(label "$1")" "$2"
}

json_usec() {
    key=$1
    printf '%s\n' "$2" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" | head -n 1
}

next_refresh() {
    raw=$(axs_systemctl list-timers --output=json axs-refresh.timer 2>/dev/null || true)
    next=$(json_usec next "$raw")
    left=$(json_usec left "$raw")
    case $next in
        ''|0|*[!0-9]*)
            printf '%s' '-'
            return 0
            ;;
    esac
    case $left in
        ''|0|*[!0-9]*)
            printf '%s' '-'
            return 0
            ;;
    esac
    sec=$((next / 1000000))
    left_sec=$((left / 1000000))
    now=$(date +%s)
    delta=$((left_sec - now))
    if [ "$delta" -lt 0 ]; then
        delta=0
    fi
    hm=$(date -d "@$sec" +%H:%M 2>/dev/null || true)
    case $hm in
        '')
            printf '%s' '-'
            return 0
            ;;
    esac
    rel=$(format_span "$delta" '后')
    printf '%s' "下次 ${hm}（${rel}）"
}

proxy_status_rows() {
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
    sys_flag=disabled
    if [ -f "$AXS_RUN/proxy-system.flag" ]; then
        sys_flag=enabled
    fi
    sess_flag=disabled
    if [ -f "$AXS_RUN/proxy-session.flag" ]; then
        sess_flag=enabled
    fi
    if [ "$sess_flag" = disabled ]; then
        sess_eff='-'
    else
        sess_eff=pending
        live=$(session_env http_proxy) && live_rc=0 || live_rc=$?
        if [ "$live_rc" -eq 2 ]; then
            sess_eff=no-x-session
        elif [ "$live_rc" -eq 0 ] && [ "$live" = "http://127.0.0.1:$port" ]; then
            sess_eff=active
        fi
    fi
    tone_word() {
        case $1 in
            on|enabled|active) ok "$1" ;;
            *) dim "$1" ;;
        esac
    }
    status_head '代理'
    status_row 'user    ' "$(tone_word "$u")"
    status_row 'system  ' "$(tone_word "$sys")（persist $(tone_word "$sys_flag")）"
    status_row 'session ' "$(dim persist) $(tone_word "$sess_flag") · $(dim effect) $(tone_word "$sess_eff")"
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
            state="$(emph 32 '运行中')（systemd，pid $(dim "$pid")，$(dim "$dur")）"
            running=1
        else
            state="$(emph 31 '未运行')（systemd）"
        fi
    elif service_up; then
        pid=$(cat "$AXS_RUN/mihomo.pid")
        dur=$(manual_etime "$pid")
        state="$(emph 32 '运行中')（手动，pid $(dim "$pid")，$(dim "$dur")）"
        running=1
    else
        state="$(emph 31 '未运行')（手动）"
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
    if [ "$port_ok" -eq 1 ]; then
        port_bit="$(dim "$MIXED") $(ok '监听')"
    else
        port_bit="$(dim "$MIXED") $(bad '不通')"
    fi
    if [ "$api_ok" -eq 1 ]; then
        api_bit="$(dim "$api_port") $(ok '可达')"
    else
        api_bit="$(dim "$api_port") $(bad '不通')"
    fi
    if use_systemd; then
        if axs_systemctl is-enabled axs.service >/dev/null 2>&1; then
            boot=$(ok 'enabled')
        else
            boot=$(bad 'disabled')
        fi
        when=$(next_refresh)
        boot="$boot（刷新：$when）"
    else
        boot=$(dim '-')
    fi
    status_head '服务'
    status_row '状态    ' "$state"
    status_row '端口    ' "$port_bit · 控制器 $api_bit"
    status_row '自启    ' "$boot"
    node_mid="→ $(dim '-')"
    node_g=$(dim '-')
    if [ "$port_ok" -eq 1 ] && [ "$api_ok" -eq 1 ]; then
        nodes=$(python3 "$PY" status-nodes "$AXS_RUN/secret" "$API" 2>/dev/null || true)
        one=$(printf '%s\n' "$nodes" | sed -n '1p')
        two=$(printf '%s\n' "$nodes" | sed -n '2p')
        if [ -n "$one" ]; then
            node_mid=$one
        fi
        if [ -n "$two" ]; then
            node_g=$two
        fi
    fi
    status_head '节点'
    status_row '主代理  ' "$node_mid"
    status_row 'GLOBAL  ' "$node_g"
    sub_out=$(python3 "$PY" status-sub "$AXS_RUN/userinfo" "$(date +%s)" 2>/dev/null) || sub_out="$(printf '%s\n%s\n' "$(dim '未知')" unknown)"
    sub_value=$(printf '%s\n' "$sub_out" | head -n 1)
    kind=$(printf '%s\n' "$sub_out" | tail -n 1)
    status_head '订阅'
    status_row '剩余    ' "$sub_value"
    status_head '测试'
    status_row 'net     ' "$(cache_value net-test)"
    status_row 'node    ' "$(cache_value node-test)"
    proxy_status_rows
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
        python3 "$PY" snap "$AXS_RUN"
    fi
    if ! python3 "$PY" build "$body" "$AXS_RUN/override.yaml" "$AXS_RUN/secret" "$AXS_RUN/rules.list" "$AXS_RUN/config.yaml.new"; then
        python3 "$PY" rollback "$AXS_RUN"
        die 3 "校验失败"
    fi
    python3 "$PY" install "$AXS_RUN/config.yaml.new" "$AXS_RUN/config.yaml"
    if [ "$body" != "$AXS_RUN/subscription.yaml" ]; then
        python3 "$PY" install "$body" "$AXS_RUN/subscription.yaml"
    fi
    if service_up; then
        if ! python3 "$PY" reload "$AXS_RUN/secret" "$API" "$AXS_RUN/config.yaml"; then
            python3 "$PY" rollback "$AXS_RUN"
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
    python3 "$PY" clear-fetch "$AXS_RUN"
}

cmd_rule_list() {
    if [ -f "$AXS_RUN/rules.list" ]; then
        cat "$AXS_RUN/rules.list"
    fi
}

mutate_rules() {
    op=$1
    shift
    running=0
    if service_up; then
        running=1
        read_ports
    fi
    python3 "$PY" rules-check "$AXS_RUN" "$op" "$running" "${API:-}" "$@" || exit $?
    with_lock
    python3 "$PY" rules-mutate "$AXS_RUN" "$op" "$running" "${API:-}" "$@" || exit $?
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
    names=$(python3 "$PY" clean-names "$kind")
    set --
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        set -- "$@" "$name"
    done <<EOF
$names
EOF
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
cmd_proxy_user() {
    python3 "$PY" proxy-user "$AXS_RUN" "$@" || exit $?
}

cmd_proxy_system() {
    python3 "$PY" proxy-system "$AXS_RUN" "$@" || exit $?
}

cmd_proxy_session() {
    python3 "$PY" proxy-session "$AXS_RUN" "$@" || exit $?
}
