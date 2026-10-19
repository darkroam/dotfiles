#!/bin/sh
# Loopback stand-in. No systemd and no names outside the allow list.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LAB=$ROOT/tests/env/lab.py
AXS=$ROOT/bin/axs
VAR=$ROOT/tests/env/var
HTTP=18091
PROXY=18092
MIXED=18093
API_PORT=18094
DNS=18095
API=127.0.0.1:$API_PORT
MARK=DOMAIN,marker.test,DIRECT

export AXS_RUN="$VAR/run"
export AXS_MIXED_PORT="$MIXED"
export AXS_API="$API"
export AXS_DELAY_URL="http://127.0.0.1:$HTTP/204"
unset AXS_FETCH AXS_FAKE_DIR AXS_FORBID_NET || true

say() {
    printf '%s\n' "$*"
}

wipe() {
    python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$VAR" || true
}

stop_lab() {
    if [ ! -f "$VAR/lab.pid" ]; then
        return 0
    fi
    pid=$(cat "$VAR/lab.pid")
    if [ -z "$pid" ]; then
        return 0
    fi
    kill "$pid" 2>/dev/null || true
    i=0
    while [ "$i" -lt 20 ] && kill -0 "$pid" 2>/dev/null; do
        i=$((i + 1))
        sleep 0.05
    done
    kill -9 "$pid" 2>/dev/null || true
}

down() {
    if [ -x "$AXS" ]; then
        "$AXS" stop >/dev/null 2>&1 || true
    fi
    stop_lab
}

code_of() {
    set +e
    "$AXS" "$@" >"$VAR/out" 2>"$VAR/err"
    CODE=$?
    set -e
}

need() {
    want=$1
    label=$2
    shift 2
    code_of "$@"
    if [ "$CODE" -ne "$want" ]; then
        say "FAIL $label want $want got $CODE"
        if [ -f "$VAR/err" ]; then
            cat "$VAR/err" >&2
        fi
        return 1
    fi
}

has_rule() {
    python3 "$LAB" has "$1" "$2"
}

up() {
    if [ -f "$VAR/ready" ] && [ -f "$AXS_RUN/mihomo.pid" ] && [ -f "$VAR/lab.pid" ]; then
        if kill -0 "$(cat "$VAR/lab.pid")" 2>/dev/null && "$AXS" status >/dev/null 2>&1; then
            return 0
        fi
    fi
    down
    wipe
    mkdir -p "$AXS_RUN"
    chmod 700 "$VAR" "$AXS_RUN"
    python3 "$LAB" serve "$VAR" "$HTTP" "$PROXY" "$DNS" >>"$VAR/lab.log" 2>&1 &
    printf '%s\n' "$!" >"$VAR/boot.pid"
    i=0
    while [ "$i" -lt 40 ]; do
        if [ -f "$VAR/ready" ]; then
            break
        fi
        if ! kill -0 "$(cat "$VAR/boot.pid")" 2>/dev/null; then
            say "FAIL lab did not bind"
            if [ -f "$VAR/lab.log" ]; then
                cat "$VAR/lab.log" >&2
            fi
            return 1
        fi
        i=$((i + 1))
        sleep 0.05
    done
    if [ ! -f "$VAR/ready" ]; then
        say "FAIL lab did not bind"
        return 1
    fi
    printf '%s\n' "http://127.0.0.1:$HTTP/sub" >"$AXS_RUN/subscription.url"
    chmod 600 "$AXS_RUN/subscription.url"
    if ! "$AXS" sub refresh >"$VAR/out" 2>"$VAR/err"; then
        say "FAIL refresh"
        cat "$VAR/err" >&2
        return 1
    fi
    if ! "$AXS" start >"$VAR/out" 2>"$VAR/err"; then
        say "FAIL start"
        cat "$VAR/err" >&2
        return 1
    fi
    i=0
    while [ "$i" -lt 50 ]; do
        if "$AXS" health >/dev/null 2>&1; then
            python3 "$LAB" audit "$(cat "$AXS_RUN/mihomo.pid")"
            python3 "$LAB" audit "$(cat "$VAR/lab.pid")"
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    say "FAIL health"
    return 1
}

static() {
    python3 "$LAB" selfcheck
    python3 "$LAB" kernel
    python3 "$LAB" merge-check
}

