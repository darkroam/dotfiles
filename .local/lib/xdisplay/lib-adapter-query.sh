# Adapter identity/expected-mode validation and stable-snapshot caches.
# Functions: xdisplay_adapter_output_is_connected,
# xdisplay_adapter_validate_internal_outputs, xdisplay_adapter_refresh_*,
# xdisplay_adapter_mode_is_available, xdisplay_adapter_apply_expected_target.

xdisplay_adapter_output_is_connected() {
    xdisplay_output_in_list "$(xdisplay_connected_outputs)" "$1"
}

xdisplay_adapter_validate_internal_outputs() {
    outputs=$1
    adapter_result=$2
    # An empty successful response means the device has no extra candidates.
    [ -n "$adapter_result" ] || return 0

    valid_outputs=
    invalid=0
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        printf '%s\n' "$candidate" |
            LC_ALL=C awk '$0 !~ /[[:space:][:cntrl:]]/ { valid = 1 } END { exit !valid }' || {
                invalid=1
                continue
            }
        xdisplay_adapter_output_is_connected "$candidate" || {
            invalid=1
            continue
        }
        printf '%s\n' "$valid_outputs" | grep -qxF "$candidate" && continue
        if [ -n "$valid_outputs" ]; then
            valid_outputs=$(printf '%s\n%s' "$valid_outputs" "$candidate")
        else
            valid_outputs=$candidate
        fi
    done <<EOF
$adapter_result
EOF

    if [ "$(xdisplay_output_count "$valid_outputs")" -gt 1 ]; then
        invalid=1
    fi
    if [ "$invalid" -eq 1 ] || [ -z "$valid_outputs" ]; then
        xdisplay_adapter_log_event internal-outputs none 65 INVALID invalid_candidate
        return 1
    fi
    printf '%s\n' "$valid_outputs"
}

xdisplay_adapter_refresh_internal_outputs() {
    ADAPTER_INTERNAL_OUTPUTS=
    [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] || return 0

    if [ ! -x "$ADAPTER_PATH" ]; then
        if [ "$ADAPTER_UNAVAILABLE_LOGGED" -eq 0 ]; then
            xdisplay_adapter_log_event internal-outputs none 127 UNAVAILABLE adapter_missing
            ADAPTER_UNAVAILABLE_LOGGED=1
        fi
        return 0
    fi

    connected=$(xdisplay_connected_outputs)
    standard_output=$(printf '%s\n' "$connected" |
        awk '$1 ~ /^(eDP|LVDS|DSI)-?[0-9]/ { print; exit }')
    [ -z "$standard_output" ] || return 0
    adapter_mtime=$(stat -c %Y "$ADAPTER_PATH" 2>/dev/null || printf unknown)
    topology_key=$(printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '$1 == "output" { printf "%s:%s:%s,", $2, $3, $22 }')
    cache_key=$adapter_mtime\|$topology_key
    if [ "$cache_key" = "$ADAPTER_INTERNAL_CACHE_KEY" ]; then
        ADAPTER_INTERNAL_OUTPUTS=$ADAPTER_INTERNAL_CACHE_VALUE
        return 0
    fi
    adapter_result=$(xdisplay_run_adapter internal-outputs)
    adapter_status=$?
    if [ "$adapter_status" -ne 0 ]; then
        ADAPTER_INTERNAL_CACHE_KEY=$cache_key
        ADAPTER_INTERNAL_CACHE_VALUE=
        return 0
    fi
    ADAPTER_INTERNAL_OUTPUTS=$(xdisplay_adapter_validate_internal_outputs "$connected" "$adapter_result") ||
        ADAPTER_INTERNAL_OUTPUTS=
    ADAPTER_INTERNAL_CACHE_KEY=$cache_key
    ADAPTER_INTERNAL_CACHE_VALUE=$ADAPTER_INTERNAL_OUTPUTS
}

