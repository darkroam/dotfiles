# Best-match custom-layout selection.
# Function: xdisplay_load_custom_layouts.

xdisplay_load_custom_layouts() {
    xdisplay_custom_layout_reset
    custom_dir=${XDISPLAY_CUSTOM_LAYOUT_DIR:-$HOME/.config/x11/display-layouts/custom}
    [ -d "$custom_dir" ] || return 0
    current_lid=${1:-${LID_STATE:-unknown}}
    current_outputs=$(xdisplay_custom_current_outputs "$current_lid")
    [ -n "$(printf '%s\n' "$current_outputs" | sed '/^$/d')" ] || return 0

    best_file=
    best_name=
    best_primary=
    best_order=
    best_positions=
    best_lid=
    best_match=
    best_lid_rank=0
    best_match_rank=0
    best_count=0
    best_mtime=0

    for custom_file in "$custom_dir"/*.conf; do
        [ -f "$custom_file" ] || continue
        custom_outputs=
        custom_lid=
        custom_match=
        custom_primary=
        custom_order=
        custom_positions=
        custom_error=0
        custom_records=$(xdisplay_custom_config_records "$custom_file") || custom_error=1
        while IFS='	' read -r section key value; do
            [ -n "${section}${key}${value}" ] || continue
            case "$section" in
                ERROR) custom_error=1; continue ;;
                identity)
                    case "$key" in
                        outputs) custom_outputs=$value ;;
                        lid) custom_lid=$value ;;
                        match_mode) custom_match=$value ;;
                        *) custom_error=1 ;;
                    esac
                    ;;
                layout)
                    case "$key" in
                        primary) custom_primary=$value ;;
                        order) custom_order=$value ;;
                        output_*)
                            xdisplay_custom_validate_position_record "$value" || custom_error=1
                            if [ -n "$custom_positions" ]; then
                                custom_positions=$(printf '%s\n%s' "$custom_positions" "$value")
                            else
                                custom_positions=$value
                            fi
                            ;;
                        *) custom_error=1 ;;
                    esac
                    ;;
                *) custom_error=1 ;;
            esac
        done <<EOF
$custom_records
EOF
        [ "$custom_error" -eq 0 ] || {
            xdisplay_adapter_log_event custom-layout "${custom_file##*/}" 65 INVALID parse_failed
            continue
        }
        case "$custom_lid" in open|closed|any) ;; *) continue ;; esac
        case "$custom_match" in exact|contains) ;; *) continue ;; esac
        [ -n "$custom_outputs" ] || continue
        [ -n "$custom_primary" ] || continue
        custom_invalid=0
        while IFS= read -r custom_output; do
            [ -n "$custom_output" ] || continue
            xdisplay_custom_valid_output_name "$custom_output" || custom_invalid=1
        done <<EOF
$(xdisplay_custom_output_lines "$custom_outputs")
EOF
        xdisplay_custom_valid_output_name "$custom_primary" || custom_invalid=1
        while IFS= read -r custom_order_output; do
            [ -n "$custom_order_output" ] || continue
            xdisplay_custom_valid_output_name "$custom_order_output" || custom_invalid=1
        done <<EOF
$(xdisplay_custom_output_lines "$custom_order")
EOF
        while IFS= read -r custom_position; do
            [ -n "$custom_position" ] || continue
            xdisplay_custom_validate_position_record "$custom_position" || custom_invalid=1
        done <<EOF
$custom_positions
EOF
        [ "$custom_invalid" -eq 0 ] || continue
        [ -n "$custom_order" ] || custom_order=$custom_outputs
        custom_primary_in_set=1
        xdisplay_custom_output_lines "$custom_outputs" | grep -qxF "$custom_primary" || custom_primary_in_set=0
        [ "$custom_primary_in_set" -eq 1 ] || continue
        case "$custom_match" in
            exact) xdisplay_custom_output_set_equal "$custom_outputs" "$current_outputs" || continue ;;
            contains) xdisplay_custom_output_set_contains "$custom_outputs" "$current_outputs" || continue ;;
        esac
        case "$custom_lid:$current_lid" in
            any:*) custom_lid_rank=1 ;;
            open:open|closed:closed) custom_lid_rank=2 ;;
            *) continue ;;
        esac
        [ "$custom_match" = exact ] && custom_match_rank=2 || custom_match_rank=1
        custom_count=$(xdisplay_custom_output_lines "$custom_outputs" | sed '/^$/d' | wc -l | awk '{print $1}')
        custom_mtime=$(stat -c %Y "$custom_file" 2>/dev/null || printf 0)
        if [ "$custom_lid_rank" -gt "$best_lid_rank" ] ||
            { [ "$custom_lid_rank" -eq "$best_lid_rank" ] &&
                [ "$custom_match_rank" -gt "$best_match_rank" ]; } ||
            { [ "$custom_lid_rank" -eq "$best_lid_rank" ] &&
                [ "$custom_match_rank" -eq "$best_match_rank" ] &&
                [ "$custom_count" -gt "$best_count" ]; } ||
            { [ "$custom_lid_rank" -eq "$best_lid_rank" ] &&
                [ "$custom_match_rank" -eq "$best_match_rank" ] &&
                [ "$custom_count" -eq "$best_count" ] &&
                [ "$custom_mtime" -gt "$best_mtime" ]; }; then
            best_file=$custom_file
            best_name=${custom_file##*/}
            best_name=${best_name%.conf}
            best_primary=$custom_primary
            best_order=$(xdisplay_custom_output_lines "$custom_order")
            best_positions=$custom_positions
            best_lid=$custom_lid
            best_match=$custom_match
            best_lid_rank=$custom_lid_rank
            best_match_rank=$custom_match_rank
            best_count=$custom_count
            best_mtime=$custom_mtime
        fi
    done

    [ -n "$best_file" ] || return 0
    CUSTOM_LAYOUT_NAME=$best_name
    CUSTOM_LAYOUT_PRIMARY=$best_primary
    CUSTOM_LAYOUT_ORDER=$best_order
    CUSTOM_LAYOUT_POSITIONS=$best_positions
    CUSTOM_LAYOUT_LID=$best_lid
    CUSTOM_LAYOUT_MATCH_MODE=$best_match
    CUSTOM_LAYOUT_MTIME=$best_mtime
    : "$CUSTOM_LAYOUT_LID" "$CUSTOM_LAYOUT_MATCH_MODE"
}
