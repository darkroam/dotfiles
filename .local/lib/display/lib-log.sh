# Private, bounded adapter diagnostics and log rotation.
# Functions: xdisplay_adapter_timestamp, xdisplay_adapter_log_value,
# xdisplay_adapter_log_event.

xdisplay_adapter_timestamp() {
    date -Iseconds 2>/dev/null || date
}

xdisplay_adapter_log_value() {
    LC_ALL=C tr -cd '\11\12\40-\176' |
        sed -E \
            -e 's#(/home/[^[:space:]]+)#<path>#g' \
            -e 's#([Xx][Aa][Uu][Tt][Hh][Oo][Rr][Ii][Tt][Yy])([=:][^[:space:]]*)#\1=<redacted>#g' \
            -e 's#([Ee][Dd][Ii][Dd])[^[:space:]]*#\1=<redacted>#g' \
            -e 's#([Ss][Ee][Rr][Ii][Aa][Ll])([=:][^[:space:]]*)#\1=<redacted>#g' \
            -e 's#([Hh][Oo][Ss][Tt][Nn][Aa][Mm][Ee])([=:][^[:space:]]*)#\1=<redacted>#g'
}

xdisplay_adapter_log_event() (
    subcommand=$1
    output=${2:-none}
    exit_code=$3
    status=$4
    detail=${5:-}
    stderr_file=${6:-}
    log_dir=${ADAPTER_LOG%/*}
    [ "$log_dir" != "$ADAPTER_LOG" ] || log_dir=.
    old_umask=$(umask)
    umask 077
    mkdir -p "$log_dir" 2>/dev/null || {
        umask "$old_umask"
        return 0
    }
    touch "$ADAPTER_LOG" 2>/dev/null || {
        umask "$old_umask"
        return 0
    }
    chmod 600 "$ADAPTER_LOG" 2>/dev/null || :
    umask "$old_umask"
    if [ -f "$ADAPTER_LOG" ]; then
        log_size=$(stat -c %s "$ADAPTER_LOG" 2>/dev/null || printf 0)
        if [ "$log_size" -ge "$ADAPTER_LOG_MAX_BYTES" ]; then
            if mv -f "$ADAPTER_LOG" "$ADAPTER_LOG.1" 2>/dev/null; then
                touch "$ADAPTER_LOG" 2>/dev/null || :
                chmod 600 "$ADAPTER_LOG" 2>/dev/null || :
            fi
        fi
    fi
    (
        umask 077
        printf '[%s] subcommand=%s output=%s pid=%s exit=%s status=%s' \
            "$(xdisplay_adapter_timestamp)" "$subcommand" "$output" "$$" "$exit_code" "$status"
        [ -n "$detail" ] && printf ' detail=%s' "$detail"
        printf '\n'
        if [ -n "$stderr_file" ] && [ -s "$stderr_file" ]; then
            printf 'stderr:\n'
            head -c 4096 "$stderr_file" | xdisplay_adapter_log_value | sed 's/^/  /'
        fi
    ) >> "$ADAPTER_LOG" 2>/dev/null || :
)

# Execute one device-local adapter command. stdout is returned to the caller;
# stderr, timeout state, and the exit code are persisted without blocking layout.
