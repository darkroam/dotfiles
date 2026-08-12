#!/bin/sh

# Keep the X11 layout aligned with lid and RandR output state. Machines whose
# internal panel uses nonstandard names can list them in
# XDISPLAY_INTERNAL_OUTPUTS. XDISPLAY_RESTORE_COMMAND may name an optional
# device-local recovery helper.

FAST_WINDOW_CHECKS=10
FAST_QUERY_INTERVAL=2
STABLE_POLL_TICKS=1
SNAPSHOT_FAILURE_LIMIT=6
# Built-in defaults are intentionally kept next to the configuration schema.
# A missing or invalid optional configuration file must preserve these values.
CONFIG_TIMEOUT_SECONDS=2
CONFIG_KILL_AFTER_SECONDS=1
CONFIG_APPLY_FAILURE_LIMIT=3
CONFIG_APPLY_RETRY_TICKS=10
CONFIG_HARDWARE_PROBE_TICKS=120
CONFIG_PENDING_PROBE_TICKS=10
CONFIG_LOG_MAX_BYTES=1048576
CONFIG_LOG_PATH=${HOME}/.local/share/x11/xdisplay-adapter.log
CONFIG_EXTERNAL_POSITION=right
CONFIG_EXTERNAL_PRIMARY=first
CONFIG_MIRROR_ON_DUPLICATE=false
CONFIG_LAYOUT_FILE_PRESENT=0
CONFIG_PARSE_ERROR=0

# Runtime aliases retained for the existing watcher and adapter code.
PENDING_PROBE_TICKS=$CONFIG_PENDING_PROBE_TICKS
HARDWARE_PROBE_TICKS=$CONFIG_HARDWARE_PROBE_TICKS
APPLY_FAILURE_LIMIT=$CONFIG_APPLY_FAILURE_LIMIT
APPLY_RETRY_TICKS=$CONFIG_APPLY_RETRY_TICKS
# Device-local adapter support is opt-in. The legacy environment variables
# remain the default compatibility path when this gate is disabled.
XDISPLAY_USE_ADAPTER=${XDISPLAY_USE_ADAPTER:-0}
case "$XDISPLAY_USE_ADAPTER" in
    1) ;;
    *) XDISPLAY_USE_ADAPTER=0 ;;
esac
ADAPTER_PATH=${HOME}/.config/x11/xdisplay-device.local
ADAPTER_LOG=$CONFIG_LOG_PATH
ADAPTER_TIMEOUT=$CONFIG_TIMEOUT_SECONDS
ADAPTER_KILLAFTER=$CONFIG_KILL_AFTER_SECONDS
ADAPTER_LOG_MAX_BYTES=$CONFIG_LOG_MAX_BYTES
# A stable watcher attempts a snapshot once per second. This wait therefore
# outlasts the old watcher's consecutive-failure exit window.
WATCH_LOCK_WAIT=8
# The second-batch chain layout is enabled in this build. Keep the guard
# explicit so a future rollout can safely fall back to the legacy path.
MULTI_SCREEN_LAYOUT_READY=1

# Explicit display states. MIRROR and CUSTOM are reserved for later layout
# batches; this batch only computes the physical/lid-derived states.
STATE_INTERNAL_ONLY=INTERNAL_ONLY
STATE_EXTERNAL_ONLY=EXTERNAL_ONLY
STATE_DUAL_EXTEND=DUAL_EXTEND
STATE_MULTI_EXTEND=MULTI_EXTEND
STATE_MULTI_EXTERNAL=MULTI_EXTERNAL
STATE_MIRROR=MIRROR
STATE_CUSTOM=CUSTOM
STATE_NONE=NONE
# Keep reserved states explicit without selecting them in this batch.
: "$STATE_MIRROR" "$STATE_CUSTOM"

ADAPTER_INTERNAL_OUTPUTS=
ADAPTER_INTERNAL_CACHE_KEY=
ADAPTER_INTERNAL_CACHE_VALUE=
ADAPTER_EXPECTED_OUTPUT=
ADAPTER_EXPECTED_VALID=0
ADAPTER_EXPECTED_PRESENT=0
ADAPTER_EXPECTED_CACHE_KEY=
ADAPTER_EXPECTED_CACHE_VALUE=
ADAPTER_EXPECTED_CACHE_VALID=0
ADAPTER_EXPECTED_MISSING_LOG_KEY=
ADAPTER_UNAVAILABLE_LOGGED=0
ADAPTER_RESTORE_ATTEMPTED=0
CURRENT_DISPLAY_STATE=$STATE_NONE
CURRENT_INTERNAL_OUTPUTS=
CURRENT_EXTERNAL_OUTPUTS=
CURRENT_DISPLAY_INTERNAL_COUNT=0
CURRENT_DISPLAY_EXTERNAL_COUNT=0
CURRENT_LAYOUT_FUNCTION=legacy
CUSTOM_LAYOUT_NAME=
CUSTOM_LAYOUT_PRIMARY=
CUSTOM_LAYOUT_ORDER=
CUSTOM_LAYOUT_POSITIONS=
CUSTOM_LAYOUT_LID=
CUSTOM_LAYOUT_MATCH_MODE=
CUSTOM_LAYOUT_MTIME=0

notify_problem() {
    message=$1
    printf '%s\n' "$message" >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Display configuration unavailable" "$message"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 && return
    notify_problem "xdisplay.sh requires $1. Install it before using this feature."
    exit 127
}

path_uid() {
    stat -c %u "$1" 2>/dev/null
}

path_mode() {
    stat -c %a "$1" 2>/dev/null
}

config_diagnostic() {
    CONFIG_PARSE_ERROR=1
    printf 'xdisplay.sh: config %s\n' "$1" >&2
}

config_is_integer() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

config_is_positive_integer() {
    config_is_integer "$1" && [ "$1" -gt 0 ]
}

config_is_position() {
    case "$1" in
        right|left|above|below) return 0 ;;
        *) return 1 ;;
    esac
}

config_is_primary_rule() {
    case "$1" in
        first|largest|manual) return 0 ;;
        *) return 1 ;;
    esac
}

config_is_boolean() {
    case "$1" in
        true|false|0|1) return 0 ;;
        *) return 1 ;;
    esac
}

