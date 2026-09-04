# Apply transactions and watcher retry scheduling.
# Functions: xdisplay_apply_snapshot, xdisplay_apply_display_config,
# xdisplay_watch_cleanup, xdisplay_start_watch_generation,
# xdisplay_watch_displays.

xdisplay_apply_snapshot() {
    lid=$1
    # Bound adapter mutation to one attempt per layout transaction. A later
    # watcher cycle may retry after the existing failure cooldown.
    ADAPTER_RESTORE_ATTEMPTED=0
    xdisplay_clear_stale_outputs "$lid" || return 1
    outputs=$(xdisplay_connected_outputs)
    count=$(xdisplay_output_count "$outputs")
    [ "$count" -gt 0 ] || return 1
    internal=$(xdisplay_internal_output "$outputs")

    if [ "$count" -eq 1 ]; then
        if [ "$lid" = closed ] && [ "$outputs" = "$internal" ]; then
            ! xdisplay_snapshot_has_stale_outputs
            return
        fi
        if [ -n "$CUSTOM_LAYOUT_NAME" ] && [ "$CURRENT_DISPLAY_STATE" != "$STATE_NONE" ]; then
            xdisplay_apply_custom_layout "$internal" "$outputs" "$lid" || return 1
            xdisplay_read_snapshot || return 1
            xdisplay_custom_layout_converged || return 1
            return 0
        fi
        if [ "$lid" = closed ] &&
            [ "$CURRENT_DISPLAY_STATE" = EXTERNAL_ONLY ]; then
            xdisplay_configure_closed "$internal" \
                "$(xdisplay_external_outputs "$outputs" "$internal")"
            return
        fi
        if [ "$outputs" = "$internal" ] &&
            xdisplay_adapter_expected_mode_missing "$internal"; then
            xdisplay_recover_or_degrade_adapter_target "$internal" || return 1
        fi
        if [ "$outputs" = "$internal" ] && ! xdisplay_output_ready "$internal" &&
            ! xdisplay_output_active "$internal"; then
            if xdisplay_adapter_expected_mode_missing "$internal" &&
                [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] && [ -x "$ADAPTER_PATH" ] &&
                xdisplay_try_adapter_restore "$internal"; then
                :
            else
                xdisplay_try_internal_restore "$internal"
                return 1
            fi
        fi
        xdisplay_configure_single "$outputs"
        return
    fi

    case "$lid" in
        closed)
            case "$CURRENT_DISPLAY_STATE" in
                EXTERNAL_ONLY|MULTI_EXTERNAL)
                    xdisplay_configure_closed "$internal" \
                        "$(xdisplay_external_outputs "$outputs" "$internal")"
                    ;;
                *)
                    if [ -n "$internal" ]; then
                        xdisplay_configure_closed "$internal" \
                            "$(xdisplay_external_outputs "$outputs" "$internal")"
                    else
                        xdisplay_configure_mirror "$outputs"
                    fi
                    ;;
            esac
            ;;
        open|unknown|absent)
            if [ -n "$internal" ]; then
                xdisplay_configure_open "$internal" "$(xdisplay_external_outputs "$outputs" "$internal")"
            else
                xdisplay_configure_mirror "$outputs"
            fi
            ;;
    esac
}

xdisplay_apply_display_config() {
    lid=$1
    flock -n 8 || return 75
    xdisplay_apply_snapshot "$lid"
    result=$?
    flock -u 8
    return "$result"
}

xdisplay_watch_cleanup() {
    cleanup_result=$?
    trap - 0 1 2 15

    if [ -n "${watch_generation:-}" ] && [ -r "$generation_file" ]; then
        IFS= read -r stored_generation < "$generation_file" || :
        if [ "$stored_generation" = "$watch_generation" ]; then
            rm -f "$generation_file"
        fi
    fi
    flock -u 9 2>/dev/null || :
    return "$cleanup_result"
}

xdisplay_start_watch_generation() {
    watch_generation=$user_id-$$
    generation_temp=$generation_file.tmp.$$

    # A manual marker can only belong to the watcher generation that created
    # it. Stage 2 does not write markers yet, but it invalidates old sessions.
    rm -f "$manual_marker" || return 1
    old_umask=$(umask)
    umask 077
    if ! printf '%s\n' "$watch_generation" > "$generation_temp" ||
        ! mv "$generation_temp" "$generation_file"; then
        rm -f "$generation_temp"
        umask "$old_umask"
        return 1
    fi
    umask "$old_umask"
}

