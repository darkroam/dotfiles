# Generic output positioning and chained extension mutations.
# Functions: xdisplay_set_output_primary_at_origin, xdisplay_output_relation,
# xdisplay_output_right_of, xdisplay_sort_external_outputs,
# xdisplay_first_output, xdisplay_apply_extend_layout.

xdisplay_set_output_primary_at_origin() {
    output=$1
    set -- --output "$output" --primary
    if ! xdisplay_output_at_target_mode "$output"; then
        target_mode=$(xdisplay_output_target_mode "$output")
        [ "$target_mode" != - ] || return 1
        set -- "$@" --mode "$target_mode"
        target_rate=$(xdisplay_output_target_rate "$output")
        [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
    fi
    set -- "$@" --pos 0x0
    xrandr "$@"
}

xdisplay_output_relation() {
    output=$1
    anchor=$2
    relation=$3
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$output" -v anchor="$anchor" -v relation="$relation" '
            $1 == "output" && ($2 == output || $2 == anchor) && $12 == 1 {
                if ($2 == output) {
                    output_x = $8
                    output_y = $9
                    output_width = $6
                    output_height = $7
                    have_output = 1
                } else {
                    anchor_width = $6
                    anchor_height = $7
                    anchor_x = $8
                    anchor_y = $9
                    have_anchor = 1
                }
            }
            END {
                if (!have_output || !have_anchor) exit 1
                if (relation == "right")
                    ok = output_x == anchor_x + anchor_width && output_y == anchor_y
                else if (relation == "left")
                    ok = output_x + output_width == anchor_x && output_y == anchor_y
                else if (relation == "above")
                    ok = output_y + output_height == anchor_y && output_x == anchor_x
                else if (relation == "below")
                    ok = output_y == anchor_y + anchor_height && output_x == anchor_x
                else
                    ok = 0
                exit !ok
            }
        '
}

xdisplay_output_right_of() {
    xdisplay_output_relation "$1" "$2" right
}

# Return external outputs in RandR connector order. A future configuration
# layer can replace this function without changing the layout callers.
xdisplay_sort_external_outputs() {
    requested=$1
    [ -n "$requested" ] || return 0
    connected=$(xdisplay_connected_outputs)
    for output in $connected; do
        xdisplay_output_in_list "$requested" "$output" || continue
        printf '%s\n' "$output"
    done
}

xdisplay_first_output() {
    printf '%s\n' "$1" | awk 'NF { print; exit }'
}

# Apply a primary plus a chained external layout in one RandR mutation.
# Each output is positioned relative to the previous output, preserving the
# existing target-mode and primary-selection helpers.
xdisplay_apply_extend_layout() {
    primary=$1
    outputs=$2
    direction=${3:-right}
    disable_output=${4:-}
    [ -n "$primary" ] || return 1
    case "$direction" in
        right) relation=--right-of ;;
        left) relation=--left-of ;;
        above) relation=--above ;;
        below) relation=--below ;;
        *) return 2 ;;
    esac

    set -- --output "$primary" --primary
    if ! xdisplay_output_at_target_mode "$primary"; then
        target_mode=$(xdisplay_output_target_mode "$primary")
        [ "$target_mode" != - ] || return 1
        set -- "$@" --mode "$target_mode"
        target_rate=$(xdisplay_output_target_rate "$primary")
        [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
    fi
    set -- "$@" --pos 0x0
    [ -n "$disable_output" ] &&
        set -- "$@" --output "$disable_output" --off

    anchor=$primary
    if [ "${XDISPLAY_LAYOUT_DRY_RUN:-0}" = 1 ]; then
        printf 'layout=extend_chain direction=%s\n' "$direction"
        printf 'primary=%s\n' "$primary"
    fi
    sorted=$(xdisplay_sort_external_outputs "$outputs" | tr '\n' ' ')
    old_ifs=$IFS
    IFS=' '
    for output in $sorted; do
        [ "$output" = "$primary" ] && continue
        set -- "$@" --output "$output"
        if ! xdisplay_output_at_target_mode "$output"; then
            target_mode=$(xdisplay_output_target_mode "$output")
            [ "$target_mode" != - ] || { IFS=$old_ifs; return 1; }
            set -- "$@" --mode "$target_mode"
            target_rate=$(xdisplay_output_target_rate "$output")
            [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
        fi
        if [ "${XDISPLAY_LAYOUT_DRY_RUN:-0}" = 1 ]; then
            printf 'output=%s relation=%s anchor=%s\n' "$output" \
                "$relation" "$anchor"
        fi
        set -- "$@" "$relation" "$anchor"
        anchor=$output
    done
    IFS=$old_ifs
    if [ "${XDISPLAY_LAYOUT_DRY_RUN:-0}" = 1 ]; then
        return 0
    fi
    xrandr "$@"
}

# Apply an absolute-position custom snapshot. Extra outputs allowed by a
# contains match are appended using the configured chain direction.
