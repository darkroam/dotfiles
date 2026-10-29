# Extended and mirrored geometry verification.
# Functions: xdisplay_outputs_extended_from,
# xdisplay_outputs_extended_from_direction, xdisplay_outputs_mirrored.

xdisplay_outputs_extended_from() {
    anchor=$1
    outputs=$2
    old_ifs=$IFS
    IFS='
'
    for output in $outputs; do
        [ "$output" = "$anchor" ] && continue
        xdisplay_output_right_of "$output" "$anchor" ||
            { IFS=$old_ifs; return 1; }
        anchor=$output
    done
    IFS=$old_ifs
}

xdisplay_outputs_extended_from_direction() {
    anchor=$1
    outputs=$2
    direction=${3:-right}
    case "$direction" in
        right) relation=right ;;
        left) relation=left ;;
        above) relation=above ;;
        below) relation=below ;;
        *) return 1 ;;
    esac
    old_ifs=$IFS
    IFS='
'
    for output in $outputs; do
        [ "$output" = "$anchor" ] && continue
        xdisplay_output_relation "$output" "$anchor" "$relation" || {
            IFS=$old_ifs
            return 1
        }
        anchor=$output
    done
    IFS=$old_ifs
}

xdisplay_outputs_mirrored() {
    primary=$1
    outputs=$2
    old_ifs=$IFS
    IFS='
'
    for output in $outputs; do
        [ "$output" = "$primary" ] && continue
        printf '%s\n' "$XRANDR_PARSED" |
            awk -F '\t' -v output="$output" -v primary="$primary" '
                $1 == "output" && ($2 == output || $2 == primary) &&
                    $12 == 1 {
                    if ($2 == output) {
                        output_x = $8
                        output_y = $9
                        have_output = 1
                    } else {
                        primary_x = $8
                        primary_y = $9
                        have_primary = 1
                    }
                }
                END {
                    exit !(have_output && have_primary &&
                        output_x == primary_x && output_y == primary_y)
                }
            ' || { IFS=$old_ifs; return 1; }
    done
    IFS=$old_ifs
}