# Emit section|key|value records from a small INI subset. Comments and blank
# lines are ignored; malformed records are reported to the caller as errors.
parse_config_records() {
    awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        {
            line = $0
            sub(/[[:space:]]*#.*/, "", line)
            line = trim(line)
            if (line == "") next
            if (line ~ /^\[[A-Za-z_][A-Za-z0-9_-]*\]$/) {
                section = line
                sub(/^\[/, "", section)
                sub(/\]$/, "", section)
                next
            }
            if (line !~ /^[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*=/) {
                printf "ERROR|%d|malformed line\n", NR
                next
            }
            split(line, pair, "=")
            key = trim(pair[1])
            value = line
            sub(/^[^=]*=/, "", value)
            value = trim(value)
            if (section == "")
                printf "ERROR|%d|key outside section\n", NR
            else
                printf "%s|%s|%s\n", section, key, value
        }
    ' "$1"
}

expand_config_path() {
    case "$1" in
        \~/*) value=${1#\~/}; printf '%s/%s\n' "$HOME" "$value" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

load_engine_config() {
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
    records=$(parse_config_records "$engine_file")
    while IFS='|' read -r section key value; do
        [ -n "${section}${key}${value}" ] || continue
        case "$section" in
            ERROR) config_diagnostic "$engine_file:$key: $value"; continue ;;
            engine) ;;
            *) config_diagnostic "$engine_file: unknown section [$section]"; continue ;;
        esac
        case "$key" in
            timeout_seconds)
                if config_is_positive_integer "$value"; then CONFIG_TIMEOUT_SECONDS=$value
                else config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            kill_after_seconds)
                if config_is_integer "$value"; then CONFIG_KILL_AFTER_SECONDS=$value
                else config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            apply_failure_limit)
                if config_is_integer "$value"; then CONFIG_APPLY_FAILURE_LIMIT=$value
                else config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            apply_retry_ticks)
                if config_is_integer "$value"; then CONFIG_APPLY_RETRY_TICKS=$value
                else config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            hardware_probe_ticks)
                if config_is_integer "$value"; then CONFIG_HARDWARE_PROBE_TICKS=$value
                else config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            pending_probe_ticks)
                if config_is_integer "$value"; then CONFIG_PENDING_PROBE_TICKS=$value
                else config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            log_max_bytes)
                if config_is_positive_integer "$value"; then CONFIG_LOG_MAX_BYTES=$value
                else config_diagnostic "$engine_file:$key: invalid value '$value'"; fi ;;
            log_path)
                if [ -n "$value" ]; then CONFIG_LOG_PATH=$(expand_config_path "$value")
                else config_diagnostic "$engine_file:$key: empty value"; fi ;;
            *) config_diagnostic "$engine_file: unknown key '$key'" ;;
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

load_layout_config() {
    CONFIG_EXTERNAL_POSITION=right
    CONFIG_EXTERNAL_PRIMARY=first
    CONFIG_MIRROR_ON_DUPLICATE=false
    CONFIG_LAYOUT_FILE_PRESENT=0
    CONFIG_PARSE_ERROR=0
    layout_file=${XDISPLAY_LAYOUT_CONFIG:-$HOME/.config/x11/display-layouts/default.conf}
    [ -r "$layout_file" ] || return 0
    CONFIG_LAYOUT_FILE_PRESENT=1
    records=$(parse_config_records "$layout_file")
    while IFS='|' read -r section key value; do
        [ -n "${section}${key}${value}" ] || continue
        case "$section" in
            ERROR) config_diagnostic "$layout_file:$key: $value"; continue ;;
            defaults) ;;
            *) config_diagnostic "$layout_file: unknown section [$section]"; continue ;;
        esac
        case "$key" in
            external_position)
                if config_is_position "$value"; then CONFIG_EXTERNAL_POSITION=$value
                else config_diagnostic "$layout_file:$key: invalid value '$value'"; fi ;;
            external_primary)
                if config_is_primary_rule "$value"; then CONFIG_EXTERNAL_PRIMARY=$value
                else config_diagnostic "$layout_file:$key: invalid value '$value'"; fi ;;
            mirror_on_duplicate)
                if config_is_boolean "$value"; then CONFIG_MIRROR_ON_DUPLICATE=$value
                else config_diagnostic "$layout_file:$key: invalid value '$value'"; fi ;;
            *) config_diagnostic "$layout_file: unknown key '$key'" ;;
        esac
    done <<EOF
$records
EOF
    [ "$CONFIG_PARSE_ERROR" -eq 0 ]
}

choose_layout_primary() {
    outputs=$1
    if [ "$CONFIG_LAYOUT_FILE_PRESENT" -eq 0 ]; then
        choose_primary "$outputs"
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
        manual|first) first_output "$outputs" ;;
        *) choose_primary "$outputs" ;;
    esac
}

init_observation_roots() {
    proc_root=/proc
    sys_root=/sys
    if [ "${XDISPLAY_TEST_MODE:-0}" = 1 ]; then
        test_root=${XDISPLAY_TEST_ROOT:-}
        case "$test_root" in
            /*) ;;
            *)
                notify_problem "XDISPLAY_TEST_ROOT must be an absolute path in test mode."
                return 1
                ;;
        esac
        proc_root=$test_root/proc
        sys_root=$test_root/sys
    fi
}

normalize_display() {
    display_server=${DISPLAY:-}
    [ -n "$display_server" ] || display_server=unknown

    # RandR state belongs to the X server, not to an individual X screen.
    # Only remove a syntactically numeric .screen suffix.
    case "$display_server" in
        *:*)
            display_tail=${display_server##*:}
            case "$display_tail" in
                *.*)
                    display_number=${display_tail%.*}
                    screen_number=${display_tail##*.}
                    case "$display_number" in
                        ''|*[!0-9]*) ;;
                        *)
                            case "$screen_number" in
                                ''|*[!0-9]*) ;;
                                *) display_server=${display_server%:*}:$display_number ;;
                            esac
                            ;;
                    esac
                    ;;
            esac
            ;;
    esac

    display_key=$(printf '%s' "$display_server" |
        LC_ALL=C tr -c 'A-Za-z0-9_-' '_')
    [ -n "$display_key" ] || display_key=unknown
}

init_runtime_paths() {
    user_id=${UID:-$(id -u)}
    case "$user_id" in
        ''|*[!0-9]*)
            notify_problem "Cannot determine a valid numeric user ID for display locks."
            return 1
            ;;
    esac

    runtime_dir=
    if [ -n "${XDG_RUNTIME_DIR:-}" ] &&
        [ -d "$XDG_RUNTIME_DIR" ] &&
        [ ! -L "$XDG_RUNTIME_DIR" ] &&
        [ -w "$XDG_RUNTIME_DIR" ] &&
        [ -x "$XDG_RUNTIME_DIR" ] &&
        [ "$(path_uid "$XDG_RUNTIME_DIR")" = "$user_id" ] &&
        [ "$(path_mode "$XDG_RUNTIME_DIR")" = 700 ]; then
        runtime_dir=$XDG_RUNTIME_DIR
    fi

    if [ -z "$runtime_dir" ]; then
        runtime_base=${TMPDIR:-/tmp}
        case "$runtime_base" in
            /*) ;;
            *) runtime_base=/tmp ;;
        esac
        if [ ! -d "$runtime_base" ] || [ ! -w "$runtime_base" ] ||
            [ ! -x "$runtime_base" ]; then
            runtime_base=/tmp
        fi
        if [ ! -d "$runtime_base" ] || [ ! -w "$runtime_base" ] ||
            [ ! -x "$runtime_base" ]; then
            notify_problem "No writable and searchable runtime directory is available."
            return 1
        fi

        runtime_dir=$runtime_base/xdisplay-$user_id
        if [ -L "$runtime_dir" ]; then
            notify_problem "Refusing symlinked display runtime directory: $runtime_dir"
            return 1
        fi
        old_umask=$(umask)
        umask 077
        if ! mkdir -p "$runtime_dir"; then
            umask "$old_umask"
            notify_problem "Cannot create display runtime directory: $runtime_dir"
            return 1
        fi
        umask "$old_umask"

        if [ -L "$runtime_dir" ] || [ ! -d "$runtime_dir" ]; then
            notify_problem "Refusing unsafe display runtime directory: $runtime_dir"
            return 1
        fi
        if [ "$(path_uid "$runtime_dir")" != "$user_id" ]; then
            notify_problem "Display runtime directory is not owned by UID $user_id: $runtime_dir"
            return 1
        fi
        if [ "$(path_mode "$runtime_dir")" != 700 ]; then
            chmod 700 "$runtime_dir" 2>/dev/null || :
        fi
        if [ "$(path_mode "$runtime_dir")" != 700 ]; then
            notify_problem "Display runtime directory must have mode 0700: $runtime_dir"
            return 1
        fi
    fi

    normalize_display
    lock_prefix=$runtime_dir/xdisplay-$user_id-$display_key
    apply_lock=$lock_prefix.apply.lock
    watch_lock=$lock_prefix.watch.lock
    generation_file=$lock_prefix.generation
    manual_marker=$lock_prefix.manual
}

open_apply_lock() {
    [ "${apply_lock_open:-0}" -eq 1 ] && return 0
    exec 8>"$apply_lock" || return 1
    apply_lock_open=1
}

read_lid_state() {
    LID_PRESENT=0
    LID_STATE=absent
    for state_file in "$proc_root"/acpi/button/lid/*/state; do
        [ -e "$state_file" ] || continue
        LID_PRESENT=1
        LID_STATE=unknown
        [ -r "$state_file" ] || continue
        IFS=' ' read -r _ state < "$state_file"
        case "$state" in
            open|closed)
                LID_STATE=$state
                return
                ;;
        esac
    done
}

lid_state() {
    read_lid_state
    printf '%s\n' "$LID_STATE"
}

drm_signature() {
    found=0
    for status_file in "$sys_root"/class/drm/card*-*/status; do
        [ -r "$status_file" ] || continue
        IFS= read -r status < "$status_file"
        connector=${status_file%/status}
        connector=${connector##*/}
        printf '%s=%s,' "$connector" "$status"
        found=1
    done
    [ "$found" -eq 1 ] || printf '%s' unavailable
}

adapter_timestamp() {
    date -Iseconds 2>/dev/null || date
}

adapter_log_value() {
    LC_ALL=C tr -cd '\11\12\40-\176' |
        sed -E \
            -e 's#(/home/[^[:space:]]+)#<path>#g' \
            -e 's#([Xx][Aa][Uu][Tt][Hh][Oo][Rr][Ii][Tt][Yy])([=:][^[:space:]]*)#\1=<redacted>#g' \
            -e 's#([Ee][Dd][Ii][Dd])[^[:space:]]*#\1=<redacted>#g' \
            -e 's#([Ss][Ee][Rr][Ii][Aa][Ll])([=:][^[:space:]]*)#\1=<redacted>#g' \
            -e 's#([Hh][Oo][Ss][Tt][Nn][Aa][Mm][Ee])([=:][^[:space:]]*)#\1=<redacted>#g'
}

adapter_log_event() (
    subcommand=$1
    output=${2:-none}
    exit_code=$3
    status=$4
    detail=${5:-}
    stderr_file=${6:-}
    log_dir=${ADAPTER_LOG%/*}
    [ "$log_dir" != "$ADAPTER_LOG" ] || log_dir=.
    old_umask=$(umask)
    umask 077
    mkdir -p "$log_dir" 2>/dev/null || {
        umask "$old_umask"
        return 0
    }
    touch "$ADAPTER_LOG" 2>/dev/null || {
        umask "$old_umask"
        return 0
    }
    chmod 600 "$ADAPTER_LOG" 2>/dev/null || :
    umask "$old_umask"
    if [ -f "$ADAPTER_LOG" ]; then
        log_size=$(stat -c %s "$ADAPTER_LOG" 2>/dev/null || printf 0)
        if [ "$log_size" -ge "$ADAPTER_LOG_MAX_BYTES" ]; then
            if mv -f "$ADAPTER_LOG" "$ADAPTER_LOG.1" 2>/dev/null; then
                touch "$ADAPTER_LOG" 2>/dev/null || :
                chmod 600 "$ADAPTER_LOG" 2>/dev/null || :
            fi
        fi
    fi
    (
        umask 077
        printf '[%s] subcommand=%s output=%s pid=%s exit=%s status=%s' \
            "$(adapter_timestamp)" "$subcommand" "$output" "$$" "$exit_code" "$status"
        [ -n "$detail" ] && printf ' detail=%s' "$detail"
        printf '\n'
        if [ -n "$stderr_file" ] && [ -s "$stderr_file" ]; then
            printf 'stderr:\n'
            head -c 4096 "$stderr_file" | adapter_log_value | sed 's/^/  /'
        fi
    ) >> "$ADAPTER_LOG" 2>/dev/null || :
)

# Execute one device-local adapter command. stdout is returned to the caller;
# stderr, timeout state, and the exit code are persisted without blocking layout.
run_adapter() (
    subcommand=$1
    output=${2:-}

    [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] || return 127
    if [ ! -x "$ADAPTER_PATH" ]; then
        adapter_log_event "$subcommand" "${output:-none}" 127 UNAVAILABLE adapter_missing
        return 127
    fi
    if ! command -v timeout >/dev/null 2>&1 ||
        ! command -v mktemp >/dev/null 2>&1 ||
        ! command -v env >/dev/null 2>&1; then
        adapter_log_event "$subcommand" "${output:-none}" 127 UNAVAILABLE runtime_tools_missing
        return 127
    fi
    if [ -z "${DISPLAY:-}" ] || [ -z "${XAUTHORITY:-}" ] || [ -z "${PATH:-}" ]; then
        adapter_log_event "$subcommand" "${output:-none}" 127 UNAVAILABLE missing_session_environment
        return 127
    fi

    tmp_stderr=$(mktemp "${TMPDIR:-/tmp}/xdisplay-adapter-stderr.XXXXXX") || {
        adapter_log_event "$subcommand" "${output:-none}" 127 FAILURE temp_failed
        return 127
    }
    tmp_stdout=$(mktemp "${TMPDIR:-/tmp}/xdisplay-adapter-stdout.XXXXXX") || {
        rm -f "$tmp_stderr"
        adapter_log_event "$subcommand" "${output:-none}" 127 FAILURE temp_failed
        return 127
    }
    trap 'rm -f "$tmp_stderr" "$tmp_stdout"' 0

    start_time=$(date +%s%3N 2>/dev/null || date +%s000)
    if [ -n "$output" ]; then
        timeout --kill-after="$ADAPTER_KILLAFTER" "$ADAPTER_TIMEOUT" \
            env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" PATH="$PATH" \
            "$ADAPTER_PATH" "$subcommand" "$output" >"$tmp_stdout" 2>"$tmp_stderr"
    else
        timeout --kill-after="$ADAPTER_KILLAFTER" "$ADAPTER_TIMEOUT" \
            env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" PATH="$PATH" \
            "$ADAPTER_PATH" "$subcommand" >"$tmp_stdout" 2>"$tmp_stderr"
    fi
    exit_code=$?
    end_time=$(date +%s%3N 2>/dev/null || date +%s000)
    elapsed=$((end_time - start_time))ms
    status=SUCCESS
    if [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 137 ]; then
        status=TIMEOUT
    elif [ "$exit_code" -ne 0 ]; then
        status=FAILURE
    fi

    adapter_log_event "$subcommand" "${output:-none}" "$exit_code" "$status" \
        "elapsed=$elapsed" "$tmp_stderr"
    cat "$tmp_stdout"
    return "$exit_code"
)

read_snapshot() {
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
    adapter_refresh_internal_outputs
    adapter_refresh_expected_target
    refresh_display_state "${LID_STATE:-unknown}"
}

connected_outputs() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '$1 == "output" && $3 == "connected" { print $2 }'
}

all_outputs() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '$1 == "output" { print $2 }'
}

output_count() {
    printf '%s\n' "$1" |
        awk 'NF { count++ } END { print count + 0 }'
}

compute_display_state() {
    state_lid=$1
    state_internal_outputs=$2
    state_external_outputs=$3
    state_internal_count=$(output_count "$state_internal_outputs")
    state_external_count=$(output_count "$state_external_outputs")

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

display_internal_outputs() {
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
        output_in_list "$state_connected" "$state_candidate" &&
            printf '%s\n' "$state_candidate"
    done
}

display_external_outputs() {
    state_connected=$1
    state_internal_outputs=$2
    old_ifs=$IFS
    IFS='
'
    for state_output in $state_connected; do
        output_in_list "$state_internal_outputs" "$state_output" ||
            printf '%s\n' "$state_output"
    done
    IFS=$old_ifs
}

refresh_display_state() {
    state_lid=${1:-unknown}
    state_connected=$(connected_outputs)
    CURRENT_INTERNAL_OUTPUTS=$(display_internal_outputs "$state_connected")
    CURRENT_EXTERNAL_OUTPUTS=$(display_external_outputs \
        "$state_connected" "$CURRENT_INTERNAL_OUTPUTS")
    compute_display_state "$state_lid" "$CURRENT_INTERNAL_OUTPUTS" \
        "$CURRENT_EXTERNAL_OUTPUTS"
    load_custom_layouts "$state_lid"
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

custom_layout_reset() {
    CUSTOM_LAYOUT_NAME=
    CUSTOM_LAYOUT_PRIMARY=
    CUSTOM_LAYOUT_ORDER=
    CUSTOM_LAYOUT_POSITIONS=
    CUSTOM_LAYOUT_LID=
    CUSTOM_LAYOUT_MATCH_MODE=
    CUSTOM_LAYOUT_MTIME=0
}

custom_config_records() {
    awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        {
            line = $0
            sub(/[[:space:]]*#.*/, "", line)
            line = trim(line)
            if (line == "") next
            if (line ~ /^\[[A-Za-z_][A-Za-z0-9_-]*\]$/) {
                section = line
                sub(/^\[/, "", section)
                sub(/\]$/, "", section)
                next
            }
            if (line !~ /^[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*=/) {
                printf "ERROR\t%d\tmalformed line\n", NR
                next
            }
            key = line
            sub(/[[:space:]]*=.*/, "", key)
            key = trim(key)
            value = line
            sub(/^[^=]*=/, "", value)
            value = trim(value)
            if (section == "")
                printf "ERROR\t%d\tkey outside section\n", NR
            else
                printf "%s\t%s\t%s\n", section, key, value
        }
    ' "$1"
}

custom_output_lines() {
    value=$1
    printf '%s\n' "$value" | tr ',' '\n' | awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }'
}

custom_output_set_equal() {
    left=$(custom_output_lines "$1" | sort -u)
    right=$(custom_output_lines "$2" | sort -u)
    [ "$(printf '%s\n' "$left" | sed '/^$/d')" = "$(printf '%s\n' "$right" | sed '/^$/d')" ]
}

custom_output_set_contains() {
    configured=$(custom_output_lines "$1" | sort -u)
    current=$(custom_output_lines "$2" | sort -u)
    [ -n "$(printf '%s\n' "$configured" | sed '/^$/d')" ] || return 1
    while IFS= read -r configured_output; do
        [ -n "$configured_output" ] || continue
        printf '%s\n' "$current" | grep -qxF "$configured_output" || return 1
    done <<EOF
$configured
EOF
}

custom_valid_output_name() {
    printf '%s\n' "$1" | LC_ALL=C awk '$0 ~ /^[^[:space:][:cntrl:],|]+$/ { ok=1 } END { exit !ok }'
}

custom_valid_position_value() {
    printf '%s\n' "$1" | LC_ALL=C awk '$0 ~ /^-?[0-9]+$/ { ok=1 } END { exit !ok }'
}

custom_valid_mode_value() {
    printf '%s\n' "$1" | LC_ALL=C awk '$0 ~ /^[1-9][0-9]*x[1-9][0-9]*$/ { ok=1 } END { exit !ok }'
}

custom_valid_rate_value() {
    [ "$1" = - ] || printf '%s\n' "$1" | LC_ALL=C awk '$0 ~ /^[1-9][0-9]*(\.[0-9]+)?$/ { ok=1 } END { exit !ok }'
}

custom_validate_position_record() {
    record=$1
    old_ifs=$IFS
    IFS='|'
    read -r record_output record_x record_y record_mode record_rate <<EOF
$record
EOF
    IFS=$old_ifs
    [ -n "$record_output" ] || return 1
    custom_valid_output_name "$record_output" || return 1
    custom_valid_position_value "$record_x" || return 1
    custom_valid_position_value "$record_y" || return 1
    custom_valid_mode_value "$record_mode" || return 1
    custom_valid_rate_value "${record_rate:--}"
}

custom_current_outputs() {
    # Identity is based on connected outputs, except that a closed lid omits
    # the physically connected but intentionally disabled internal panel.
    connected=$(connected_outputs)
    if [ "${1:-unknown}" = closed ]; then
        internal=$(internal_output "$connected")
        printf '%s\n' "$connected" | awk -v internal="$internal" '$1 != internal'
    else
        printf '%s\n' "$connected"
    fi
}

load_custom_layouts() {
    custom_layout_reset
    custom_dir=${XDISPLAY_CUSTOM_LAYOUT_DIR:-$HOME/.config/x11/display-layouts/custom}
    [ -d "$custom_dir" ] || return 0
    current_lid=${1:-${LID_STATE:-unknown}}
    current_outputs=$(custom_current_outputs "$current_lid")
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
        custom_records=$(custom_config_records "$custom_file") || custom_error=1
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
                            custom_validate_position_record "$value" || custom_error=1
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
            adapter_log_event custom-layout "${custom_file##*/}" 65 INVALID parse_failed
            continue
        }
        case "$custom_lid" in open|closed|any) ;; *) continue ;; esac
        case "$custom_match" in exact|contains) ;; *) continue ;; esac
        [ -n "$custom_outputs" ] || continue
        [ -n "$custom_primary" ] || continue
        custom_invalid=0
        while IFS= read -r custom_output; do
            [ -n "$custom_output" ] || continue
            custom_valid_output_name "$custom_output" || custom_invalid=1
        done <<EOF
