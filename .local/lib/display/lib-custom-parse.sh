# Custom-layout record parsing and output-set comparison.
# Functions: xdisplay_custom_layout_reset, xdisplay_custom_config_records,
# xdisplay_custom_output_lines, xdisplay_custom_output_set_*.

xdisplay_custom_layout_reset() {
    CUSTOM_LAYOUT_NAME=
    CUSTOM_LAYOUT_PRIMARY=
    CUSTOM_LAYOUT_ORDER=
    CUSTOM_LAYOUT_POSITIONS=
    CUSTOM_LAYOUT_LID=
    CUSTOM_LAYOUT_MATCH_MODE=
    CUSTOM_LAYOUT_MTIME=0
}

xdisplay_custom_config_records() {
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

xdisplay_custom_output_lines() {
    value=$1
    printf '%s\n' "$value" | tr ',' '\n' | awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }'
}

xdisplay_custom_output_set_equal() {
    left=$(xdisplay_custom_output_lines "$1" | sort -u)
    right=$(xdisplay_custom_output_lines "$2" | sort -u)
    [ "$(printf '%s\n' "$left" | sed '/^$/d')" = "$(printf '%s\n' "$right" | sed '/^$/d')" ]
}

xdisplay_custom_output_set_contains() {
    configured=$(xdisplay_custom_output_lines "$1" | sort -u)
    current=$(xdisplay_custom_output_lines "$2" | sort -u)
    [ -n "$(printf '%s\n' "$configured" | sed '/^$/d')" ] || return 1
    while IFS= read -r configured_output; do
        [ -n "$configured_output" ] || continue
        printf '%s\n' "$current" | grep -qxF "$configured_output" || return 1
    done <<EOF
$configured
EOF
}
