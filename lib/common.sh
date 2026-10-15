#!/bin/sh
# Lock, atomic install, and controller calls. ROOT is set by bin/axs.
# shortcut: AXS_FETCH / AXS_MIXED_PORT / AXS_API keep the suite offline; leave them unset in production.
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
    cmd_stop
    cmd_start
}

expiry_line() {
    kind=$(python3 "$PY" classify "$AXS_RUN/userinfo" "$(date +%s)" || true)
    case $kind in
        expired) printf '%s\n' "已过期" ;;
        soon) printf '%s\n' "警告：订阅剩余不足 3 天" ;;
        unknown) printf '%s\n' "未知" ;;
        ok) printf '%s\n' "订阅有效" ;;
        *) printf '%s\n' "未知" ;;
    esac
    printf '%s' "$kind"
}

report() {
    # $1 is health or status
    mode=$1
    if ! service_up; then
        printf '%s\n' "服务：未运行" 
        exit 2
    fi
    read_ports
    if ! port_open "$MIXED"; then
        printf '%s\n' "入站：不通"
        exit 2
    fi
    if ! python3 "$PY" version "$AXS_RUN/secret" "$API"; then
        printf '%s\n' "控制器：不通"
        exit 3
    fi
    line=$(expiry_line)
    kind=$(printf '%s\n' "$line" | tail -n 1)
    printf '%s\n' "$line" | head -n 1
    if [ "$mode" = "health" ] && [ "$kind" = "expired" ]; then
        exit 5
    fi
}

cmd_status() {
    report status
}

cmd_health() {
    report health
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
    body=$AXS_RUN/fetch.yaml
    hdr=$AXS_RUN/fetch.hdr
    if [ -n "${AXS_FETCH:-}" ]; then
        if ! "$AXS_FETCH" "$AXS_RUN/subscription.url" "$body" "$hdr"; then
            die 3 "拉取失败"
        fi
    elif ! python3 "$PY" fetch "$AXS_RUN/subscription.url" "$body" "$hdr"; then
        die 3 "拉取失败"
    fi
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

cmd_groups() {
    if ! service_up; then
        die 2 "服务：未运行"
    fi
    read_ports
    python3 "$PY" groups "$AXS_RUN/secret" "$API" || die 3 "控制器"
}

cmd_test() {
    if ! service_up; then
        die 2 "服务：未运行"
    fi
    read_ports
    group=${1:-}
    if [ -z "$group" ]; then
        group=$(python3 "$PY" groups "$AXS_RUN/secret" "$API" | head -n 1) || die 3 "控制器"
    fi
    [ -n "$group" ] || die 3 "组名不存在"
    python3 "$PY" delay "$AXS_RUN/secret" "$API" "$group" || die 3 "控制器"
}