$(custom_output_lines "$custom_outputs")
EOF
        custom_valid_output_name "$custom_primary" || custom_invalid=1
        while IFS= read -r custom_order_output; do
            [ -n "$custom_order_output" ] || continue
            custom_valid_output_name "$custom_order_output" || custom_invalid=1
        done <<EOF
$(custom_output_lines "$custom_order")
EOF
        while IFS= read -r custom_position; do
            [ -n "$custom_position" ] || continue
            custom_validate_position_record "$custom_position" || custom_invalid=1
        done <<EOF
$custom_positions
EOF
        [ "$custom_invalid" -eq 0 ] || continue
        [ -n "$custom_order" ] || custom_order=$custom_outputs
        custom_primary_in_set=1
        custom_output_lines "$custom_outputs" | grep -qxF "$custom_primary" || custom_primary_in_set=0
        [ "$custom_primary_in_set" -eq 1 ] || continue
        case "$custom_match" in
            exact) custom_output_set_equal "$custom_outputs" "$current_outputs" || continue ;;
            contains) custom_output_set_contains "$custom_outputs" "$current_outputs" || continue ;;
        esac
        case "$custom_lid:$current_lid" in
            any:*) custom_lid_rank=1 ;;
            open:open|closed:closed) custom_lid_rank=2 ;;
            *) continue ;;
        esac
        [ "$custom_match" = exact ] && custom_match_rank=2 || custom_match_rank=1
        custom_count=$(custom_output_lines "$custom_outputs" | sed '/^$/d' | wc -l | awk '{print $1}')
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
            best_order=$(custom_output_lines "$custom_order")
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

