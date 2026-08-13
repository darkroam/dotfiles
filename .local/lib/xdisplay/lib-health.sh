# Snapshot health checks and stale-output cleanup.
# Functions: xdisplay_verify_active_outputs, xdisplay_snapshot_has_*,
# xdisplay_snapshot_health, xdisplay_clear_stale_outputs.

xdisplay_verify_active_outputs() {
    old_ifs=$IFS
    IFS='
'
    for output in $1; do
        xdisplay_output_active "$output" || {
            IFS=$old_ifs
            return 1
        }
    done
    IFS=$old_ifs
}

xdisplay_snapshot_has_pending_outputs() {
    lid=$1
    outputs=$(xdisplay_connected_outputs)
    internal=$(xdisplay_internal_output "$outputs")
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v lid="$lid" -v internal="$internal" '
            $1 == "output" && $14 == 1 &&
                !(lid == "closed" && $2 == internal) { found = 1 }
            END { exit !found }
        '
}

xdisplay_snapshot_has_stale_outputs() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '
            $1 == "output" && $13 == 1 { found = 1 }
            END { exit !found }
        '
}

xdisplay_snapshot_health() {
    lid=$1
    if xdisplay_snapshot_has_stale_outputs; then
        printf '%s\n' stale
    elif xdisplay_snapshot_has_pending_outputs "$lid"; then
        printf '%s\n' pending
    elif [ -z "$(xdisplay_connected_outputs)" ]; then
        printf '%s\n' no-connected-output
    else
        printf '%s\n' ready
    fi
}

xdisplay_clear_stale_outputs() {
    lid=$1
    stale_outputs=$(printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '$1 == "output" && $13 == 1 { print $2 }')
    [ -n "$stale_outputs" ] || return 0

    connected=$(xdisplay_connected_outputs)
    active_connected=$(printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '
            $1 == "output" && $3 == "connected" && $12 == 1 { print $2 }
        ')

    # Bring up and verify a replacement before removing the last framebuffer
    # anchor. With a closed lid, only an external output is a safe candidate.
    if [ -z "$active_connected" ]; then
        candidates=$connected
        internal=$(xdisplay_internal_output "$connected")
        if [ "$lid" = closed ] && [ -n "$internal" ]; then
            candidates=$(xdisplay_external_outputs "$connected" "$internal")
        fi
        candidates=$(xdisplay_usable_outputs "$candidates")
        [ -n "$candidates" ] || return 1
        replacement=$(xdisplay_choose_primary "$candidates")
        [ -n "$replacement" ] || return 1
        xdisplay_set_output_primary_at_origin "$replacement" || return 1
        xdisplay_read_snapshot --current || return 1
        xdisplay_output_active "$replacement" || return 1
    fi

    set --
    old_ifs=$IFS
    IFS='
'
    for output in $stale_outputs; do
        set -- "$@" --output "$output" --off
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    xdisplay_read_snapshot --current || return 1
    ! xdisplay_snapshot_has_stale_outputs
}
