# Adapter/legacy recovery orchestration and graceful degradation.
# Functions: xdisplay_try_internal_restore, xdisplay_try_adapter_restore,
# xdisplay_adapter_expected_mode_missing,
# xdisplay_recover_or_degrade_adapter_target.

xdisplay_try_internal_restore() {
    output=$1
    restore_command=${XDISPLAY_RESTORE_COMMAND:-}
    [ -n "$restore_command" ] || return 1
    command -v "$restore_command" >/dev/null 2>&1 || return 1
    command -v timeout >/dev/null 2>&1 || return 1
    timeout "$ADAPTER_TIMEOUT" "$restore_command" "$output" >/dev/null 2>&1 || true
    xdisplay_read_snapshot &&
        { xdisplay_output_ready "$output" || xdisplay_output_active "$output"; }
}

xdisplay_try_adapter_restore() {
    output=$1
    [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] || return 127
    [ -x "$ADAPTER_PATH" ] || return 127
    [ "$ADAPTER_RESTORE_ATTEMPTED" -eq 0 ] || return 1
    ADAPTER_RESTORE_ATTEMPTED=1
    if [ "$ADAPTER_EXPECTED_VALID" -eq 1 ] &&
        [ "$ADAPTER_EXPECTED_PRESENT" -eq 1 ]; then
        return 1
    fi

    xdisplay_run_adapter restore-internal "$output" >/dev/null || return 1
    xdisplay_read_snapshot || return 1
    if [ "$ADAPTER_EXPECTED_VALID" -eq 1 ]; then
        [ "$ADAPTER_EXPECTED_OUTPUT" = "$output" ] &&
            [ "$ADAPTER_EXPECTED_PRESENT" -eq 1 ]
    else
        xdisplay_output_ready "$output" || xdisplay_output_active "$output"
    fi
}

xdisplay_adapter_expected_mode_missing() {
    [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] || return 1
    [ "$ADAPTER_EXPECTED_VALID" -eq 1 ] || return 1
    [ "$ADAPTER_EXPECTED_PRESENT" -eq 0 ]
}

xdisplay_recover_or_degrade_adapter_target() {
    output=$1
    xdisplay_adapter_expected_mode_missing || return 0
    xdisplay_try_adapter_restore "$output" && return 0
    # Preserve the legacy recovery hook as the next compatibility fallback
    # when the explicitly enabled adapter cannot converge the expected mode.
    xdisplay_try_internal_restore "$output" || :
    if [ "$ADAPTER_EXPECTED_OUTPUT" = "$output" ] &&
        [ "$ADAPTER_EXPECTED_PRESENT" -eq 1 ]; then
        return 0
    fi
    xdisplay_output_ready "$output" || return 1
    ADAPTER_EXPECTED_VALID=0
    ADAPTER_EXPECTED_PRESENT=0
    xdisplay_adapter_log_event expected-mode "$output" 0 FALLBACK randr_preferred
    return 0
}