output_in_list() {
    printf '%s\n' "$1" |
        awk -v output="$2" '$1 == output { found = 1 } END { exit !found }'
}

output_active() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output && $12 == 1 { found = 1 }
            END { exit !found }
        '
}

output_primary() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output && $4 == 1 { found = 1 }
            END { exit !found }
        '
}

output_at_origin() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output && $12 == 1 &&
                $8 == 0 && $9 == 0 { found = 1 }
            END { exit !found }
        '
}

output_ready() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" '
            $1 == "output" && $2 == output && $10 == 1 { found = 1 }
            END { exit !found }
        '
}

output_target_mode() {
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

output_target_rate() {
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

output_at_target_mode() {
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

adapter_output_is_connected() {
    output_in_list "$(connected_outputs)" "$1"
}

adapter_validate_internal_outputs() {
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
        adapter_output_is_connected "$candidate" || {
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

    if [ "$(output_count "$valid_outputs")" -gt 1 ]; then
        invalid=1
    fi
    if [ "$invalid" -eq 1 ] || [ -z "$valid_outputs" ]; then
        adapter_log_event internal-outputs none 65 INVALID invalid_candidate
        return 1
    fi
    printf '%s\n' "$valid_outputs"
}

adapter_refresh_internal_outputs() {
    ADAPTER_INTERNAL_OUTPUTS=
    [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] || return 0

    if [ ! -x "$ADAPTER_PATH" ]; then
        if [ "$ADAPTER_UNAVAILABLE_LOGGED" -eq 0 ]; then
            adapter_log_event internal-outputs none 127 UNAVAILABLE adapter_missing
            ADAPTER_UNAVAILABLE_LOGGED=1
        fi
        return 0
    fi

    connected=$(connected_outputs)
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
    adapter_result=$(run_adapter internal-outputs)
    adapter_status=$?
    if [ "$adapter_status" -ne 0 ]; then
        ADAPTER_INTERNAL_CACHE_KEY=$cache_key
        ADAPTER_INTERNAL_CACHE_VALUE=
        return 0
    fi
    ADAPTER_INTERNAL_OUTPUTS=$(adapter_validate_internal_outputs "$connected" "$adapter_result") ||
        ADAPTER_INTERNAL_OUTPUTS=
    ADAPTER_INTERNAL_CACHE_KEY=$cache_key
    ADAPTER_INTERNAL_CACHE_VALUE=$ADAPTER_INTERNAL_OUTPUTS
}

adapter_mode_is_available() {
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

adapter_apply_expected_target() {
    output=$1
    mode=$2
    rate=$3
    XRANDR_PARSED=$(printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v OFS='\t' -v output="$output" -v mode="$mode" -v rate="$rate" '
            $1 == "output" && $2 == output { $23 = mode; $24 = rate }
            { print }
        ')
}

adapter_refresh_expected_target() {
    ADAPTER_EXPECTED_OUTPUT=
    ADAPTER_EXPECTED_VALID=0
    ADAPTER_EXPECTED_PRESENT=0
    [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] || return 0
    [ -x "$ADAPTER_PATH" ] || return 0

    connected=$(connected_outputs)
    internal=$(internal_output "$connected")
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
        expected=$(run_adapter expected-mode "$internal")
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
        adapter_log_event expected-mode "$internal" 65 INVALID invalid_output_shape
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
            adapter_log_event expected-mode "$internal" 65 INVALID invalid_mode_format
            ADAPTER_EXPECTED_CACHE_VALID=0
            return 0
        }
    if [ "$expected_rate" != - ]; then
        printf '%s\n' "$expected_rate" |
            grep -Eq '^[1-9][0-9]*(\.[0-9]+)?$' || {
                adapter_log_event expected-mode "$internal" 65 INVALID invalid_rate_format
                ADAPTER_EXPECTED_CACHE_VALID=0
                return 0
            }
    fi

    ADAPTER_EXPECTED_OUTPUT=$internal
    ADAPTER_EXPECTED_VALID=1
    if adapter_mode_is_available "$internal" "$expected_mode" "$expected_rate"; then
        ADAPTER_EXPECTED_PRESENT=1
        adapter_apply_expected_target "$internal" "$expected_mode" "$expected_rate"
    else
        if [ "$cache_key" != "$ADAPTER_EXPECTED_MISSING_LOG_KEY" ]; then
            adapter_log_event expected-mode "$internal" 0 MISSING expected_mode_missing
            ADAPTER_EXPECTED_MISSING_LOG_KEY=$cache_key
        fi
    fi
}

verify_target_modes() {
    old_ifs=$IFS
    IFS='
'
    for output in $1; do
        output_at_target_mode "$output" || { IFS=$old_ifs; return 1; }
    done
    IFS=$old_ifs
}

topology_signature() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '
            $1 == "output" { printf "%s:%s:%s:%s,", $2, $3, $11, $22 }
        '
    printf 'custom:%s:%s\n' "$CUSTOM_LAYOUT_NAME" "$CUSTOM_LAYOUT_MTIME"
}

internal_output() {
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
        if output_in_list "$outputs" "$candidate"; then
            printf '%s\n' "$candidate"
            return
        fi
    done
}

external_outputs() {
    printf '%s\n' "$1" |
        awk -v internal="$2" '$1 != internal'
}

usable_outputs() {
    old_ifs=$IFS
    IFS='
'
    for output in $1; do
        if output_active "$output" || output_ready "$output"; then
            printf '%s\n' "$output"
        fi
    done
    IFS=$old_ifs
}

choose_primary() {
    outputs=$1

    old_ifs=$IFS
    IFS='
'
    for output in $outputs; do
        if output_primary "$output"; then
            printf '%s\n' "$output"
            IFS=$old_ifs
            return
        fi
    done
    for output in $outputs; do
        if output_active "$output"; then
            printf '%s\n' "$output"
            IFS=$old_ifs
            return
        fi
    done
    IFS=$old_ifs

    printf '%s\n' "$outputs" | awk 'NF { print; exit }'
}

verify_active_outputs() {
    old_ifs=$IFS
    IFS='
'
    for output in $1; do
        output_active "$output" || { IFS=$old_ifs; return 1; }
    done
    IFS=$old_ifs
}

snapshot_has_pending_outputs() {
    lid=$1
    outputs=$(connected_outputs)
    internal=$(internal_output "$outputs")
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v lid="$lid" -v internal="$internal" '
            $1 == "output" && $14 == 1 &&
                !(lid == "closed" && $2 == internal) { found = 1 }
            END { exit !found }
        '
}

snapshot_has_stale_outputs() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '
            $1 == "output" && $13 == 1 { found = 1 }
            END { exit !found }
        '
}

snapshot_health() {
    lid=$1
    if snapshot_has_stale_outputs; then
        printf '%s\n' stale
    elif snapshot_has_pending_outputs "$lid"; then
        printf '%s\n' pending
    elif [ -z "$(connected_outputs)" ]; then
        printf '%s\n' no-connected-output
    else
        printf '%s\n' ready
    fi
}

clear_stale_outputs() {
    lid=$1
    stale_outputs=$(printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '$1 == "output" && $13 == 1 { print $2 }')
    [ -n "$stale_outputs" ] || return 0

    connected=$(connected_outputs)
    active_connected=$(printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '
            $1 == "output" && $3 == "connected" && $12 == 1 { print $2 }
        ')

    # Bring up and verify a replacement before removing the last framebuffer
    # anchor. With a closed lid, only an external output is a safe candidate.
    if [ -z "$active_connected" ]; then
        candidates=$connected
        internal=$(internal_output "$connected")
        if [ "$lid" = closed ] && [ -n "$internal" ]; then
            candidates=$(external_outputs "$connected" "$internal")
        fi
        candidates=$(usable_outputs "$candidates")
        [ -n "$candidates" ] || return 1
        replacement=$(choose_primary "$candidates")
        [ -n "$replacement" ] || return 1
        set_output_primary_at_origin "$replacement" || return 1
        read_snapshot --current || return 1
        output_active "$replacement" || return 1
    fi

    set --
    old_ifs=$IFS
    IFS='
'
    for output in $stale_outputs; do
        set -- "$@" --output "$output" --off
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    read_snapshot --current || return 1
    ! snapshot_has_stale_outputs
}

set_output_primary_at_origin() {
    output=$1
    set -- --output "$output" --primary
    if ! output_at_target_mode "$output"; then
        target_mode=$(output_target_mode "$output")
        [ "$target_mode" != - ] || return 1
        set -- "$@" --mode "$target_mode"
        target_rate=$(output_target_rate "$output")
        [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
    fi
    set -- "$@" --pos 0x0
    xrandr "$@"
}

output_relation() {
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

output_right_of() {
    output_relation "$1" "$2" right
}

# Return external outputs in RandR connector order. A future configuration
# layer can replace this function without changing the layout callers.
sort_external_outputs() {
    requested=$1
    [ -n "$requested" ] || return 0
    connected=$(connected_outputs)
    for output in $connected; do
        output_in_list "$requested" "$output" || continue
        printf '%s\n' "$output"
    done
}

first_output() {
    printf '%s\n' "$1" | awk 'NF { print; exit }'
}

# Apply a primary plus a chained external layout in one RandR mutation.
# Each output is positioned relative to the previous output, preserving the
# existing target-mode and primary-selection helpers.
apply_extend_layout() {
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
    if ! output_at_target_mode "$primary"; then
        target_mode=$(output_target_mode "$primary")
        [ "$target_mode" != - ] || return 1
        set -- "$@" --mode "$target_mode"
        target_rate=$(output_target_rate "$primary")
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
    sorted=$(sort_external_outputs "$outputs" | tr '\n' ' ')
    old_ifs=$IFS
    IFS=' '
    for output in $sorted; do
        [ "$output" = "$primary" ] && continue
        set -- "$@" --output "$output"
        if ! output_at_target_mode "$output"; then
            target_mode=$(output_target_mode "$output")
            [ "$target_mode" != - ] || { IFS=$old_ifs; return 1; }
            set -- "$@" --mode "$target_mode"
            target_rate=$(output_target_rate "$output")
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
apply_custom_layout() {
    internal=$1
    externals=$2
    lid=${3:-open}
    [ -n "$CUSTOM_LAYOUT_NAME" ] || return 1
    primary=$CUSTOM_LAYOUT_PRIMARY
    [ -n "$primary" ] || return 1
    connected=$(connected_outputs)
    output_in_list "$connected" "$primary" || return 1

    set --
    configured_outputs=$CUSTOM_LAYOUT_ORDER
    [ -n "$configured_outputs" ] || configured_outputs=$primary
    old_ifs=$IFS
    IFS='
'
    for output in $configured_outputs; do
        [ -n "$output" ] || continue
        output_in_list "$connected" "$output" || continue
        position_line=$(printf '%s\n' "$CUSTOM_LAYOUT_POSITIONS" |
            awk -F '\|' -v output="$output" '$1 == output { print; exit }')
        [ -n "$position_line" ] || continue
        saved_x=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $2 }')
        saved_y=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $3 }')
        saved_mode=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $4 }')
        saved_rate=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $5 }')
        [ -n "$saved_rate" ] || saved_rate=-
        custom_valid_position_value "$saved_x" || { IFS=$old_ifs; return 1; }
        custom_valid_position_value "$saved_y" || { IFS=$old_ifs; return 1; }
        custom_valid_mode_value "$saved_mode" || { IFS=$old_ifs; return 1; }
        custom_valid_rate_value "$saved_rate" || { IFS=$old_ifs; return 1; }
        set -- "$@" --output "$output"
        [ "$saved_mode" = - ] || set -- "$@" --mode "$saved_mode"
        [ "$saved_rate" = - ] || set -- "$@" --rate "$saved_rate"
        set -- "$@" --pos "${saved_x}x${saved_y}"
        [ "$output" = "$primary" ] && set -- "$@" --primary
        if [ "${XDISPLAY_LAYOUT_DRY_RUN:-0}" = 1 ]; then
            custom_primary_suffix=
            [ "$output" = "$primary" ] && custom_primary_suffix=' primary'
            printf 'custom_output=%s pos=%sx%s mode=%s rate=%s%s\n' \
                "$output" "$saved_x" "$saved_y" "$saved_mode" "$saved_rate" \
                "$custom_primary_suffix"
        fi
    done
    IFS=$old_ifs

    # Add outputs not recorded by a contains snapshot without hiding them.
    anchor=$primary
    for configured_output in $configured_outputs; do
        output_in_list "$connected" "$configured_output" || continue
        anchor=$configured_output
    done
    for output in $(sort_external_outputs "$externals"); do
        printf '%s\n' "$configured_outputs" | grep -qxF "$output" && continue
        set -- "$@" --output "$output" --auto "--${CONFIG_EXTERNAL_POSITION}-of" "$anchor"
        if [ "${XDISPLAY_LAYOUT_DRY_RUN:-0}" = 1 ]; then
            printf 'custom_extra=%s relation=--%s-of anchor=%s\n' "$output" \
                "$CONFIG_EXTERNAL_POSITION" "$anchor"
        fi
        anchor=$output
    done
    if [ "$lid" = closed ] && [ -n "$internal" ] && [ "$internal" != "$primary" ]; then
        set -- "$@" --output "$internal" --off
    fi
    [ "$#" -gt 0 ] || return 1
    if [ "${XDISPLAY_LAYOUT_DRY_RUN:-0}" = 1 ]; then
        printf 'layout=custom name=%s\n' "$CUSTOM_LAYOUT_NAME"
        printf 'custom_primary=%s\n' "$primary"
        return 0
    fi
    xrandr "$@"
}

custom_output_at_saved_position() {
    output=$1
    position_line=$(printf '%s\n' "$CUSTOM_LAYOUT_POSITIONS" |
        awk -F '\|' -v output="$output" '$1 == output { print; exit }')
    [ -n "$position_line" ] || return 0
    saved_x=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $2 }')
    saved_y=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $3 }')
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$output" -v x="$saved_x" -v y="$saved_y" '
            $1 == "output" && $2 == output && $12 == 1 &&
                ($8 + 0) == (x + 0) && ($9 + 0) == (y + 0) { found = 1 }
            END { exit !found }
        '
}

custom_output_at_saved_mode() {
    output=$1
    position_line=$(printf '%s\n' "$CUSTOM_LAYOUT_POSITIONS" |
        awk -F '\|' -v output="$output" '$1 == output { print; exit }')
    [ -n "$position_line" ] || return 0
    saved_mode=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $4 }')
    saved_rate=$(printf '%s\n' "$position_line" | awk -F '\|' '{ print $5 }')
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$output" -v mode="$saved_mode" -v rate="$saved_rate" '
            $1 == "output" && $2 == output && $12 == 1 && $15 == mode &&
                (rate == "-" || ($16 + 0) == (rate + 0)) { found = 1 }
            END { exit !found }
        '
}