xdisplay_adapter_mode_is_available() {
    output=$1
    mode=$2
    rate=$3
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$output" -v mode="$mode" -v rate="$rate" '
            $1 == "output" && $2 == output {
                count = split($22, entries, ";")
                for (i = 1; i <= count; i++) {
                    split(entries[i], parts, "@")
                    if (parts[1] != mode)
                        continue
                    gsub(/[+]/, "", parts[2])
                    if (rate == "-") {
                        found = 1
                    } else {
                        rates_count = split(parts[2], rates, ",")
                        for (j = 1; j <= rates_count; j++)
                            if ((rates[j] + 0) == (rate + 0))
                                found = 1
                    }
                }
            }
            END { exit !found }
        '
}

xdisplay_adapter_apply_expected_target() {
    output=$1
    mode=$2
    rate=$3
    XRANDR_PARSED=$(printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v OFS='\t' -v output="$output" -v mode="$mode" -v rate="$rate" '
            $1 == "output" && $2 == output { $23 = mode; $24 = rate }
            { print }
        ')
}

xdisplay_adapter_refresh_expected_target() {
    ADAPTER_EXPECTED_OUTPUT=
    ADAPTER_EXPECTED_VALID=0
    ADAPTER_EXPECTED_PRESENT=0
    [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] || return 0
    [ -x "$ADAPTER_PATH" ] || return 0

    connected=$(xdisplay_connected_outputs)
    internal=$(xdisplay_internal_output "$connected")
    [ -n "$internal" ] || return 0
    adapter_mtime=$(stat -c %Y "$ADAPTER_PATH" 2>/dev/null || printf unknown)
    output_signature=$(printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$internal" '$1 == "output" && $2 == output { print $22 }')
    topology_key=$(printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '$1 == "output" { printf "%s:%s,", $2, $3 }')
    cache_key=$adapter_mtime\|$internal\|$topology_key\|$output_signature
    if [ "$cache_key" = "$ADAPTER_EXPECTED_CACHE_KEY" ]; then
        [ "$ADAPTER_EXPECTED_CACHE_VALID" -eq 1 ] || return 0
        expected=$ADAPTER_EXPECTED_CACHE_VALUE
    else
        expected=$(xdisplay_run_adapter expected-mode "$internal")
        expected_status=$?
        ADAPTER_EXPECTED_CACHE_KEY=$cache_key
        ADAPTER_EXPECTED_CACHE_VALUE=$expected
        if [ "$expected_status" -eq 0 ]; then
            ADAPTER_EXPECTED_CACHE_VALID=1
        else
            ADAPTER_EXPECTED_CACHE_VALID=0
            return 0
        fi
    fi

    printf '%s\n' "$expected" | awk 'NR != 1 || NF != 1 { exit 1 }' || {
        xdisplay_adapter_log_event expected-mode "$internal" 65 INVALID invalid_output_shape
        ADAPTER_EXPECTED_CACHE_VALID=0
        return 0
    }
    expected_mode=$expected
    expected_rate=-
    case "$expected" in
        *@*)
            expected_mode=${expected%@*}
            expected_rate=${expected##*@}
            ;;
    esac
    printf '%s\n' "$expected_mode" |
        grep -Eq '^[1-9][0-9]*x[1-9][0-9]*$' || {
            xdisplay_adapter_log_event expected-mode "$internal" 65 INVALID invalid_mode_format
            ADAPTER_EXPECTED_CACHE_VALID=0
            return 0
        }
    if [ "$expected_rate" != - ]; then
        printf '%s\n' "$expected_rate" |
            grep -Eq '^[1-9][0-9]*(\.[0-9]+)?$' || {
                xdisplay_adapter_log_event expected-mode "$internal" 65 INVALID invalid_rate_format
                ADAPTER_EXPECTED_CACHE_VALID=0
                return 0
            }
    fi

    ADAPTER_EXPECTED_OUTPUT=$internal
    ADAPTER_EXPECTED_VALID=1
    if xdisplay_adapter_mode_is_available "$internal" "$expected_mode" "$expected_rate"; then
        ADAPTER_EXPECTED_PRESENT=1
        xdisplay_adapter_apply_expected_target "$internal" "$expected_mode" "$expected_rate"
    else
        if [ "$cache_key" != "$ADAPTER_EXPECTED_MISSING_LOG_KEY" ]; then
            xdisplay_adapter_log_event expected-mode "$internal" 0 MISSING expected_mode_missing
            ADAPTER_EXPECTED_MISSING_LOG_KEY=$cache_key
        fi
    fi
}
