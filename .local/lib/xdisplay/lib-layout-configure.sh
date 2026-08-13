# State-specific single, open, closed, and mirror layout orchestration.
# Functions: xdisplay_configure_single, xdisplay_configure_closed,
# xdisplay_configure_open, xdisplay_configure_mirror.

xdisplay_configure_single() {
    output=$1
    if ! xdisplay_snapshot_has_stale_outputs &&
        xdisplay_output_active "$output" &&
        xdisplay_output_primary "$output" &&
        xdisplay_output_at_origin "$output" &&
        xdisplay_output_at_target_mode "$output"; then
        return 0
    fi

    xdisplay_output_active "$output" || xdisplay_output_ready "$output" || return 1
    xdisplay_set_output_primary_at_origin "$output" || return 1

    xdisplay_read_snapshot &&
        ! xdisplay_snapshot_has_stale_outputs &&
        xdisplay_output_active "$output" &&
        xdisplay_output_primary "$output" &&
        xdisplay_output_at_origin "$output" &&
        xdisplay_output_at_target_mode "$output"
}

xdisplay_configure_closed() {
    internal=$1
    externals=$(xdisplay_usable_outputs "$2")
    [ -n "$externals" ] || return 1
    sorted_externals=$(xdisplay_sort_external_outputs "$externals")
    if [ -n "$CUSTOM_LAYOUT_NAME" ] && [ "$CURRENT_DISPLAY_STATE" != "$STATE_NONE" ]; then
        xdisplay_apply_custom_layout "$internal" "$sorted_externals" closed || return 1
        xdisplay_read_snapshot || return 1
        if xdisplay_custom_layout_converged &&
            { [ -z "$internal" ] || ! xdisplay_output_active "$internal"; }; then
            return 0
        fi
        xdisplay_custom_layout_reset
    fi
    case "$CURRENT_DISPLAY_STATE" in
        EXTERNAL_ONLY|MULTI_EXTERNAL)
            if [ "$MULTI_SCREEN_LAYOUT_READY" -eq 1 ]; then
                externals=$sorted_externals
                primary=$(xdisplay_choose_layout_primary "$externals")
                layout_mode=extend_chain
            else
                primary=$(xdisplay_choose_primary "$externals")
                layout_mode=legacy
            fi
            ;;
        *)
            primary=$(xdisplay_choose_primary "$externals")
            layout_mode=legacy
            ;;
    esac
    [ -n "$primary" ] || return 1

    if [ "$layout_mode" = extend_chain ]; then
        # Keep an external primary active before applying the external chain
        # and internal-off transition in one RandR mutation.
        if ! xdisplay_snapshot_has_stale_outputs &&
            xdisplay_output_primary "$primary" &&
            xdisplay_output_at_origin "$primary" &&
            ! xdisplay_output_active "$internal" &&
            xdisplay_verify_active_outputs "$externals" &&
            xdisplay_verify_target_modes "$externals" &&
            xdisplay_outputs_extended_from_direction "$primary" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"; then
            return 0
        fi
        if ! xdisplay_output_active "$primary"; then
            xdisplay_output_ready "$primary" || return 1
            xdisplay_set_output_primary_at_origin "$primary" || return 1
            xdisplay_read_snapshot || return 1
            xdisplay_output_active "$primary" && xdisplay_output_at_target_mode "$primary" || return 1
        fi
        xdisplay_apply_extend_layout "$primary" "$externals" \
            "$CONFIG_EXTERNAL_POSITION" "$internal" || return 1
        xdisplay_read_snapshot || return 1
        ! xdisplay_snapshot_has_stale_outputs &&
            xdisplay_output_primary "$primary" &&
            xdisplay_output_at_origin "$primary" &&
            ! xdisplay_output_active "$internal" &&
            xdisplay_verify_active_outputs "$externals" &&
            xdisplay_verify_target_modes "$externals" &&
            xdisplay_outputs_extended_from_direction "$primary" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"
        return
    fi

    if ! xdisplay_snapshot_has_stale_outputs &&
        xdisplay_output_primary "$primary" &&
        xdisplay_output_at_origin "$primary" &&
        ! xdisplay_output_active "$internal" &&
        xdisplay_verify_active_outputs "$externals" &&
        xdisplay_verify_target_modes "$externals" &&
            xdisplay_outputs_extended_from_direction "$primary" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"; then
        return 0
    fi

    # If the external primary is not active yet, prepare it before turning off
    # the internal panel. This keeps a usable screen alive during link training.
    if ! xdisplay_output_active "$primary"; then
        xdisplay_output_ready "$primary" || return 1
        xdisplay_set_output_primary_at_origin "$primary" || return 1
        xdisplay_read_snapshot || return 1
        xdisplay_output_active "$primary" && xdisplay_output_at_target_mode "$primary" || return 1
    fi

    set -- --output "$primary" --primary
    if ! xdisplay_output_at_target_mode "$primary"; then
        target_mode=$(xdisplay_output_target_mode "$primary")
        [ "$target_mode" != - ] || return 1
        set -- "$@" --mode "$target_mode"
        target_rate=$(xdisplay_output_target_rate "$primary")
        [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
    fi
    set -- "$@" --pos 0x0 --output "$internal" --off
    anchor=$primary
    old_ifs=$IFS
    IFS='
'
    for output in $externals; do
        [ "$output" = "$primary" ] && continue
        set -- "$@" --output "$output"
        if ! xdisplay_output_at_target_mode "$output"; then
            target_mode=$(xdisplay_output_target_mode "$output")
            [ "$target_mode" != - ] || { IFS=$old_ifs; return 1; }
            set -- "$@" --mode "$target_mode"
            target_rate=$(xdisplay_output_target_rate "$output")
            [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
        fi
        set -- "$@" "--${CONFIG_EXTERNAL_POSITION}-of" "$anchor"
        anchor=$output
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    xdisplay_read_snapshot || return 1
    ! xdisplay_snapshot_has_stale_outputs &&
        xdisplay_output_primary "$primary" &&
        xdisplay_output_at_origin "$primary" &&
        ! xdisplay_output_active "$internal" &&
        xdisplay_verify_active_outputs "$externals" &&
        xdisplay_verify_target_modes "$externals" &&
            xdisplay_outputs_extended_from_direction "$primary" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"
}

xdisplay_configure_open() {
    internal=$1
    externals=$(xdisplay_usable_outputs "$2")
    sorted_externals=$(xdisplay_sort_external_outputs "$externals")
    layout_mode=legacy
    case "$CURRENT_DISPLAY_STATE" in
        DUAL_EXTEND|MULTI_EXTEND)
            if [ "$MULTI_SCREEN_LAYOUT_READY" -eq 1 ]; then
                externals=$sorted_externals
                layout_mode=extend_chain
            fi
            ;;
    esac

    if xdisplay_adapter_expected_mode_missing "$internal"; then
        xdisplay_recover_or_degrade_adapter_target "$internal" || return 1
    fi

    if [ -n "$CUSTOM_LAYOUT_NAME" ] && [ "$CURRENT_DISPLAY_STATE" != "$STATE_NONE" ]; then
        xdisplay_apply_custom_layout "$internal" "$sorted_externals" open || return 1
        xdisplay_read_snapshot || return 1
        if xdisplay_custom_layout_converged; then
            return 0
        fi
        # A stale custom snapshot must not strand the display; the caller's
        # existing retry path will re-read RandR and use the default planner.
        xdisplay_custom_layout_reset
        layout_mode=legacy
    fi

    if ! xdisplay_snapshot_has_stale_outputs &&
        xdisplay_output_primary "$internal" &&
        xdisplay_output_active "$internal" &&
        xdisplay_output_at_origin "$internal" &&
        xdisplay_verify_active_outputs "$externals" &&
        xdisplay_output_at_target_mode "$internal" &&
        xdisplay_verify_target_modes "$externals" &&
        xdisplay_outputs_extended_from_direction "$internal" "$externals" \
            "$CONFIG_EXTERNAL_POSITION"; then
        return 0
    fi

    if ! xdisplay_output_active "$internal"; then
        if ! xdisplay_output_ready "$internal"; then
            if xdisplay_adapter_expected_mode_missing "$internal" &&
                [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] && [ -x "$ADAPTER_PATH" ] &&
                xdisplay_try_adapter_restore "$internal"; then
                :
            else
                xdisplay_try_internal_restore "$internal"
                return 1
            fi
        fi
        xdisplay_set_output_primary_at_origin "$internal" || return 1
        xdisplay_read_snapshot || return 1
        xdisplay_output_active "$internal" && xdisplay_output_at_target_mode "$internal" || return 1
    fi

    if [ "$layout_mode" = extend_chain ]; then
        xdisplay_apply_extend_layout "$internal" "$externals" \
            "$CONFIG_EXTERNAL_POSITION" || return 1
        xdisplay_read_snapshot || return 1
        ! xdisplay_snapshot_has_stale_outputs &&
            xdisplay_output_primary "$internal" &&
            xdisplay_output_active "$internal" &&
            xdisplay_output_at_origin "$internal" &&
            xdisplay_verify_active_outputs "$externals" &&
            xdisplay_output_at_target_mode "$internal" &&
            xdisplay_verify_target_modes "$externals" &&
            xdisplay_outputs_extended_from_direction "$internal" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"
        return
    fi

    set -- --output "$internal" --primary
    if ! xdisplay_output_at_target_mode "$internal"; then
        target_mode=$(xdisplay_output_target_mode "$internal")
        [ "$target_mode" != - ] || return 1
        set -- "$@" --mode "$target_mode"
        target_rate=$(xdisplay_output_target_rate "$internal")
        [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
    fi
    set -- "$@" --pos 0x0
    anchor=$internal
    old_ifs=$IFS
    IFS='
'
    for output in $externals; do
        set -- "$@" --output "$output"
        if ! xdisplay_output_at_target_mode "$output"; then
            target_mode=$(xdisplay_output_target_mode "$output")
            [ "$target_mode" != - ] || { IFS=$old_ifs; return 1; }
            set -- "$@" --mode "$target_mode"
            target_rate=$(xdisplay_output_target_rate "$output")
            [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
        fi
        set -- "$@" "--${CONFIG_EXTERNAL_POSITION}-of" "$anchor"
        anchor=$output
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    xdisplay_read_snapshot || return 1
    ! xdisplay_snapshot_has_stale_outputs &&
        xdisplay_output_primary "$internal" &&
        xdisplay_output_active "$internal" &&
        xdisplay_output_at_origin "$internal" &&
        xdisplay_verify_active_outputs "$externals" &&
        xdisplay_output_at_target_mode "$internal" &&
            xdisplay_verify_target_modes "$externals" &&
            xdisplay_outputs_extended_from_direction "$internal" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"
}

xdisplay_configure_mirror() {
    outputs=$(xdisplay_usable_outputs "$1")
    count=$(xdisplay_output_count "$outputs")
    [ "$count" -gt 0 ] || return 1
    [ "$count" -gt 1 ] || { xdisplay_configure_single "$outputs"; return; }

    primary=$(xdisplay_choose_primary "$outputs")
    if ! xdisplay_snapshot_has_stale_outputs &&
        xdisplay_output_primary "$primary" &&
        xdisplay_output_at_origin "$primary" &&
        xdisplay_verify_active_outputs "$outputs" &&
        xdisplay_verify_target_modes "$outputs" &&
        xdisplay_outputs_mirrored "$primary" "$outputs"; then
        return 0
    fi

    set -- --output "$primary" --primary
    if ! xdisplay_output_at_target_mode "$primary"; then
        target_mode=$(xdisplay_output_target_mode "$primary")
        [ "$target_mode" != - ] || return 1
        set -- "$@" --mode "$target_mode"
        target_rate=$(xdisplay_output_target_rate "$primary")
        [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
    fi
    set -- "$@" --pos 0x0

    old_ifs=$IFS
    IFS='
'
    for output in $outputs; do
        [ "$output" = "$primary" ] && continue
        set -- "$@" --output "$output"
        if ! xdisplay_output_at_target_mode "$output"; then
            target_mode=$(xdisplay_output_target_mode "$output")
            [ "$target_mode" != - ] || { IFS=$old_ifs; return 1; }
            set -- "$@" --mode "$target_mode"
            target_rate=$(xdisplay_output_target_rate "$output")
            [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
        fi
        set -- "$@" --same-as "$primary"
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    xdisplay_read_snapshot || return 1
    ! xdisplay_snapshot_has_stale_outputs &&
        xdisplay_output_primary "$primary" &&
        xdisplay_output_at_origin "$primary" &&
        xdisplay_verify_active_outputs "$outputs" &&
        xdisplay_verify_target_modes "$outputs" &&
        xdisplay_outputs_mirrored "$primary" "$outputs"
}