custom_layout_converged() {
    [ -n "$CUSTOM_LAYOUT_NAME" ] || return 1
    old_ifs=$IFS
    IFS='
'
    for output in $CUSTOM_LAYOUT_ORDER; do
        [ -n "$output" ] || continue
        output_active "$output" || { IFS=$old_ifs; return 1; }
        custom_output_at_saved_mode "$output" || { IFS=$old_ifs; return 1; }
        custom_output_at_saved_position "$output" || { IFS=$old_ifs; return 1; }
    done
    IFS=$old_ifs
    output_primary "$CUSTOM_LAYOUT_PRIMARY" || return 1
    return 0
}

outputs_extended_from() {
    anchor=$1
    outputs=$2
    old_ifs=$IFS
    IFS='
'
    for output in $outputs; do
        [ "$output" = "$anchor" ] && continue
        output_right_of "$output" "$anchor" ||
            { IFS=$old_ifs; return 1; }
        anchor=$output
    done
    IFS=$old_ifs
}

outputs_extended_from_direction() {
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
        output_relation "$output" "$anchor" "$relation" || {
            IFS=$old_ifs
            return 1
        }
        anchor=$output
    done
    IFS=$old_ifs
}

outputs_mirrored() {
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

try_internal_restore() {
    output=$1
    restore_command=${XDISPLAY_RESTORE_COMMAND:-}
    [ -n "$restore_command" ] || return 1
    command -v "$restore_command" >/dev/null 2>&1 || return 1
    command -v timeout >/dev/null 2>&1 || return 1
    timeout "$ADAPTER_TIMEOUT" "$restore_command" "$output" >/dev/null 2>&1 || true
    read_snapshot &&
        { output_ready "$output" || output_active "$output"; }
}

try_adapter_restore() {
    output=$1
    [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] || return 127
    [ -x "$ADAPTER_PATH" ] || return 127
    [ "$ADAPTER_RESTORE_ATTEMPTED" -eq 0 ] || return 1
    ADAPTER_RESTORE_ATTEMPTED=1
    if [ "$ADAPTER_EXPECTED_VALID" -eq 1 ] &&
        [ "$ADAPTER_EXPECTED_PRESENT" -eq 1 ]; then
        return 1
    fi

    run_adapter restore-internal "$output" >/dev/null || return 1
    read_snapshot || return 1
    if [ "$ADAPTER_EXPECTED_VALID" -eq 1 ]; then
        [ "$ADAPTER_EXPECTED_OUTPUT" = "$output" ] &&
            [ "$ADAPTER_EXPECTED_PRESENT" -eq 1 ]
    else
        output_ready "$output" || output_active "$output"
    fi
}

adapter_expected_mode_missing() {
    [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] || return 1
    [ "$ADAPTER_EXPECTED_VALID" -eq 1 ] || return 1
    [ "$ADAPTER_EXPECTED_PRESENT" -eq 0 ]
}

recover_or_degrade_adapter_target() {
    output=$1
    adapter_expected_mode_missing || return 0
    try_adapter_restore "$output" && return 0
    # Preserve the legacy recovery hook as the next compatibility fallback
    # when the explicitly enabled adapter cannot converge the expected mode.
    try_internal_restore "$output" || :
    if [ "$ADAPTER_EXPECTED_OUTPUT" = "$output" ] &&
        [ "$ADAPTER_EXPECTED_PRESENT" -eq 1 ]; then
        return 0
    fi
    output_ready "$output" || return 1
    ADAPTER_EXPECTED_VALID=0
    ADAPTER_EXPECTED_PRESENT=0
    adapter_log_event expected-mode "$output" 0 FALLBACK randr_preferred
    return 0
}

configure_single() {
    output=$1
    if ! snapshot_has_stale_outputs &&
        output_active "$output" &&
        output_primary "$output" &&
        output_at_origin "$output" &&
        output_at_target_mode "$output"; then
        return 0
    fi

    output_active "$output" || output_ready "$output" || return 1
    set_output_primary_at_origin "$output" || return 1

    read_snapshot &&
        ! snapshot_has_stale_outputs &&
        output_active "$output" &&
        output_primary "$output" &&
        output_at_origin "$output" &&
        output_at_target_mode "$output"
}

configure_closed() {
    internal=$1
    externals=$(usable_outputs "$2")
    [ -n "$externals" ] || return 1
    sorted_externals=$(sort_external_outputs "$externals")
    if [ -n "$CUSTOM_LAYOUT_NAME" ] && [ "$CURRENT_DISPLAY_STATE" != "$STATE_NONE" ]; then
        apply_custom_layout "$internal" "$sorted_externals" closed || return 1
        read_snapshot || return 1
        if custom_layout_converged &&
            { [ -z "$internal" ] || ! output_active "$internal"; }; then
            return 0
        fi
        custom_layout_reset
    fi
    case "$CURRENT_DISPLAY_STATE" in
        EXTERNAL_ONLY|MULTI_EXTERNAL)
            if [ "$MULTI_SCREEN_LAYOUT_READY" -eq 1 ]; then
                externals=$sorted_externals
                primary=$(choose_layout_primary "$externals")
                layout_mode=extend_chain
            else
                primary=$(choose_primary "$externals")
                layout_mode=legacy
            fi
            ;;
        *)
            primary=$(choose_primary "$externals")
            layout_mode=legacy
            ;;
    esac
    [ -n "$primary" ] || return 1

    if [ "$layout_mode" = extend_chain ]; then
        # Keep an external primary active before applying the external chain
        # and internal-off transition in one RandR mutation.
        if ! snapshot_has_stale_outputs &&
            output_primary "$primary" &&
            output_at_origin "$primary" &&
            ! output_active "$internal" &&
            verify_active_outputs "$externals" &&
            verify_target_modes "$externals" &&
            outputs_extended_from_direction "$primary" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"; then
            return 0
        fi
        if ! output_active "$primary"; then
            output_ready "$primary" || return 1
            set_output_primary_at_origin "$primary" || return 1
            read_snapshot || return 1
            output_active "$primary" && output_at_target_mode "$primary" || return 1
        fi
        apply_extend_layout "$primary" "$externals" \
            "$CONFIG_EXTERNAL_POSITION" "$internal" || return 1
        read_snapshot || return 1
        ! snapshot_has_stale_outputs &&
            output_primary "$primary" &&
            output_at_origin "$primary" &&
            ! output_active "$internal" &&
            verify_active_outputs "$externals" &&
            verify_target_modes "$externals" &&
            outputs_extended_from_direction "$primary" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"
        return
    fi

    if ! snapshot_has_stale_outputs &&
        output_primary "$primary" &&
        output_at_origin "$primary" &&
        ! output_active "$internal" &&
        verify_active_outputs "$externals" &&
        verify_target_modes "$externals" &&
            outputs_extended_from_direction "$primary" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"; then
        return 0
    fi

    # If the external primary is not active yet, prepare it before turning off
    # the internal panel. This keeps a usable screen alive during link training.
    if ! output_active "$primary"; then
        output_ready "$primary" || return 1
        set_output_primary_at_origin "$primary" || return 1
        read_snapshot || return 1
        output_active "$primary" && output_at_target_mode "$primary" || return 1
    fi

    set -- --output "$primary" --primary
    if ! output_at_target_mode "$primary"; then
        target_mode=$(output_target_mode "$primary")
        [ "$target_mode" != - ] || return 1
        set -- "$@" --mode "$target_mode"
        target_rate=$(output_target_rate "$primary")
        [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
    fi
    set -- "$@" --pos 0x0 --output "$internal" --off
    anchor=$primary
    old_ifs=$IFS
    IFS='
'
    for output in $externals; do
        [ "$output" = "$primary" ] && continue
        set -- "$@" --output "$output"
        if ! output_at_target_mode "$output"; then
            target_mode=$(output_target_mode "$output")
            [ "$target_mode" != - ] || { IFS=$old_ifs; return 1; }
            set -- "$@" --mode "$target_mode"
            target_rate=$(output_target_rate "$output")
            [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
        fi
        set -- "$@" "--${CONFIG_EXTERNAL_POSITION}-of" "$anchor"
        anchor=$output
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    read_snapshot || return 1
    ! snapshot_has_stale_outputs &&
        output_primary "$primary" &&
        output_at_origin "$primary" &&
        ! output_active "$internal" &&
        verify_active_outputs "$externals" &&
        verify_target_modes "$externals" &&
            outputs_extended_from_direction "$primary" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"
}

configure_open() {
    internal=$1
    externals=$(usable_outputs "$2")
    sorted_externals=$(sort_external_outputs "$externals")
    layout_mode=legacy
    case "$CURRENT_DISPLAY_STATE" in
        DUAL_EXTEND|MULTI_EXTEND)
            if [ "$MULTI_SCREEN_LAYOUT_READY" -eq 1 ]; then
                externals=$sorted_externals
                layout_mode=extend_chain
            fi
            ;;
    esac

    if adapter_expected_mode_missing "$internal"; then
        recover_or_degrade_adapter_target "$internal" || return 1
    fi

    if [ -n "$CUSTOM_LAYOUT_NAME" ] && [ "$CURRENT_DISPLAY_STATE" != "$STATE_NONE" ]; then
        apply_custom_layout "$internal" "$sorted_externals" open || return 1
        read_snapshot || return 1
        if custom_layout_converged; then
            return 0
        fi
        # A stale custom snapshot must not strand the display; the caller's
        # existing retry path will re-read RandR and use the default planner.
        custom_layout_reset
        layout_mode=legacy
    fi

    if ! snapshot_has_stale_outputs &&
        output_primary "$internal" &&
        output_active "$internal" &&
        output_at_origin "$internal" &&
        verify_active_outputs "$externals" &&
        output_at_target_mode "$internal" &&
        verify_target_modes "$externals" &&
        outputs_extended_from_direction "$internal" "$externals" \
            "$CONFIG_EXTERNAL_POSITION"; then
        return 0
    fi

    if ! output_active "$internal"; then
        if ! output_ready "$internal"; then
            if adapter_expected_mode_missing "$internal" &&
                [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] && [ -x "$ADAPTER_PATH" ] &&
                try_adapter_restore "$internal"; then
                :
            else
                try_internal_restore "$internal"
                return 1
            fi
        fi
        set_output_primary_at_origin "$internal" || return 1
        read_snapshot || return 1
        output_active "$internal" && output_at_target_mode "$internal" || return 1
    fi

    if [ "$layout_mode" = extend_chain ]; then
        apply_extend_layout "$internal" "$externals" \
            "$CONFIG_EXTERNAL_POSITION" || return 1
        read_snapshot || return 1
        ! snapshot_has_stale_outputs &&
            output_primary "$internal" &&
            output_active "$internal" &&
            output_at_origin "$internal" &&
            verify_active_outputs "$externals" &&
            output_at_target_mode "$internal" &&
            verify_target_modes "$externals" &&
            outputs_extended_from_direction "$internal" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"
        return
    fi

    set -- --output "$internal" --primary
    if ! output_at_target_mode "$internal"; then
        target_mode=$(output_target_mode "$internal")
        [ "$target_mode" != - ] || return 1
        set -- "$@" --mode "$target_mode"
        target_rate=$(output_target_rate "$internal")
        [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
    fi
    set -- "$@" --pos 0x0
    anchor=$internal
    old_ifs=$IFS
    IFS='
'
    for output in $externals; do
        set -- "$@" --output "$output"
        if ! output_at_target_mode "$output"; then
            target_mode=$(output_target_mode "$output")
            [ "$target_mode" != - ] || { IFS=$old_ifs; return 1; }
            set -- "$@" --mode "$target_mode"
            target_rate=$(output_target_rate "$output")
            [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
        fi
        set -- "$@" "--${CONFIG_EXTERNAL_POSITION}-of" "$anchor"
        anchor=$output
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    read_snapshot || return 1
    ! snapshot_has_stale_outputs &&
        output_primary "$internal" &&
        output_active "$internal" &&
        output_at_origin "$internal" &&
        verify_active_outputs "$externals" &&
        output_at_target_mode "$internal" &&
            verify_target_modes "$externals" &&
            outputs_extended_from_direction "$internal" "$externals" \
                "$CONFIG_EXTERNAL_POSITION"
}

configure_mirror() {
    outputs=$(usable_outputs "$1")
    count=$(output_count "$outputs")
    [ "$count" -gt 0 ] || return 1
    [ "$count" -gt 1 ] || { configure_single "$outputs"; return; }

    primary=$(choose_primary "$outputs")
    if ! snapshot_has_stale_outputs &&
        output_primary "$primary" &&
        output_at_origin "$primary" &&
        verify_active_outputs "$outputs" &&
        verify_target_modes "$outputs" &&
        outputs_mirrored "$primary" "$outputs"; then
        return 0
    fi

    set -- --output "$primary" --primary
    if ! output_at_target_mode "$primary"; then
        target_mode=$(output_target_mode "$primary")
        [ "$target_mode" != - ] || return 1
        set -- "$@" --mode "$target_mode"
        target_rate=$(output_target_rate "$primary")
        [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
    fi
    set -- "$@" --pos 0x0

    old_ifs=$IFS
    IFS='
'
    for output in $outputs; do
        [ "$output" = "$primary" ] && continue
        set -- "$@" --output "$output"
        if ! output_at_target_mode "$output"; then
            target_mode=$(output_target_mode "$output")
            [ "$target_mode" != - ] || { IFS=$old_ifs; return 1; }
            set -- "$@" --mode "$target_mode"
            target_rate=$(output_target_rate "$output")
            [ "$target_rate" = - ] || set -- "$@" --rate "$target_rate"
        fi
        set -- "$@" --same-as "$primary"
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    read_snapshot || return 1
    ! snapshot_has_stale_outputs &&
        output_primary "$primary" &&
        output_at_origin "$primary" &&
        verify_active_outputs "$outputs" &&
        verify_target_modes "$outputs" &&
        outputs_mirrored "$primary" "$outputs"
}

describe_policy() {
    lid=$1
    outputs=$(connected_outputs)
    count=$(output_count "$outputs")
    if [ "$count" -eq 0 ]; then
        printf '%s\n' no-connected-output
        return
    fi

    internal=$(internal_output "$outputs")
    if [ "$count" -eq 1 ]; then
        if [ "$lid" = closed ] && [ "$outputs" = "$internal" ]; then
            printf '%s\n' preserve-closed-internal
        elif [ "$outputs" = "$internal" ] &&
            ! output_ready "$internal" && ! output_active "$internal"; then
            printf '%s\n' restore-internal-then-single
        else
            printf '%s\n' single-output
        fi
        return
    fi

    case "$lid" in
        closed)
            if [ -n "$internal" ]; then
                printf '%s\n' extend-externals-and-disable-internal
            else
                printf '%s\n' mirror-fallback
            fi
            ;;
        open|unknown|absent)
            if [ -n "$internal" ]; then
                printf '%s\n' extend-from-internal
            else
                printf '%s\n' mirror-fallback
            fi
            ;;
    esac
}

state_names() {
    field=$1
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v field="$field" '
            $1 == "output" && $field == 1 {
                if (found++) printf ","
                printf "%s", $2
            }
            END { if (!found) printf "none"; printf "\n" }
        '
}

read_runtime_value() {
    value_file=$1
    if [ ! -e "$value_file" ]; then
        printf '%s\n' absent
        return
    fi
    if [ ! -r "$value_file" ]; then
        printf '%s\n' unreadable
        return
    fi
    IFS= read -r runtime_value < "$value_file" || :
    [ -n "${runtime_value:-}" ] || runtime_value=empty
    printf '%s\n' "$runtime_value"
}

display_status() {
    read_lid_state
    read_snapshot --current || {
        notify_problem "Cannot read the current RandR state."
        return 1
    }

    if [ "$LID_PRESENT" -eq 1 ]; then
        lid_present=yes
    else
        lid_present=no
    fi
    printf 'lid_present=%s\n' "$lid_present"
    printf 'lid_state=%s\n' "$LID_STATE"
    printf 'state=%s internal=%s external=%s\n' \
        "$CURRENT_DISPLAY_STATE" "$CURRENT_DISPLAY_INTERNAL_COUNT" \
        "$CURRENT_DISPLAY_EXTERNAL_COUNT"
    printf 'layout=%s\n' "$CURRENT_LAYOUT_FUNCTION"
    if [ -n "$CUSTOM_LAYOUT_NAME" ]; then
        printf 'custom=%s\n' "$CUSTOM_LAYOUT_NAME"
    else
        printf 'custom=none\n'
    fi
    printf 'config: timeout=%s kill-after=%s position=%s limit=%s retry=%s probe=%s pending=%s log=%s log_max=%s\n' \
        "$CONFIG_TIMEOUT_SECONDS" "$CONFIG_KILL_AFTER_SECONDS" \
        "$CONFIG_EXTERNAL_POSITION" "$CONFIG_APPLY_FAILURE_LIMIT" \
        "$CONFIG_APPLY_RETRY_TICKS" "$CONFIG_HARDWARE_PROBE_TICKS" \
        "$CONFIG_PENDING_PROBE_TICKS" "$CONFIG_LOG_PATH" \
        "$CONFIG_LOG_MAX_BYTES"
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '
            $1 == "screen" {
                printf "screen=number:%s minimum:%sx%s current:%sx%s maximum:%sx%s\n",
                    $2, $3, $4, $5, $6, $7, $8
            }
            $1 == "output" {
                printf "output=%s connection:%s primary:%s geometry:%s width:%s height:%s x:%s y:%s mode_ready:%s first_mode:%s active:%s stale:%s pending:%s current_mode:%s current_rate:%s preferred_mode:%s preferred_rate:%s target_mode:%s target_rate:%s mode_count:%s mode_signature:%s\n",
                    $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
                    $13, $14, $15, $16, $17, $18,
                    ($23 != "-" ? $23 : $19),
                    ($24 != "-" ? $24 : $20), $21, $22
            }
        '

    stale_outputs=$(state_names 13)
    pending_outputs=$(state_names 14)
    if [ "$stale_outputs" != none ]; then
        health=stale
    elif [ "$pending_outputs" != none ]; then
        health=pending
    elif [ -z "$(connected_outputs)" ]; then
        health=no-connected-output
    else
        health=ready
    fi
    printf 'policy=%s\n' "$(describe_policy "$LID_STATE")"
    printf 'stale_outputs=%s\n' "$stale_outputs"
    printf 'pending_outputs=%s\n' "$pending_outputs"
    printf 'health=%s\n' "$health"
    printf 'topology_signature=%s:%s|%s\n' \
        "$LID_PRESENT" "$LID_STATE" "$(topology_signature)"
    printf 'display_server=%s\n' "$display_server"
    printf 'lock_apply=%s\n' "$apply_lock"
    printf 'lock_watch=%s\n' "$watch_lock"
    printf 'generation_path=%s\n' "$generation_file"
    current_generation=$(read_runtime_value "$generation_file")
    printf 'generation=%s\n' "$current_generation"
    printf 'manual_marker_path=%s\n' "$manual_marker"
    marker_value=$(read_runtime_value "$manual_marker")
    case "$marker_value:$current_generation" in
        absent:*|unreadable:*|empty:*) marker_state=$marker_value ;;
        *:absent|*:unreadable|*:empty) marker_state=stale ;;
        "$current_generation:$current_generation") marker_state=current ;;
        *) marker_state=stale ;;
    esac
    printf 'manual_marker=%s\n' "$marker_state"
    printf 'legacy_internal_outputs=%s\n' \
        "${XDISPLAY_INTERNAL_OUTPUTS:-none}"
    legacy_restore=${XDISPLAY_RESTORE_COMMAND:-}
    if [ -z "$legacy_restore" ]; then
        printf 'legacy_restore_command=none\n'
    elif command -v "$legacy_restore" >/dev/null 2>&1; then
        printf 'legacy_restore_command=%s (available)\n' "$legacy_restore"
    else
        printf 'legacy_restore_command=%s (unavailable)\n' "$legacy_restore"
    fi
}

