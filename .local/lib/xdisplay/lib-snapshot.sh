# RandR snapshot acquisition and TSV parsing.
# Function: xdisplay_read_snapshot.

xdisplay_read_snapshot() {
    XRANDR_STATE=$(LC_ALL=C xrandr "${1:---current}" 2>/dev/null) || return 1

    # Every raw RandR snapshot is parsed exactly once. Later queries consume
    # this stable TSV model instead of interpreting xrandr's prose repeatedly.
    XRANDR_PARSED=$(printf '%s\n' "$XRANDR_STATE" |
        awk '
            BEGIN { OFS = "\t" }

            function number(value) {
                gsub(/,/, "", value)
                return value + 0
            }

            function parse_geometry(value,    rest, at, tail, sign_at) {
                geometry_width = geometry_height = "-"
                geometry_x = geometry_y = "-"
                if (value !~ /^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+$/)
                    return 0

                split(value, dimensions, "x")
                geometry_width = dimensions[1] + 0
                rest = dimensions[2]
                at = match(rest, /[+-]/)
                if (!at)
                    return 0
                geometry_height = substr(rest, 1, at - 1) + 0
                tail = substr(rest, at)
                sign_at = match(substr(tail, 2), /[+-]/)
                if (!sign_at)
                    return 0
                sign_at++
                geometry_x = substr(tail, 1, sign_at - 1) + 0
                geometry_y = substr(tail, sign_at) + 0
                return 1
            }

            $1 == "Screen" {
                have_screen = 1
                screen_number = $2
                sub(/:$/, "", screen_number)
                for (i = 3; i <= NF; i++) {
                    if ($i == "minimum") {
                        minimum_width = number($(i + 1))
                        minimum_height = number($(i + 3))
                    } else if ($i == "current") {
                        current_width = number($(i + 1))
                        current_height = number($(i + 3))
                    } else if ($i == "maximum") {
                        maximum_width = number($(i + 1))
                        maximum_height = number($(i + 3))
                    }
                }
                selected = 0
                next
            }

            /^[^ \t]/ {
                selected = 0
                if ($2 != "connected" && $2 != "disconnected")
                    next

                count++
                selected = count
                name[count] = $1
                connection[count] = $2
                primary[count] = 0
                geometry[count] = "-"
                width[count] = height[count] = "-"
                x[count] = y[count] = "-"
                first_mode[count] = "-"
                first_rate[count] = "-"
                current_mode[count] = current_rate[count] = "-"
                preferred_mode[count] = preferred_rate[count] = "-"
                mode_count[count] = 0
                mode_signature[count] = ""
                for (i = 3; i <= NF; i++) {
                    if ($i == "primary")
                        primary[count] = 1
                    if (parse_geometry($i)) {
                        geometry[count] = $i
                        width[count] = geometry_width
                        height[count] = geometry_height
                        x[count] = geometry_x
                        y[count] = geometry_y
                    }
                }
                next
            }

            selected && connection[selected] == "connected" &&
                $1 ~ /^[0-9]+x[0-9]+/ {
                output_index = selected
                mode = $1
                is_first_mode = (first_mode[output_index] == "-")
                if (is_first_mode)
                    first_mode[output_index] = mode
                mode_count[output_index]++
                mode_entry = mode "@"
                separator = ""
                last_rate = ""
                last_rate_preferred = 0

                for (i = 2; i <= NF; i++) {
                    token = $i
                    if (token ~ /^[*+]+$/ && last_rate != "") {
                        is_current = (token ~ /[*]/)
                        is_preferred = (token ~ /[+]/)
                        if (is_preferred && !last_rate_preferred)
                            mode_entry = mode_entry "+"
                        if (is_current && current_mode[output_index] == "-") {
                            current_mode[output_index] = mode
                            current_rate[output_index] = last_rate
                        }
                        if (is_preferred && preferred_mode[output_index] == "-") {
                            preferred_mode[output_index] = mode
                            preferred_rate[output_index] = last_rate
                        }
                        if (is_preferred)
                            last_rate_preferred = 1
                        continue
                    }
                    if (token !~ /^[0-9]+([.][0-9]+)?[*+]*$/)
                        continue
                    is_current = (token ~ /[*]/)
                    is_preferred = (token ~ /[+]/)
                    rate = token
                    gsub(/[*+]/, "", rate)
                    if (rate !~ /^[0-9]+([.][0-9]+)?$/)
                        continue

                    if (is_first_mode && first_rate[output_index] == "-")
                        first_rate[output_index] = rate
                    mode_entry = mode_entry separator rate
                    if (is_preferred)
                        mode_entry = mode_entry "+"
                    separator = ","
                    last_rate = rate
                    last_rate_preferred = is_preferred

                    if (is_current && current_mode[output_index] == "-") {
                        current_mode[output_index] = mode
                        current_rate[output_index] = rate
                    }
                    if (is_preferred && preferred_mode[output_index] == "-") {
                        preferred_mode[output_index] = mode
                        preferred_rate[output_index] = rate
                    }
                }
                mode_signature[output_index] = mode_signature[output_index] \
                    mode_entry ";"
                next
            }

            END {
                if (!have_screen)
                    exit 2
                print "screen", screen_number, minimum_width, minimum_height,
                    current_width, current_height, maximum_width, maximum_height
                for (i = 1; i <= count; i++) {
                    active = (geometry[i] != "-")
                    mode_ready = (connection[i] == "connected" &&
                        first_mode[i] != "-")
                    stale = (connection[i] == "disconnected" && active)
                    pending = (connection[i] == "connected" && !active &&
                        !mode_ready)
                    if (preferred_mode[i] != "-") {
                        target_mode = preferred_mode[i]
                        target_rate = preferred_rate[i]
                    } else {
                        target_mode = first_mode[i]
                        target_rate = first_rate[i]
                    }
                    if (mode_signature[i] == "")
                        mode_signature[i] = "-"
                    print "output", name[i], connection[i], primary[i],
                        geometry[i], width[i], height[i], x[i], y[i],
                        mode_ready, first_mode[i], active, stale, pending,
                        current_mode[i], current_rate[i], preferred_mode[i],
                        preferred_rate[i], target_mode, target_rate,
                        mode_count[i], mode_signature[i], "-", "-"
                }
            }
        ') || return 1

    [ -n "$XRANDR_PARSED" ] || return 1
    xdisplay_adapter_refresh_internal_outputs
    xdisplay_adapter_refresh_expected_target
    xdisplay_refresh_display_state "${LID_STATE:-unknown}"
}