check() {
    static
    say "a kernel-reject"
    up
    groups=$("$AXS" node groups)
    printf '%s\n' "$groups" | grep -x PROXY >/dev/null || {
        say "FAIL groups"
        return 1
    }
    delay=$("$AXS" node test PROXY)
    case $delay in
        *' '[1-9]*) ;;
        *) say "FAIL delay"; printf '%s\n' "$delay" >&2; return 1 ;;
    esac
    say "b groups-delay"
    "$AXS" rule add via target.test PROXY >/dev/null
    via=$(curl -fsS --max-time 5 -x "http://127.0.0.1:$MIXED" "http://target.test:$HTTP/who")
    [ "$via" = "node" ] || { say "FAIL via"; printf '%s\n' "$via" >&2; return 1; }
    "$AXS" rule add direct target.test >/dev/null
    direct=$(curl -fsS --max-time 5 -x "http://127.0.0.1:$MIXED" "http://target.test:$HTTP/who")
    [ "$direct" = "direct" ] || { say "FAIL direct"; printf '%s\n' "$direct" >&2; return 1; }
    if [ -f "$VAR/tripwire" ]; then
        say "FAIL tripwire during traffic"
        return 1
    fi
    python3 "$LAB" poke "$PROXY" "$VAR"
    say "c via-direct"
    rm -f "$VAR/tripwire"
    [ "$(has_rule "$AXS_RUN/config.yaml" "$MARK")" = "no" ] || { say "FAIL marker already present"; return 1; }
    : >"$VAR/marker"
    "$AXS" sub refresh >/dev/null
    [ "$(has_rule "$AXS_RUN/config.yaml" "$MARK")" = "yes" ] || { say "FAIL marker missing"; return 1; }
    [ -f "$AXS_RUN/config.yaml.bak" ] || { say "FAIL bak missing"; return 1; }
    [ "$(has_rule "$AXS_RUN/config.yaml.bak" "$MARK")" = "no" ] || { say "FAIL bak has marker"; return 1; }
    cp -p "$AXS_RUN/config.yaml" "$VAR/good-config"
    cp -p "$AXS_RUN/subscription.yaml" "$VAR/good-sub"
    : >"$VAR/bad"
    need 3 "bad refresh" sub refresh || return 1
    cmp -s "$AXS_RUN/config.yaml" "$VAR/good-config" || { say "FAIL config replaced"; return 1; }
    cmp -s "$AXS_RUN/subscription.yaml" "$VAR/good-sub" || { say "FAIL body replaced"; return 1; }
    cmp -s "$AXS_RUN/config.yaml.bak" "$VAR/good-config" || { say "FAIL bak not rebuilt"; return 1; }
    rm -f "$VAR/bad"
    flock "$AXS_RUN/refresh.lock" -c 'sleep 2' &
    lockpid=$!
    i=0
    while [ "$i" -lt 30 ]; do
        if ! flock -n "$AXS_RUN/refresh.lock" -c true; then
            break
        fi
        i=$((i + 1))
        sleep 0.05
    done
    need 4 "lock" sub refresh || return 1
    grep -q '锁' "$VAR/err" || { say "FAIL lock text"; return 1; }
    wait "$lockpid" || true
    say "d refresh-rollback-lock"
    printf '%s\n' past >"$VAR/expire"
    "$AXS" sub refresh >/dev/null
    need 5 "expired" health || return 1
    grep -q '已过期' "$VAR/out" || { say "FAIL expired text"; return 1; }
    printf '%s\n' soon >"$VAR/expire"
    "$AXS" sub refresh >/dev/null
    need 0 "soon" health || return 1
    grep -q '警告' "$VAR/out" || { say "FAIL soon text"; return 1; }
    printf '%s\n' ok >"$VAR/expire"
    "$AXS" sub refresh >/dev/null
    need 0 "valid" health || return 1
    grep -q '订阅有效' "$VAR/out" || { say "FAIL valid text"; return 1; }
    say "e health"
    old=$(cat "$AXS_RUN/mihomo.pid")
    up
    [ "$(cat "$AXS_RUN/mihomo.pid")" = "$old" ] || { say "FAIL second up restarted"; return 1; }
    kill -9 "$old" 2>/dev/null || true
    rm -f "$VAR/ready"
    up
    [ "$(cat "$AXS_RUN/mihomo.pid")" != "$old" ] || { say "FAIL did not restart"; return 1; }
    python3 "$LAB" audit "$(cat "$AXS_RUN/mihomo.pid")"
    if [ -f "$VAR/tripwire" ]; then
        say "FAIL tripwire left set"
        return 1
    fi
    code=$(python3 "$LAB" reload-bad "$AXS_RUN" "$API")
    case $code in
        2??) say "a-reload accepted $code" ;;
        *) say "a-reload rejected $code" ;;
    esac
    if ! kill -0 "$(cat "$AXS_RUN/mihomo.pid")" 2>/dev/null; then
        say "FAIL reload stopped the process"
        return 1
    fi
    say "f idempotent"
}

cmd=${1:-check}
case $cmd in
    static) static ;;
    up) up ;;
    down) down; wipe ;;
    check)
        trap 'down; wipe' EXIT
        check
        ;;
    *)
        say "usage: run.sh static|up|down|check" >&2
        exit 1
        ;;
esac