apply_snapshot() {
    lid=$1
    # Bound adapter mutation to one attempt per layout transaction. A later
    # watcher cycle may retry after the existing failure cooldown.
    ADAPTER_RESTORE_ATTEMPTED=0
    clear_stale_outputs "$lid" || return 1
    outputs=$(connected_outputs)
    count=$(output_count "$outputs")
    [ "$count" -gt 0 ] || return 1
    internal=$(internal_output "$outputs")

    if [ "$count" -eq 1 ]; then
        if [ "$lid" = closed ] && [ "$outputs" = "$internal" ]; then
            ! snapshot_has_stale_outputs
            return
        fi
        if [ -n "$CUSTOM_LAYOUT_NAME" ] && [ "$CURRENT_DISPLAY_STATE" != "$STATE_NONE" ]; then
            apply_custom_layout "$internal" "$outputs" "$lid" || return 1
            read_snapshot || return 1
            custom_layout_converged || return 1
            return 0
        fi
        if [ "$lid" = closed ] &&
            [ "$CURRENT_DISPLAY_STATE" = EXTERNAL_ONLY ]; then
            configure_closed "$internal" \
                "$(external_outputs "$outputs" "$internal")"
            return
        fi
        if [ "$outputs" = "$internal" ] &&
            adapter_expected_mode_missing "$internal"; then
            recover_or_degrade_adapter_target "$internal" || return 1
        fi
        if [ "$outputs" = "$internal" ] && ! output_ready "$internal" &&
            ! output_active "$internal"; then
            if adapter_expected_mode_missing "$internal" &&
                [ "$XDISPLAY_USE_ADAPTER" -eq 1 ] && [ -x "$ADAPTER_PATH" ] &&
                try_adapter_restore "$internal"; then
                :
            else
                try_internal_restore "$internal"
                return 1
            fi
        fi
        configure_single "$outputs"
        return
    fi

    case "$lid" in
        closed)
            case "$CURRENT_DISPLAY_STATE" in
                EXTERNAL_ONLY|MULTI_EXTERNAL)
                    configure_closed "$internal" \
                        "$(external_outputs "$outputs" "$internal")"
                    ;;
                *)
                    if [ -n "$internal" ]; then
                        configure_closed "$internal" \
                            "$(external_outputs "$outputs" "$internal")"
                    else
                        configure_mirror "$outputs"
                    fi
                    ;;
            esac
            ;;
        open|unknown|absent)
            if [ -n "$internal" ]; then
                configure_open "$internal" "$(external_outputs "$outputs" "$internal")"
            else
                configure_mirror "$outputs"
            fi
            ;;
    esac
}

