# Connected-output lists and read-only display-state calculation.
# Functions: xdisplay_connected_outputs, xdisplay_all_outputs,
# xdisplay_output_count, xdisplay_compute_display_state,
# xdisplay_display_*_outputs, xdisplay_refresh_display_state.

xdisplay_connected_outputs() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '$1 == "output" && $3 == "connected" { print $2 }'
}

xdisplay_all_outputs() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '$1 == "output" { print $2 }'
}

xdisplay_output_count() {
    printf '%s\n' "$1" |
        awk 'NF { count++ } END { print count + 0 }'
}

xdisplay_compute_display_state() {
    state_lid=$1
    state_internal_outputs=$2
    state_external_outputs=$3
    state_internal_count=$(xdisplay_output_count "$state_internal_outputs")
    state_external_count=$(xdisplay_output_count "$state_external_outputs")

    # A closed lid makes the internal panel unavailable to the effective
    # layout state, while retaining the physical list for diagnostics.
    case "$state_lid" in
        closed) state_effective_internal_count=0 ;;
        *) state_effective_internal_count=$state_internal_count ;;
    esac

    if [ "$state_effective_internal_count" -eq 0 ]; then
        if [ "$state_external_count" -eq 0 ]; then
            CURRENT_DISPLAY_STATE=$STATE_NONE
        elif [ "$state_external_count" -eq 1 ]; then
            CURRENT_DISPLAY_STATE=$STATE_EXTERNAL_ONLY
        else
            CURRENT_DISPLAY_STATE=$STATE_MULTI_EXTERNAL
        fi
    elif [ "$state_external_count" -eq 0 ]; then
        CURRENT_DISPLAY_STATE=$STATE_INTERNAL_ONLY
    elif [ "$state_external_count" -eq 1 ]; then
        CURRENT_DISPLAY_STATE=$STATE_DUAL_EXTEND
    else
        CURRENT_DISPLAY_STATE=$STATE_MULTI_EXTEND
    fi

    CURRENT_DISPLAY_INTERNAL_COUNT=$state_effective_internal_count
    CURRENT_DISPLAY_EXTERNAL_COUNT=$state_external_count
}

xdisplay_display_internal_outputs() {
    state_connected=$1
    state_standard=$(printf '%s\n' "$state_connected" |
        awk '$1 ~ /^(eDP|LVDS|DSI)-?[0-9]/ { print }')
    if [ -n "$state_standard" ]; then
        printf '%s\n' "$state_standard"
        return
    fi
    if [ -n "$ADAPTER_INTERNAL_OUTPUTS" ]; then
        printf '%s\n' "$ADAPTER_INTERNAL_OUTPUTS"
        return
    fi
    for state_candidate in ${XDISPLAY_INTERNAL_OUTPUTS:-}; do
        xdisplay_output_in_list "$state_connected" "$state_candidate" &&
            printf '%s\n' "$state_candidate"
    done
}

xdisplay_display_external_outputs() {
    state_connected=$1
    state_internal_outputs=$2
    old_ifs=$IFS
    IFS='
'
    for state_output in $state_connected; do
        xdisplay_output_in_list "$state_internal_outputs" "$state_output" ||
            printf '%s\n' "$state_output"
    done
    IFS=$old_ifs
}

xdisplay_refresh_display_state() {
    state_lid=${1:-unknown}
    state_connected=$(xdisplay_connected_outputs)
    CURRENT_INTERNAL_OUTPUTS=$(xdisplay_display_internal_outputs "$state_connected")
    CURRENT_EXTERNAL_OUTPUTS=$(xdisplay_display_external_outputs \
        "$state_connected" "$CURRENT_INTERNAL_OUTPUTS")
    xdisplay_compute_display_state "$state_lid" "$CURRENT_INTERNAL_OUTPUTS" \
        "$CURRENT_EXTERNAL_OUTPUTS"
    xdisplay_load_custom_layouts "$state_lid"
    case "$state_lid:$CURRENT_DISPLAY_STATE" in
        open:DUAL_EXTEND|unknown:DUAL_EXTEND|absent:DUAL_EXTEND|\
        open:MULTI_EXTEND|unknown:MULTI_EXTEND|absent:MULTI_EXTEND|\
        closed:EXTERNAL_ONLY|closed:MULTI_EXTERNAL)
            if [ "$MULTI_SCREEN_LAYOUT_READY" -eq 1 ]; then
                CURRENT_LAYOUT_FUNCTION=extend_chain
            else
                CURRENT_LAYOUT_FUNCTION=legacy
            fi
            ;;
        *) CURRENT_LAYOUT_FUNCTION=legacy ;;
    esac
    if [ -n "$CUSTOM_LAYOUT_NAME" ]; then
        CURRENT_LAYOUT_FUNCTION=custom
    fi
    return 0
}
