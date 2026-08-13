# Per-output state and target-mode queries.
# Functions: xdisplay_output_in_list, xdisplay_output_active,
# xdisplay_output_primary, xdisplay_output_at_origin, xdisplay_output_ready,
# xdisplay_output_target_*, xdisplay_output_at_target_mode.

xdisplay_output_in_list() {
    printf '%s\n' "$1" |
        awk -v output="$2" '$1 == output { found = 1 } END { exit !found }'
}

xdisplay_output_active() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output && $12 == 1 { found = 1 }
            END { exit !found }
        '
}

xdisplay_output_primary() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output && $4 == 1 { found = 1 }
            END { exit !found }
        '
}

xdisplay_output_at_origin() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output && $12 == 1 &&
                $8 == 0 && $9 == 0 { found = 1 }
            END { exit !found }
        '
}

xdisplay_output_ready() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output && $10 == 1 { found = 1 }
            END { exit !found }
        '
}

xdisplay_output_target_mode() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output {
                print ($23 != "-" ? $23 : $19)
                found = 1
                exit
            }
            END { if (!found) print "-" }
        '
}

xdisplay_output_target_rate() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output {
                print ($24 != "-" ? $24 : $20)
                found = 1
                exit
            }
            END { if (!found) print "-" }
        '
}

xdisplay_output_at_target_mode() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output && $12 == 1 {
                target_mode = ($23 != "-" ? $23 : $19)
                target_rate = ($24 != "-" ? $24 : $20)
                if (target_mode == "-")
                    found = 1
                else if ($23 != "-" && $15 == target_mode &&
                    (target_rate == "-" || ($16 + 0) == (target_rate + 0)))
                    found = 1
                else if ($23 == "-" && $15 == target_mode &&
                    (target_rate == "-" || $16 == target_rate))
                    found = 1
            }
            END { exit !found }
        '
}