apply_display_config() {
    lid=$1
    flock -n 8 || return 75
    apply_snapshot "$lid"
    result=$?
    flock -u 8
    return "$result"
}

watch_cleanup() {
    cleanup_result=$?
    trap - 0 1 2 15

    if [ -n "${watch_generation:-}" ] && [ -r "$generation_file" ]; then
        IFS= read -r stored_generation < "$generation_file" || :
        if [ "$stored_generation" = "$watch_generation" ]; then
            rm -f "$generation_file"
        fi
    fi
    flock -u 9 2>/dev/null || :
    return "$cleanup_result"
}

start_watch_generation() {
    watch_generation=$user_id-$$
    generation_temp=$generation_file.tmp.$$

    # A manual marker can only belong to the watcher generation that created
    # it. Stage 2 does not write markers yet, but it invalidates old sessions.
    rm -f "$manual_marker" || return 1
    old_umask=$(umask)
    umask 077
    if ! printf '%s\n' "$watch_generation" > "$generation_temp" ||
        ! mv "$generation_temp" "$generation_file"; then
        rm -f "$generation_temp"
        umask "$old_umask"
        return 1
    fi
    umask "$old_umask"
}

watch_displays() {
    exec 9>"$watch_lock" || return 1
    if ! flock -w "$WATCH_LOCK_WAIT" 9; then
        printf '%s\n' "xdisplay.sh watcher is already running." >&2
        return 0
    fi

    trap 'watch_cleanup' 0
    trap 'exit 129' 1
    trap 'exit 130' 2
    trap 'exit 143' 15
    if ! start_watch_generation; then
        printf '%s\n' "Cannot initialize the xdisplay watcher generation." >&2
        return 1
    fi

    observed_lid=
    observed_drm=
    observed_key=
    observed_health=
    applied_key=
    applied_health=
    apply_failure_state=
    apply_failures=0
    apply_retry_ticks=0
    poll_ticks=0
    fast_checks=0
    hardware_probe_ticks=$HARDWARE_PROBE_TICKS
    pending_outputs=0
    probe_pending=0
    snapshot_failures=0

    while :; do
        read_lid_state
        current_lid=$LID_STATE
        current_drm=$(drm_signature)
        force_probe=$probe_pending
        lid_closing=0
        if [ "$current_lid" != "$observed_lid" ]; then
            if [ "$observed_lid" = open ] && [ "$current_lid" = closed ]; then
                lid_closing=1
            fi
            fast_checks=$FAST_WINDOW_CHECKS
            poll_ticks=0
        fi
        if [ "$current_drm" != "$observed_drm" ]; then
            force_probe=1
            probe_pending=1
            fast_checks=$FAST_WINDOW_CHECKS
            poll_ticks=0
        fi

        if [ "$poll_ticks" -le 0 ]; then
            snapshot_option=--current
            pending_layout=0
            if { [ "$observed_key" != "$applied_key" ] ||
                [ "$observed_health" != "$applied_health" ]; } &&
                [ "$apply_failures" -lt "$APPLY_FAILURE_LIMIT" ]; then
                pending_layout=1
            elif [ "$pending_outputs" -eq 1 ] &&
                [ "$apply_failures" -lt "$APPLY_FAILURE_LIMIT" ]; then
                pending_layout=1
            fi
            if [ "$lid_closing" -eq 0 ]; then
                if [ "$force_probe" -eq 1 ] ||
                    [ "$hardware_probe_ticks" -ge "$HARDWARE_PROBE_TICKS" ] ||
                    { [ "$pending_layout" -eq 1 ] &&
                        [ "$hardware_probe_ticks" -ge "$PENDING_PROBE_TICKS" ]; } ||
                    { [ "$fast_checks" -gt 0 ] &&
                        [ $((fast_checks % FAST_QUERY_INTERVAL)) -eq 0 ]; }; then
                    snapshot_option=--query
                    hardware_probe_ticks=0
                fi
            fi
            if read_snapshot "$snapshot_option"; then
                snapshot_failures=0
                [ "$snapshot_option" = --query ] && probe_pending=0
                current_key=$LID_PRESENT:$current_lid\|$(topology_signature)
                current_health=$(snapshot_health "$current_lid")
                current_state=$current_key\|health:$current_health
                if [ "$current_key" != "$observed_key" ] ||
                    [ "$current_health" != "$observed_health" ]; then
                    observed_key=$current_key
                    observed_health=$current_health
                    fast_checks=$FAST_WINDOW_CHECKS
                fi
                if [ "$current_state" != "$apply_failure_state" ]; then
                    apply_failure_state=$current_state
                    apply_failures=0
                    apply_retry_ticks=0
                fi
                apply_due=0
                if [ "$apply_retry_ticks" -le 0 ]; then
                    if [ "$apply_failures" -lt "$APPLY_FAILURE_LIMIT" ] ||
                        [ "$snapshot_option" = --query ]; then
                        apply_due=1
                    fi
                fi
                if { [ "$current_key" != "$applied_key" ] ||
                    [ "$current_health" != "$applied_health" ]; } &&
                    [ "$apply_due" -eq 1 ]; then
                    if apply_display_config "$current_lid"; then
                        applied_key=$LID_PRESENT:$current_lid\|$(topology_signature)
                        applied_health=$(snapshot_health "$current_lid")
                        observed_key=$applied_key
                        observed_health=$applied_health
                        apply_failure_state=$applied_key\|health:$applied_health
                        apply_failures=0
                        apply_retry_ticks=0
                        if snapshot_has_pending_outputs "$current_lid"; then
                            pending_outputs=1
                        else
                            pending_outputs=0
                            hardware_probe_ticks=0
                        fi
                    else
                        apply_result=$?
                        if [ "$apply_result" -ne 75 ] &&
                            [ "$apply_failures" -lt "$APPLY_FAILURE_LIMIT" ]; then
                            apply_failures=$((apply_failures + 1))
                        fi
                        apply_retry_ticks=$APPLY_RETRY_TICKS
                    fi
                fi
            else
                snapshot_failures=$((snapshot_failures + 1))
                if [ "$snapshot_failures" -ge "$SNAPSHOT_FAILURE_LIMIT" ]; then
                    printf '%s\n' \
                        "RandR snapshot failed $snapshot_failures consecutive times; exiting watcher." >&2
                    return 1
                fi
            fi

            if [ "$fast_checks" -gt 0 ]; then
                fast_checks=$((fast_checks - 1))
                poll_ticks=0
            else
                poll_ticks=$STABLE_POLL_TICKS
            fi
        else
            poll_ticks=$((poll_ticks - 1))
        fi

        observed_lid=$current_lid
        observed_drm=$current_drm
        hardware_probe_ticks=$((hardware_probe_ticks + 1))
        if [ "$apply_retry_ticks" -gt 0 ]; then
            apply_retry_ticks=$((apply_retry_ticks - 1))
        fi
        sleep 0.5
    done
}

