# Output classification, topology signatures, and primary selection.
# Functions: xdisplay_verify_target_modes, xdisplay_topology_signature,
# xdisplay_internal_output, xdisplay_external_outputs,
# xdisplay_usable_outputs, xdisplay_choose_primary.

xdisplay_verify_target_modes() {
    old_ifs=$IFS
    IFS='
'
    for output in $1; do
        xdisplay_output_at_target_mode "$output" || {
            IFS=$old_ifs
            return 1
        }
    done
    IFS=$old_ifs
}

xdisplay_topology_signature() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '
            $1 == "output" { printf "%s:%s:%s:%s,", $2, $3, $11, $22 }
        '
    printf 'custom:%s:%s\n' "$CUSTOM_LAYOUT_NAME" "$CUSTOM_LAYOUT_MTIME"
}

xdisplay_internal_output() {
    outputs=$1
    standard_output=$(printf '%s\n' "$outputs" |
        awk '$1 ~ /^(eDP|LVDS|DSI)-?[0-9]/ { print; exit }')
    if [ -n "$standard_output" ]; then
        printf '%s\n' "$standard_output"
        return
    fi

    if [ -n "$ADAPTER_INTERNAL_OUTPUTS" ]; then
        printf '%s\n' "$ADAPTER_INTERNAL_OUTPUTS"
        return
    fi

    for candidate in ${XDISPLAY_INTERNAL_OUTPUTS:-}; do
        if xdisplay_output_in_list "$outputs" "$candidate"; then
            printf '%s\n' "$candidate"
            return
        fi
    done
}

xdisplay_external_outputs() {
    printf '%s\n' "$1" | awk -v internal="$2" '$1 != internal'
}

xdisplay_usable_outputs() {
    old_ifs=$IFS
    IFS='
'
    for output in $1; do
        if xdisplay_output_active "$output" || xdisplay_output_ready "$output"; then
            printf '%s\n' "$output"
        fi
    done
    IFS=$old_ifs
}

xdisplay_choose_primary() {
    outputs=$1
    old_ifs=$IFS
    IFS='
'
    for output in $outputs; do
        if xdisplay_output_primary "$output"; then
            printf '%s\n' "$output"
            IFS=$old_ifs
            return
        fi
    done
    for output in $outputs; do
        if xdisplay_output_active "$output"; then
            printf '%s\n' "$output"
            IFS=$old_ifs
            return
        fi
    done
    IFS=$old_ifs
    printf '%s\n' "$outputs" | awk 'NF { print; exit }'
}
