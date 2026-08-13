# Bounded adapter subprocess execution.
# Function: xdisplay_run_adapter.

xdisplay_run_adapter() (
    subcommand=$1
    output=${2:-}

    [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] || return 127
    if [ ! -x "$ADAPTER_PATH" ]; then
        xdisplay_adapter_log_event "$subcommand" "${output:-none}" 127 UNAVAILABLE adapter_missing
        return 127
    fi
    if ! command -v timeout >/dev/null 2>&1 ||
        ! command -v mktemp >/dev/null 2>&1 ||
        ! command -v env >/dev/null 2>&1; then
        xdisplay_adapter_log_event "$subcommand" "${output:-none}" 127 UNAVAILABLE runtime_tools_missing
        return 127
    fi
    if [ -z "${DISPLAY:-}" ] || [ -z "${XAUTHORITY:-}" ] || [ -z "${PATH:-}" ]; then
        xdisplay_adapter_log_event "$subcommand" "${output:-none}" 127 UNAVAILABLE missing_session_environment
        return 127
    fi

    tmp_stderr=$(mktemp "${TMPDIR:-/tmp}/xdisplay-adapter-stderr.XXXXXX") || {
        xdisplay_adapter_log_event "$subcommand" "${output:-none}" 127 FAILURE temp_failed
        return 127
    }
    tmp_stdout=$(mktemp "${TMPDIR:-/tmp}/xdisplay-adapter-stdout.XXXXXX") || {
        rm -f "$tmp_stderr"
        xdisplay_adapter_log_event "$subcommand" "${output:-none}" 127 FAILURE temp_failed
        return 127
    }
    trap 'rm -f "$tmp_stderr" "$tmp_stdout"' 0

    start_time=$(date +%s%3N 2>/dev/null || date +%s000)
    if [ -n "$output" ]; then
        timeout --kill-after="$ADAPTER_KILLAFTER" "$ADAPTER_TIMEOUT" \
            env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" PATH="$PATH" \
            "$ADAPTER_PATH" "$subcommand" "$output" >"$tmp_stdout" 2>"$tmp_stderr"
    else
        timeout --kill-after="$ADAPTER_KILLAFTER" "$ADAPTER_TIMEOUT" \
            env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" PATH="$PATH" \
            "$ADAPTER_PATH" "$subcommand" >"$tmp_stdout" 2>"$tmp_stderr"
    fi
    exit_code=$?
    end_time=$(date +%s%3N 2>/dev/null || date +%s000)
    elapsed=$((end_time - start_time))ms
    status=SUCCESS
    if [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 137 ]; then
        status=TIMEOUT
    elif [ "$exit_code" -ne 0 ]; then
        status=FAILURE
    fi

    xdisplay_adapter_log_event "$subcommand" "${output:-none}" "$exit_code" "$status" \
        "elapsed=$elapsed" "$tmp_stderr"
    cat "$tmp_stdout"
    return "$exit_code"
)
