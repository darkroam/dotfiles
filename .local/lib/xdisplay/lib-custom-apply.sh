# Custom-layout mutation and convergence validation.
# Functions: xdisplay_apply_custom_layout, xdisplay_custom_output_at_saved_*,
# xdisplay_custom_layout_converged.

xdisplay_apply_custom_layout() {
    internal=$1
    externals=$2
    lid=${3:-open}
    [ -n "$CUSTOM_LAYOUT_NAME" ] || return 1
    primary=$CUSTOM_LAYOUT_PRIMARY
    [ -n "$primary" ] || return 1
    connected=$(xdisplay_connected_outputs)
    xdisplay_output_in_list "$connected" "$primary" || return 1

    set --
    configured_outputs=$CUSTOM_LAYOUT_ORDER
    [ -n "$configured_outputs" ] || configured_outputs=$primary
    old_ifs=$IFS
    IFS='
'
    for output in $configured_outputs; do
        [ -n "$output" ] || continue
        xdisplay_output_in_list "$connected" "$output" || continue
        position_line=$(printf '%s\n' "$CUSTOM_LAYOUT_POSITIONS" |
            awk -F '\|' -v output="$output" '$1 == output { print; exit }')
        [ -n "$position_line" ] || continue
        saved_x=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $2 }')
        saved_y=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $3 }')
        saved_mode=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $4 }')
        saved_rate=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $5 }')
        [ -n "$saved_rate" ] || saved_rate=-
        xdisplay_custom_valid_position_value "$saved_x" || { IFS=$old_ifs; return 1; }
        xdisplay_custom_valid_position_value "$saved_y" || { IFS=$old_ifs; return 1; }
        xdisplay_custom_valid_mode_value "$saved_mode" || { IFS=$old_ifs; return 1; }
        xdisplay_custom_valid_rate_value "$saved_rate" || { IFS=$old_ifs; return 1; }
        set -- "$@" --output "$output"
        [ "$saved_mode" = - ] || set -- "$@" --mode "$saved_mode"
        [ "$saved_rate" = - ] || set -- "$@" --rate "$saved_rate"
        set -- "$@" --pos "${saved_x}x${saved_y}"
        [ "$output" = "$primary" ] && set -- "$@" --primary
        if [ "${XDISPLAY_LAYOUT_DRY_RUN:-0}" = 1 ]; then
            custom_primary_suffix=
            [ "$output" = "$primary" ] && custom_primary_suffix=' primary'
            printf 'custom_output=%s pos=%sx%s mode=%s rate=%s%s\n' \
                "$output" "$saved_x" "$saved_y" "$saved_mode" "$saved_rate" \
                "$custom_primary_suffix"
        fi
    done
    IFS=$old_ifs

    # Add outputs not recorded by a contains snapshot without hiding them.
    anchor=$primary
    for configured_output in $configured_outputs; do
        xdisplay_output_in_list "$connected" "$configured_output" || continue
        anchor=$configured_output
    done
    for output in $(xdisplay_sort_external_outputs "$externals"); do
        printf '%s\n' "$configured_outputs" | grep -qxF "$output" && continue
        set -- "$@" --output "$output" --auto "--${CONFIG_EXTERNAL_POSITION}-of" "$anchor"
        if [ "${XDISPLAY_LAYOUT_DRY_RUN:-0}" = 1 ]; then
            printf 'custom_extra=%s relation=--%s-of anchor=%s\n' "$output" \
                "$CONFIG_EXTERNAL_POSITION" "$anchor"
        fi
        anchor=$output
    done
    if [ "$lid" = closed ] && [ -n "$internal" ] && [ "$internal" != "$primary" ]; then
        set -- "$@" --output "$internal" --off
    fi
    [ "$#" -gt 0 ] || return 1
    if [ "${XDISPLAY_LAYOUT_DRY_RUN:-0}" = 1 ]; then
        printf 'layout=custom name=%s\n' "$CUSTOM_LAYOUT_NAME"
        printf 'custom_primary=%s\n' "$primary"
        return 0
    fi
    xrandr "$@"
}

xdisplay_custom_output_at_saved_position() {
    output=$1
    position_line=$(printf '%s\n' "$CUSTOM_LAYOUT_POSITIONS" |
        awk -F '\|' -v output="$output" '$1 == output { print; exit }')
    [ -n "$position_line" ] || return 0
    saved_x=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $2 }')
    saved_y=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $3 }')
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$output" -v x="$saved_x" -v y="$saved_y" '
            $1 == "output" && $2 == output && $12 == 1 &&
                ($8 + 0) == (x + 0) && ($9 + 0) == (y + 0) { found = 1 }
            END { exit !found }
        '
}

xdisplay_custom_output_at_saved_mode() {
    output=$1
    position_line=$(printf '%s\n' "$CUSTOM_LAYOUT_POSITIONS" |
        awk -F '\|' -v output="$output" '$1 == output { print; exit }')
    [ -n "$position_line" ] || return 0
    saved_mode=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $4 }')
    saved_rate=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $5 }')
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$output" -v mode="$saved_mode" -v rate="$saved_rate" '
            $1 == "output" && $2 == output && $12 == 1 && $15 == mode &&
                (rate == "-" || ($16 + 0) == (rate + 0)) { found = 1 }
            END { exit !found }
        '
}

xdisplay_custom_layout_converged() {
    [ -n "$CUSTOM_LAYOUT_NAME" ] || return 1
    old_ifs=$IFS
    IFS='
'
    for output in $CUSTOM_LAYOUT_ORDER; do
        [ -n "$output" ] || continue
        xdisplay_output_active "$output" || { IFS=$old_ifs; return 1; }
        xdisplay_custom_output_at_saved_mode "$output" || { IFS=$old_ifs; return 1; }
        xdisplay_custom_output_at_saved_position "$output" || { IFS=$old_ifs; return 1; }
    done
    IFS=$old_ifs
    xdisplay_output_primary "$CUSTOM_LAYOUT_PRIMARY" || return 1
    return 0
}
