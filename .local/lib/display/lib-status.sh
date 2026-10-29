# Read-only policy and status reporting.
# Functions: xdisplay_describe_policy, xdisplay_state_names,
# xdisplay_read_runtime_value, xdisplay_display_status.

xdisplay_describe_policy() {
    lid=$1
    outputs=$(xdisplay_connected_outputs)
    count=$(xdisplay_output_count "$outputs")
    if [ "$count" -eq 0 ]; then
        printf '%s\n' no-connected-output
        return
    fi

    internal=$(xdisplay_internal_output "$outputs")
    if [ "$count" -eq 1 ]; then
        if [ "$lid" = closed ] && [ "$outputs" = "$internal" ]; then
            printf '%s\n' preserve-closed-internal
        elif [ "$outputs" = "$internal" ] &&
            ! xdisplay_output_ready "$internal" && ! xdisplay_output_active "$internal"; then
            printf '%s\n' restore-internal-then-single
        else
            printf '%s\n' single-output
        fi
        return
    fi

    case "$lid" in
        closed)
            if [ -n "$internal" ]; then
                printf '%s\n' extend-externals-and-disable-internal
            else
                printf '%s\n' mirror-fallback
            fi
            ;;
        open|unknown|absent)
            if [ -n "$internal" ]; then
                printf '%s\n' extend-from-internal
            else
                printf '%s\n' mirror-fallback
            fi
            ;;
    esac
}

xdisplay_state_names() {
    field=$1
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v field="$field" '
            $1 == "output" && $field == 1 {
                if (found++) printf ","
                printf "%s", $2
            }
            END { if (!found) printf "none"; printf "\n" }
        '
}

xdisplay_read_runtime_value() {
    value_file=$1
    if [ ! -e "$value_file" ]; then
        printf '%s\n' absent
        return
    fi
    if [ ! -r "$value_file" ]; then
        printf '%s\n' unreadable
        return
    fi
    IFS= read -r runtime_value < "$value_file" || :
    [ -n "${runtime_value:-}" ] || runtime_value=empty
    printf '%s\n' "$runtime_value"
}

xdisplay_display_status() {
    xdisplay_read_lid_state
    xdisplay_read_snapshot --current || {
        xdisplay_notify_problem "Cannot read the current RandR state."
        return 1
    }

    if [ "$LID_PRESENT" -eq 1 ]; then
        lid_present=yes
    else
        lid_present=no
    fi
    printf 'lid_present=%s\n' "$lid_present"
    printf 'lid_state=%s\n' "$LID_STATE"
    printf 'state=%s internal=%s external=%s\n' \
        "$CURRENT_DISPLAY_STATE" "$CURRENT_DISPLAY_INTERNAL_COUNT" \
        "$CURRENT_DISPLAY_EXTERNAL_COUNT"
    printf 'layout=%s\n' "$CURRENT_LAYOUT_FUNCTION"
    if [ -n "$CUSTOM_LAYOUT_NAME" ]; then
        printf 'custom=%s\n' "$CUSTOM_LAYOUT_NAME"
    else
        printf 'custom=none\n'
    fi
    printf 'config: timeout=%s kill-after=%s position=%s limit=%s retry=%s probe=%s pending=%s log=%s log_max=%s\n' \
        "$CONFIG_TIMEOUT_SECONDS" "$CONFIG_KILL_AFTER_SECONDS" \
        "$CONFIG_EXTERNAL_POSITION" "$CONFIG_APPLY_FAILURE_LIMIT" \
        "$CONFIG_APPLY_RETRY_TICKS" "$CONFIG_HARDWARE_PROBE_TICKS" \
        "$CONFIG_PENDING_PROBE_TICKS" "$CONFIG_LOG_PATH" \
        "$CONFIG_LOG_MAX_BYTES"
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '
            $1 == "screen" {
                printf "screen=number:%s minimum:%sx%s current:%sx%s maximum:%sx%s\n",
                    $2, $3, $4, $5, $6, $7, $8
            }
            $1 == "output" {
                printf "output=%s connection:%s primary:%s geometry:%s width:%s height:%s x:%s y:%s mode_ready:%s first_mode:%s active:%s stale:%s pending:%s current_mode:%s current_rate:%s preferred_mode:%s preferred_rate:%s target_mode:%s target_rate:%s mode_count:%s mode_signature:%s\n",
                    $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
                    $13, $14, $15, $16, $17, $18,
                    ($23 != "-" ? $23 : $19),
                    ($24 != "-" ? $24 : $20), $21, $22
            }
        '

    stale_outputs=$(xdisplay_state_names 13)
    pending_outputs=$(xdisplay_state_names 14)
    if [ "$stale_outputs" != none ]; then
        health=stale
    elif [ "$pending_outputs" != none ]; then
        health=pending
    elif [ -z "$(xdisplay_connected_outputs)" ]; then
        health=no-connected-output
    else
        health=ready
    fi
    printf 'policy=%s\n' "$(xdisplay_describe_policy "$LID_STATE")"
    printf 'stale_outputs=%s\n' "$stale_outputs"
    printf 'pending_outputs=%s\n' "$pending_outputs"
    printf 'health=%s\n' "$health"
    printf 'topology_signature=%s:%s|%s\n' \
        "$LID_PRESENT" "$LID_STATE" "$(xdisplay_topology_signature)"
    printf 'display_server=%s\n' "$display_server"
    printf 'lock_apply=%s\n' "$apply_lock"
    printf 'lock_watch=%s\n' "$watch_lock"
    printf 'generation_path=%s\n' "$generation_file"
    current_generation=$(xdisplay_read_runtime_value "$generation_file")
    printf 'generation=%s\n' "$current_generation"
    printf 'manual_marker_path=%s\n' "$manual_marker"
    marker_value=$(xdisplay_read_runtime_value "$manual_marker")
    case "$marker_value:$current_generation" in
        absent:*|unreadable:*|empty:*) marker_state=$marker_value ;;
        *:absent|*:unreadable|*:empty) marker_state=stale ;;
        "$current_generation:$current_generation") marker_state=current ;;
        *) marker_state=stale ;;
    esac
    printf 'manual_marker=%s\n' "$marker_state"
    printf 'legacy_internal_outputs=%s\n' \
        "${XDISPLAY_INTERNAL_OUTPUTS:-none}"
    legacy_restore=${XDISPLAY_RESTORE_COMMAND:-}
    if [ -z "$legacy_restore" ]; then
        printf 'legacy_restore_command=none\n'
    elif command -v "$legacy_restore" >/dev/null 2>&1; then
        printf 'legacy_restore_command=%s (available)\n' "$legacy_restore"
    else
        printf 'legacy_restore_command=%s (unavailable)\n' "$legacy_restore"
    fi
}
