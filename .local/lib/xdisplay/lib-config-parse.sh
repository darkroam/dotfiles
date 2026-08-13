# POSIX-INI parsing and configuration value validation.
# Functions: xdisplay_config_*, xdisplay_parse_config_records,
# xdisplay_expand_config_path.

xdisplay_config_diagnostic() {
    CONFIG_PARSE_ERROR=1
    printf 'xdisplay: config %s\n' "$1" >&2
}

xdisplay_config_is_integer() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

xdisplay_config_is_positive_integer() {
    xdisplay_config_is_integer "$1" && [ "$1" -gt 0 ]
}

xdisplay_config_is_position() {
    case "$1" in
        right|left|above|below) return 0 ;;
        *) return 1 ;;
    esac
}

xdisplay_config_is_primary_rule() {
    case "$1" in
        first|largest|manual) return 0 ;;
        *) return 1 ;;
    esac
}

xdisplay_config_is_boolean() {
    case "$1" in
        true|false|0|1) return 0 ;;
        *) return 1 ;;
    esac
}

# Emit section|key|value records from a small INI subset. Comments and blank
# lines are ignored; malformed records are reported to the caller as errors.
xdisplay_parse_config_records() {
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

xdisplay_expand_config_path() {
    case "$1" in
        \~/*) value=${1#\~/}; printf '%s/%s\n' "$HOME" "$value" ;;
        *) printf '%s\n' "$1" ;;
    esac
}