xdisplay_watch_displays() {
    exec 9>"$watch_lock" || return 1
    if ! flock -w "$WATCH_LOCK_WAIT" 9; then
        printf '%s\n' "xdisplay watcher is already running." >&2
        return 0
    fi

    trap 'xdisplay_watch_cleanup' 0
    trap 'exit 129' 1
    trap 'exit 130' 2
    trap 'exit 143' 15
    if ! xdisplay_start_watch_generation; then
        printf '%s\n' "Cannot initialize the xdisplay watcher generation." >&2
        return 1
    fi

    observed_lid=
    observed_drm=
    observed_key=
    observed_health=
    applied_key=
    applied_health=
    apply_failure_state=
    apply_failures=0
    apply_retry_ticks=0
    poll_ticks=0
    fast_checks=0
    hardware_probe_ticks=$HARDWARE_PROBE_TICKS
    pending_outputs=0
    probe_pending=0
    snapshot_failures=0
    authoritative_parsed=
    authoritative_connections=
    startup_gate_key=
    startup_gate_stable_ticks=0
    startup_gate_ticks=0
    startup_gate_open=0

    while :; do
        xdisplay_read_lid_state
        current_lid=$LID_STATE
        current_drm=$(xdisplay_drm_signature)
        force_probe=$probe_pending
        lid_closing=0
        if [ "$current_lid" != "$observed_lid" ]; then
            if [ "$observed_lid" = open ] && [ "$current_lid" = closed ]; then
                lid_closing=1
            fi
            fast_checks=$FAST_WINDOW_CHECKS
            poll_ticks=0
        fi
        if [ "$current_drm" != "$observed_drm" ]; then
            force_probe=1
            probe_pending=1
            fast_checks=$FAST_WINDOW_CHECKS
            poll_ticks=0
        fi

        if [ "$poll_ticks" -le 0 ]; then
            snapshot_option=--current
            pending_layout=0
            if { [ "$observed_key" != "$applied_key" ] ||
                [ "$observed_health" != "$applied_health" ]; } &&
                [ "$apply_failures" -lt "$APPLY_FAILURE_LIMIT" ]; then
                pending_layout=1
            elif [ "$pending_outputs" -eq 1 ] &&
                [ "$apply_failures" -lt "$APPLY_FAILURE_LIMIT" ]; then
                pending_layout=1
            fi
            if [ "$lid_closing" -eq 0 ]; then
                if [ "$force_probe" -eq 1 ] ||
                    [ "$hardware_probe_ticks" -ge "$HARDWARE_PROBE_TICKS" ] ||
                    { [ "$pending_layout" -eq 1 ] &&
                        [ "$hardware_probe_ticks" -ge "$PENDING_PROBE_TICKS" ]; } ||
                    { [ "$fast_checks" -gt 0 ] &&
                        [ $((fast_checks % FAST_QUERY_INTERVAL)) -eq 0 ]; }; then
                    snapshot_option=--query
                    hardware_probe_ticks=0
                fi
            fi
            if xdisplay_read_snapshot "$snapshot_option"; then
                snapshot_failures=0
                [ "$snapshot_option" = --query ] && probe_pending=0
                current_connections=$(xdisplay_connection_signature)
                normalized_snapshot=1
                if [ "$snapshot_option" = --query ]; then
                    authoritative_parsed=$XRANDR_PARSED
                    authoritative_connections=$current_connections
                elif [ -n "$authoritative_parsed" ] &&
                    [ "$current_connections" = "$authoritative_connections" ]; then
                    XRANDR_PARSED=$authoritative_parsed
                    xdisplay_refresh_display_state "$current_lid"
                else
                    # A cached snapshot may reveal a real hotplug, but its
                    # capability list is not authoritative. Defer layout work
                    # until the forced probe on the next watcher tick.
                    authoritative_parsed=
                    authoritative_connections=$current_connections
                    probe_pending=1
                    fast_checks=$FAST_WINDOW_CHECKS
                    poll_ticks=0
                    normalized_snapshot=0
                fi
                current_key=$LID_PRESENT:$current_lid\|$(xdisplay_topology_signature)
                current_health=$(xdisplay_snapshot_health "$current_lid")
                current_state=$current_key\|health:$current_health
                if [ "$current_key" != "$observed_key" ] ||
                    [ "$current_health" != "$observed_health" ]; then
                    observed_key=$current_key
                    observed_health=$current_health
                    fast_checks=$FAST_WINDOW_CHECKS
                fi
                if [ "$current_state" != "$apply_failure_state" ]; then
                    apply_failure_state=$current_state
                    apply_failures=0
                    apply_retry_ticks=0
                fi
                apply_due=0
                if [ "$apply_retry_ticks" -le 0 ]; then
                    if [ "$apply_failures" -lt "$APPLY_FAILURE_LIMIT" ] ||
                        [ "$snapshot_option" = --query ]; then
                        apply_due=1
                    fi
                fi
                if [ "$startup_gate_open" -eq 0 ]; then
                    startup_gate_ticks=$((startup_gate_ticks + 1))
                    if [ "$normalized_snapshot" -eq 1 ] &&
                        [ "$current_key" = "$startup_gate_key" ]; then
                        startup_gate_stable_ticks=$((startup_gate_stable_ticks + 1))
                    else
                        startup_gate_key=$current_key
                        startup_gate_stable_ticks=1
                    fi
                    if [ "$startup_gate_ticks" -ge "$STARTUP_GATE_MAX_TICKS" ] ||
                        { [ "$normalized_snapshot" -eq 1 ] &&
                            [ "$startup_gate_stable_ticks" -ge "$STARTUP_GATE_STABLE_TICKS" ] &&
                            xdisplay_outputs_preferred_ready "$CURRENT_EXTERNAL_OUTPUTS"; }; then
                        startup_gate_open=1
                    else
                        apply_due=0
                    fi
                elif [ "$normalized_snapshot" -eq 0 ]; then
                    apply_due=0
                fi
                if { [ "$current_key" != "$applied_key" ] ||
                    [ "$current_health" != "$applied_health" ]; } &&
                    [ "$apply_due" -eq 1 ]; then
                    if xdisplay_apply_display_config "$current_lid"; then
                        applied_connections=$(xdisplay_connection_signature)
                        post_apply_key=$current_key
                        if [ "$applied_connections" = "$current_connections" ]; then
                            applied_key=$current_key
                        else
                            # Keep the pre-transaction key as the applied
                            # generation, while observing the new projection.
                            # The forced probe will then plan that generation.
                            applied_key=$current_key
                            post_apply_key=$LID_PRESENT:$current_lid\|$(xdisplay_topology_signature)
                            authoritative_parsed=
                            authoritative_connections=$applied_connections
                            probe_pending=1
                        fi
                        applied_health=$(xdisplay_snapshot_health "$current_lid")
                        observed_key=$post_apply_key
                        observed_health=$applied_health
                        apply_failure_state=$post_apply_key\|health:$applied_health
                        apply_failures=0
                        apply_retry_ticks=0
                        if xdisplay_snapshot_has_pending_outputs "$current_lid"; then
                            pending_outputs=1
                        else
                            pending_outputs=0
                            hardware_probe_ticks=0
                        fi
                    else
                        apply_result=$?
                        if [ "$apply_result" -ne 75 ] &&
                            [ "$apply_failures" -lt "$APPLY_FAILURE_LIMIT" ]; then
                            apply_failures=$((apply_failures + 1))
                        fi
                        apply_retry_ticks=$APPLY_RETRY_TICKS
                    fi
                fi
            else
                snapshot_failures=$((snapshot_failures + 1))
                if [ "$snapshot_failures" -ge "$SNAPSHOT_FAILURE_LIMIT" ]; then
                    printf '%s\n' \
                        "RandR snapshot failed $snapshot_failures consecutive times; exiting watcher." >&2
                    return 1
                fi
            fi

            if [ "$fast_checks" -gt 0 ]; then
                fast_checks=$((fast_checks - 1))
                poll_ticks=0
            else
                poll_ticks=$STABLE_POLL_TICKS
            fi
        else
            poll_ticks=$((poll_ticks - 1))
        fi

        observed_lid=$current_lid
        observed_drm=$current_drm
        hardware_probe_ticks=$((hardware_probe_ticks + 1))
        if [ "$apply_retry_ticks" -gt 0 ]; then
            apply_retry_ticks=$((apply_retry_ticks - 1))
        fi
        sleep 0.5
    done
}