if [ "${XDISPLAY_STATE_TEST:-0}" = 1 ]; then
    # Test-only read-only hook. It is evaluated before normal command and X
    # initialization, so state unit tests do not require a live X server.
    compute_display_state "${1:-unknown}" "${2:-}" "${3:-}"
    printf '%s\n' "$CURRENT_DISPLAY_STATE"
    exit 0
fi

if [ "${XDISPLAY_LAYOUT_TEST:-0}" = 1 ]; then
    # Test-only planner hook: exercise sorting and state-to-layout mapping
    # without requiring a live X server or issuing an xrandr mutation.
    layout_lid=${1:-open}
    layout_internal=${2:-}
    layout_external=${3:-}
    load_engine_config || :
    load_layout_config || :
    layout_direction=${4:-$CONFIG_EXTERNAL_POSITION}
    layout_external=$(printf '%s\n' "$layout_external" | tr ' ' '\n')
    # The hook receives its complete topology explicitly; do not let a
    # caller's legacy internal-output environment alter the mock planner.
    ADAPTER_INTERNAL_OUTPUTS=
    XDISPLAY_INTERNAL_OUTPUTS=
    XRANDR_PARSED=$(printf 'screen\t0\t320\t200\t320\t200\t16384\t16384\n'; for layout_output in $layout_internal $layout_external; do
        [ -n "$layout_output" ] || continue
        printf 'output\t%s\tconnected\t0\t-\t1920\t1080\t0\t0\t1\t1920x1080\t1\t0\t0\t1920x1080\t60\t1920x1080\t60\t1920x1080\t60\t1\t1920x1080@60\t-\t-\n' "$layout_output"
    done)
    refresh_display_state "$layout_lid"
    layout_sorted=$(sort_external_outputs "$layout_external")
    layout_primary=$layout_internal
    [ "$layout_lid" = closed ] && layout_primary=$(first_output "$layout_sorted")
    printf 'state=%s\n' "$CURRENT_DISPLAY_STATE"
    if [ -n "$CUSTOM_LAYOUT_NAME" ]; then
        XDISPLAY_LAYOUT_DRY_RUN=1 apply_custom_layout "$layout_internal" \
            "$layout_sorted" "$layout_lid"
    else
        XDISPLAY_LAYOUT_DRY_RUN=1 apply_extend_layout "$layout_primary" \
            "$layout_sorted" "$layout_direction"
    fi
    exit 0
fi

if [ "${XDISPLAY_CONFIG_TEST:-0}" = 1 ]; then
    load_engine_config || :
    load_layout_config || :
    printf 'timeout=%s\nkill-after=%s\napply-failure-limit=%s\napply-retry-ticks=%s\nhardware-probe-ticks=%s\npending-probe-ticks=%s\nlog-max-bytes=%s\nlog-path=%s\nexternal-position=%s\nexternal-primary=%s\nmirror-on-duplicate=%s\n' \
        "$CONFIG_TIMEOUT_SECONDS" "$CONFIG_KILL_AFTER_SECONDS" \
        "$CONFIG_APPLY_FAILURE_LIMIT" "$CONFIG_APPLY_RETRY_TICKS" \
        "$CONFIG_HARDWARE_PROBE_TICKS" "$CONFIG_PENDING_PROBE_TICKS" \
        "$CONFIG_LOG_MAX_BYTES" "$CONFIG_LOG_PATH" \
        "$CONFIG_EXTERNAL_POSITION" "$CONFIG_EXTERNAL_PRIMARY" \
        "$CONFIG_MIRROR_ON_DUPLICATE"
    exit 0
fi

usage() {
    printf 'Usage: %s [--apply|--watch|--status|--help]\n' "$0"
}

[ "$#" -le 1 ] || {
    usage >&2
    exit 2
}

case "${1:-}" in
    ""|--apply) command_mode=apply ;;
    --watch) command_mode=watch ;;
    --status) command_mode=status ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

# Optional configuration is loaded after help parsing so `--help` retains its
# lightweight, side-effect-free behavior. Invalid values only produce a
# diagnostic and leave the corresponding built-in default in place.
load_engine_config || :
load_layout_config || :

require_command xrandr
require_command stat
require_command tr
init_observation_roots || exit 1
init_runtime_paths || exit 1

case "$command_mode" in
    apply)
        require_command flock
        if ! open_apply_lock; then
            notify_problem "Cannot open the display layout lock: $apply_lock"
            exit 1
        fi
        read_lid_state
        current_lid=$LID_STATE
        read_snapshot && apply_display_config "$current_lid"
        result=$?
        if [ "$result" -eq 75 ]; then
            notify_problem "Another display configuration is currently in progress."
        elif [ "$result" -ne 0 ]; then
            notify_problem "The display layout is not ready yet; try again after the outputs finish connecting."
        fi
        exit "$result"
        ;;
    watch)
        require_command flock
        if ! open_apply_lock; then
            notify_problem "Cannot open the display layout lock: $apply_lock"
            exit 1
        fi
        watch_displays
        exit $?
        ;;
    status) display_status ;;
esac
