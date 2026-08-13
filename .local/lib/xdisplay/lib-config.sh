# Engine and default-layout configuration loading.
# Functions: xdisplay_load_engine_config, xdisplay_load_layout_config,
# xdisplay_choose_layout_primary.

xdisplay_load_engine_config() {
    CONFIG_TIMEOUT_SECONDS=2
    CONFIG_KILL_AFTER_SECONDS=1
    CONFIG_APPLY_FAILURE_LIMIT=3
    CONFIG_APPLY_RETRY_TICKS=10
    CONFIG_HARDWARE_PROBE_TICKS=120
    CONFIG_PENDING_PROBE_TICKS=10
    CONFIG_LOG_MAX_BYTES=1048576
    CONFIG_LOG_PATH=${XDG_STATE_HOME:-$HOME/.local/share}/x11/xdisplay-adapter.log
    CONFIG_PARSE_ERROR=0
    engine_file=${XDISPLAY_ENGINE_CONFIG:-$HOME/.config/x11/display-engine.conf}
    [ -r "$engine_file" ] || {
        PENDING_PROBE_TICKS=$CONFIG_PENDING_PROBE_TICKS
        HARDWARE_PROBE_TICKS=$CONFIG_HARDWARE_PROBE_TICKS
        APPLY_FAILURE_LIMIT=$CONFIG_APPLY_FAILURE_LIMIT
        APPLY_RETRY_TICKS=$CONFIG_APPLY_RETRY_TICKS
        ADAPTER_TIMEOUT=$CONFIG_TIMEOUT_SECONDS
        ADAPTER_KILLAFTER=$CONFIG_KILL_AFTER_SECONDS
        ADAPTER_LOG_MAX_BYTES=$CONFIG_LOG_MAX_BYTES
        ADAPTER_LOG=$CONFIG_LOG_PATH
        return 0
    }
    records=$(xdisplay_parse_config_records "$engine_file")
    while IFS='|' read -r section key value; do
        [ -n "${section}${key}${value}" ] || continue
        case "$section" in
            ERROR) xdisplay_config_diagnostic "$engine_file:$key: $value"; continue ;;
            engine) ;;
            *) xdisplay_config_diagnostic "$engine_file: unknown section [$section]"; continue ;;
        esac
        case "$key" in
            timeout_seconds)
                if xdisplay_config_is_positive_integer "$value"; then CONFIG_TIMEOUT_SECONDS=$value
                else xdisplay_config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            kill_after_seconds)
                if xdisplay_config_is_integer "$value"; then CONFIG_KILL_AFTER_SECONDS=$value
                else xdisplay_config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            apply_failure_limit)
                if xdisplay_config_is_integer "$value"; then CONFIG_APPLY_FAILURE_LIMIT=$value
                else xdisplay_config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            apply_retry_ticks)
                if xdisplay_config_is_integer "$value"; then CONFIG_APPLY_RETRY_TICKS=$value
                else xdisplay_config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            hardware_probe_ticks)
                if xdisplay_config_is_integer "$value"; then CONFIG_HARDWARE_PROBE_TICKS=$value
                else xdisplay_config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            pending_probe_ticks)
                if xdisplay_config_is_integer "$value"; then CONFIG_PENDING_PROBE_TICKS=$value
                else xdisplay_config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            log_max_bytes)
                if xdisplay_config_is_positive_integer "$value"; then CONFIG_LOG_MAX_BYTES=$value
                else xdisplay_config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            log_path)
                if [ -n "$value" ]; then CONFIG_LOG_PATH=$(xdisplay_expand_config_path "$value")
                else xdisplay_config_diagnostic "$engine_file:$key: empty value"; fi ;;
            *) xdisplay_config_diagnostic "$engine_file: unknown key '$key'" ;;
        esac
    done <<EOF
$records
EOF
    PENDING_PROBE_TICKS=$CONFIG_PENDING_PROBE_TICKS
    HARDWARE_PROBE_TICKS=$CONFIG_HARDWARE_PROBE_TICKS
    APPLY_FAILURE_LIMIT=$CONFIG_APPLY_FAILURE_LIMIT
    APPLY_RETRY_TICKS=$CONFIG_APPLY_RETRY_TICKS
    ADAPTER_TIMEOUT=$CONFIG_TIMEOUT_SECONDS
    ADAPTER_KILLAFTER=$CONFIG_KILL_AFTER_SECONDS
    ADAPTER_LOG_MAX_BYTES=$CONFIG_LOG_MAX_BYTES
    ADAPTER_LOG=$CONFIG_LOG_PATH
    [ "$CONFIG_PARSE_ERROR" -eq 0 ]
}

xdisplay_load_layout_config() {
    CONFIG_EXTERNAL_POSITION=right
    CONFIG_EXTERNAL_PRIMARY=first
    CONFIG_MIRROR_ON_DUPLICATE=false
    CONFIG_LAYOUT_FILE_PRESENT=0
    CONFIG_PARSE_ERROR=0
    layout_file=${XDISPLAY_LAYOUT_CONFIG:-$HOME/.config/x11/display-layouts/default.conf}
    [ -r "$layout_file" ] || return 0
    CONFIG_LAYOUT_FILE_PRESENT=1
    records=$(xdisplay_parse_config_records "$layout_file")
    while IFS='|' read -r section key value; do
        [ -n "${section}${key}${value}" ] || continue
        case "$section" in
            ERROR) xdisplay_config_diagnostic "$layout_file:$key: $value"; continue ;;
            defaults) ;;
            *) xdisplay_config_diagnostic "$layout_file: unknown section [$section]"; continue ;;
        esac
        case "$key" in
            external_position)
                if xdisplay_config_is_position "$value"; then CONFIG_EXTERNAL_POSITION=$value
                else xdisplay_config_diagnostic "$layout_file:$key: invalid value '$value'"; fi ;;
            external_primary)
                if xdisplay_config_is_primary_rule "$value"; then CONFIG_EXTERNAL_PRIMARY=$value
                else xdisplay_config_diagnostic "$layout_file:$key: invalid value '$value'"; fi ;;
            mirror_on_duplicate)
                if xdisplay_config_is_boolean "$value"; then CONFIG_MIRROR_ON_DUPLICATE=$value
                else xdisplay_config_diagnostic "$layout_file:$key: invalid value '$value'"; fi ;;
            *) xdisplay_config_diagnostic "$layout_file: unknown key '$key'" ;;
        esac
    done <<EOF
$records
EOF
    [ "$CONFIG_PARSE_ERROR" -eq 0 ]
}

xdisplay_choose_layout_primary() {
    outputs=$1
    if [ "$CONFIG_LAYOUT_FILE_PRESENT" -eq 0 ]; then
        xdisplay_choose_primary "$outputs"
        return
    fi
    case "$CONFIG_EXTERNAL_PRIMARY" in
        largest)
            printf '%s\n' "$XRANDR_PARSED" |
                awk -F '\t' -v candidates="$outputs" '
                    BEGIN { count = split(candidates, names, /\n/) }
                    $1 == "output" && $3 == "connected" {
                        for (i = 1; i <= count; i++) if ($2 == names[i]) {
                            area = ($6 + 0) * ($7 + 0)
                            if (!found || area > best_area) {
                                best_area = area
                                best = $2
                                found = 1
                            }
                        }
                    }
                    END { if (found) print best }
                '
            ;;
        manual|first) xdisplay_first_output "$outputs" ;;
        *) xdisplay_choose_primary "$outputs" ;;
    esac
}
