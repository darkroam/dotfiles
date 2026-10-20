#!/bin/sh
# Lock, atomic install, and controller calls. ROOT is set by bin/axs.
# shortcut: AXS_FETCH / AXS_MIXED_PORT / AXS_API / AXS_DELAY_URL keep tests off the public net; leave them unset in production.
set -eu

: "${ROOT:?}"
PY=$ROOT/lib/merge.py
: "${AXS_RUN:=$ROOT/run}"
: "${AXS_MIHOMO:=$HOME/.local/bin/mihomo}"

die() {
    code=$1
    shift
    printf '%s\n' "$*" >&2
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
        printf '%s\n' "最近 ${label}：-"
        return 0
    fi
    ts=$(sed -n 's/^ts=//p' "$file" | head -n 1)
    result=$(sed -n 's/^result=//p' "$file" | head -n 1)
    case $ts in
        ''|*[!0-9]*)
            printf '%s\n' "最近 ${label}：-"
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
            printf '%s\n' "最近 net test：${rel} 全部通"
        else
            printf '%s\n' "最近 net test：${rel} 有不通"
        fi
    else
        printf '%s\n' "最近 node test：${rel}"
    fi
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
            printf '%s\n' "服务：运行中（systemd: axs.service，MainPID ${pid}，运行时长 ${dur}）"
            running=1
        else
            printf '%s\n' "服务：未运行（来源 systemd: axs.service）"
        fi
    elif service_up; then
        pid=$(cat "$AXS_RUN/mihomo.pid")
        dur=$(manual_etime "$pid")
        printf '%s\n' "服务：运行中（手动，MainPID ${pid}，运行时长 ${dur}）"
        running=1
    else
        printf '%s\n' "服务：未运行（来源 手动）"
    fi
    load_status_ports
    port_ok=0
    if port_open "$MIXED"; then
        printf '%s\n' "端口：${MIXED} 监听"
        port_ok=1
    else
        printf '%s\n' "端口：${MIXED} 不通"
    fi
    api_port=${API##*:}
    api_ok=0
    if controller_ok; then
        printf '%s\n' "控制器：${api_port} 可达"
        api_ok=1
    else
        printf '%s\n' "控制器：${api_port} 不通"
    fi
    if [ "$port_ok" -eq 1 ] && [ "$api_ok" -eq 1 ]; then
        python3 "$PY" status-nodes "$AXS_RUN/secret" "$API" 2>/dev/null || printf '%s\n' "节点：主代理 = -；自动选择 = -；GLOBAL = -"
    else
        printf '%s\n' "节点：主代理 = -；自动选择 = -；GLOBAL = -"
    fi
    sub_out=$(python3 "$PY" status-sub "$AXS_RUN/userinfo" "$(date +%s)" 2>/dev/null) || sub_out='订阅：未知
unknown'
    printf '%s\n' "$sub_out" | head -n 1
    kind=$(printf '%s\n' "$sub_out" | tail -n 1)
    if use_systemd; then
        next=$(axs_systemctl list-timers axs-refresh.timer --no-legend 2>/dev/null | head -n 1 || true)
        case $next in
            ''|*'timers listed'*) printf '%s\n' "定时刷新：-" ;;
            *) printf '%s\n' "定时刷新：下次 ${next}" ;;
        esac
    else
        printf '%s\n' "定时刷新：-"
    fi
    cache_line net-test
    cache_line node-test
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
            printf '%s' "$list"
        fi
        if [ -t 0 ]; then
            printf '%s' '确认删除？[y/N] ' >&2
            IFS= read -r answer || die 1 "需要 --yes"
            case $answer in
                y|Y|yes|YES) ;;
                *) die 1 "需要 --yes" ;;
            esac
        else
            die 1 "需要 --yes"
        fi
    fi
    for name in "$@"; do
        path=$AXS_RUN/$name
        if [ -L "$path" ] || [ -e "$path" ]; then
            rm -f -- "$path" || die 3 "删除失败"
        fi
    done
}

cmd_clean() {
    clean_run config "$@"
}

cmd_sub_clean() {
    clean_run sub "$@"
}
