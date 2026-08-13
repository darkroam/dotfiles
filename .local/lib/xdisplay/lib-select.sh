# displayselect custom-layout persistence commands.
# Functions: xdisplay_select_valid_layout_name,
# xdisplay_select_custom_lid_state, xdisplay_select_custom_layout_snapshot,
# xdisplay_select_save_custom_layout, xdisplay_select_list_custom_layouts,
# xdisplay_select_delete_custom_layout.

xdisplay_select_valid_layout_name() {
    case "$1" in
        ''|.*|*[!A-Za-z0-9._-]*) return 1 ;;
        *) return 0 ;;
    esac
}

xdisplay_select_custom_lid_state() {
    for lid_file in /proc/acpi/button/lid/*/state; do
        [ -r "$lid_file" ] || continue
        IFS=' ' read -r _ lid_value < "$lid_file"
        case "$lid_value" in open|closed) printf '%s\n' "$lid_value"; return ;; esac
    done
    printf '%s\n' any
}

xdisplay_select_custom_layout_snapshot() {
    xrandr --query | awk '
        function geometry(value,    rest, pos, sign, dimensions, tail) {
            if (value !~ /^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+$/) return 0
            split(value, dimensions, "x")
            rest=dimensions[2]; pos=match(rest, /[+-]/)
            if (!pos) return 0
            w=dimensions[1]; h=substr(rest, 1, pos-1); tail=substr(rest,pos)
            sign=match(substr(tail,2), /[+-]/); if (!sign) return 0
            sign++; x=substr(tail,1,sign-1); y=substr(tail,sign); return 1
        }
        function flush(    i, token) {
            if (!name || !active || !have_geometry) return
            printf "%s\t%s\t%s\t%s\t%s\t%s\n", name, x+0, y+0, mode, rate, primary
        }
        /^[^ \t]/ {
            flush()
            name=""; active=0; have_geometry=0; primary=0; mode="-"; rate="-"; x=0; y=0
            if ($2 == "connected") {
                name=$1; active=1
                for (i=3; i<=NF; i++) {
                    if ($i == "primary") primary=1
                    if (geometry($i)) have_geometry=1
                }
                if (primary) primary_name=name
            }
            next
        }
        active && $1 ~ /^[0-9]+x[0-9]+$/ {
            if (mode != "-") next
            mode=$1
            for (i=2; i<=NF; i++) {
                token=$i
                if (token ~ /[*]/) {
                    gsub(/[+*]/, "", token)
                    rate=token
                    break
                }
            }
            next
        }
        END { flush() }
    '
}

xdisplay_select_save_custom_layout() {
    requested=${1:-}
    if [ -z "$requested" ]; then
        requested=$(date '+auto-%Y-%m-%d-%H-%M-%S')
    fi
    xdisplay_select_valid_layout_name "$requested" || {
        printf 'displayselect: invalid layout name: %s\n' "$requested" >&2
        return 2
    }
    snapshot=$(xdisplay_select_custom_layout_snapshot) || {
        printf 'displayselect: cannot read current display layout.\n' >&2
        return 1
    }
    [ -n "$snapshot" ] || {
        printf 'displayselect: no active outputs to save.\n' >&2
        return 1
    }
    saved_lid=$(xdisplay_select_custom_lid_state)
    if [ "$saved_lid" = closed ]; then
        snapshot=$(printf '%s\n' "$snapshot" | awk -F '\t' -v legacy="${XDISPLAY_INTERNAL_OUTPUTS:-}" '
            BEGIN { split(legacy, names, /[[:space:]]+/) }
            $1 ~ /^(eDP|LVDS|DSI)-?[0-9]+$/ { next }
            { for (i in names) if ($1 == names[i]) next }
            { print }
        ')
    fi
    [ -n "$snapshot" ] || {
        printf 'displayselect: no active external outputs to save while closed.\n' >&2
        return 1
    }
    old_umask=$(umask)
    umask 077
    mkdir -p "$custom_layout_dir" || { umask "$old_umask"; return 1; }
    chmod 700 "$custom_layout_dir" 2>/dev/null || :
    target=$custom_layout_dir/$requested.conf
    temp=$target.tmp.$$
    primary=$(printf '%s\n' "$snapshot" | awk -F '\t' '$6 == 1 { print $1; exit }')
    [ -n "$primary" ] || primary=$(printf '%s\n' "$snapshot" | awk -F '\t' 'NR == 1 { print $1 }')
    outputs=$(printf '%s\n' "$snapshot" | awk -F '\t' '{ if (NR > 1) printf ","; printf "%s", $1 }')
    {
        printf '[identity]\noutputs = %s\nlid = %s\nmatch_mode = exact\n\n' \
            "$outputs" "$saved_lid"
        printf '[layout]\nprimary = %s\norder = %s\n' "$primary" "$outputs"
        printf '%s\n' "$snapshot" | awk -F '\t' '{ printf "output_%d = %s|%s|%s|%s|%s\n", NR, $1, $2, $3, $4, $5 }'
    } > "$temp" || { rm -f "$temp"; umask "$old_umask"; return 1; }
    chmod 600 "$temp" 2>/dev/null || :
    mv -f "$temp" "$target" || { rm -f "$temp"; umask "$old_umask"; return 1; }
    chmod 600 "$target" 2>/dev/null || :
    umask "$old_umask"
    printf '%s\n' "$target"
}

xdisplay_select_list_custom_layouts() {
    [ -d "$custom_layout_dir" ] || return 0
    for layout_file in "$custom_layout_dir"/*.conf; do
        [ -f "$layout_file" ] || continue
        basename=${layout_file##*/}; basename=${basename%.conf}
        printf '%s\n' "$basename"
    done
}

xdisplay_select_delete_custom_layout() {
    name=$1
    xdisplay_select_valid_layout_name "$name" || return 2
    target=$custom_layout_dir/$name.conf
    [ -f "$target" ] || {
        printf 'displayselect: layout not found: %s\n' "$name" >&2
        return 1
    }
    rm -f "$target"
}
