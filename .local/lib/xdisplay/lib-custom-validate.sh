# Custom-layout field and position-record validation.
# Functions: xdisplay_custom_valid_*, xdisplay_custom_validate_position_record,
# xdisplay_custom_current_outputs.

xdisplay_custom_valid_output_name() {
    printf '%s\n' "$1" | LC_ALL=C awk '$0 ~ /^[^[:space:][:cntrl:],|]+$/ { ok=1 } END { exit !ok }'
}

xdisplay_custom_valid_position_value() {
    printf '%s\n' "$1" | LC_ALL=C awk '$0 ~ /^-?[0-9]+$/ { ok=1 } END { exit !ok }'
}

xdisplay_custom_valid_mode_value() {
    printf '%s\n' "$1" | LC_ALL=C awk '$0 ~ /^[1-9][0-9]*x[1-9][0-9]*$/ { ok=1 } END { exit !ok }'
}

xdisplay_custom_valid_rate_value() {
    [ "$1" = - ] || printf '%s\n' "$1" | LC_ALL=C awk '$0 ~ /^[1-9][0-9]*(\.[0-9]+)?$/ { ok=1 } END { exit !ok }'
}

xdisplay_custom_validate_position_record() {
    record=$1
    old_ifs=$IFS
    IFS='|'
    read -r record_output record_x record_y record_mode record_rate <<EOF
$record
EOF
    IFS=$old_ifs
    [ -n "$record_output" ] || return 1
    xdisplay_custom_valid_output_name "$record_output" || return 1
    xdisplay_custom_valid_position_value "$record_x" || return 1
    xdisplay_custom_valid_position_value "$record_y" || return 1
    xdisplay_custom_valid_mode_value "$record_mode" || return 1
    xdisplay_custom_valid_rate_value "${record_rate:--}"
}

xdisplay_custom_current_outputs() {
    # Identity is based on connected outputs, except that a closed lid omits
    # the physically connected but intentionally disabled internal panel.
    connected=$(xdisplay_connected_outputs)
    if [ "${1:-unknown}" = closed ]; then
        internal=$(xdisplay_internal_output "$connected")
        printf '%s\n' "$connected" | awk -v internal="$internal" '$1 != internal'
    else
        printf '%s\n' "$connected"
    fi
}
