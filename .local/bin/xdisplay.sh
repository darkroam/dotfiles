#!/bin/sh

# Keep the X11 layout aligned with lid and RandR output state. Machines whose
# internal panel uses nonstandard names can list them in
# XDISPLAY_INTERNAL_OUTPUTS. XDISPLAY_RESTORE_COMMAND may name an optional
# device-local recovery helper.

FAST_WINDOW_CHECKS=10
FAST_QUERY_INTERVAL=2
PENDING_PROBE_TICKS=10
HARDWARE_PROBE_TICKS=120
STABLE_POLL_TICKS=1
SNAPSHOT_FAILURE_LIMIT=6
# A stable watcher attempts a snapshot once per second. This wait therefore
# outlasts the old watcher's consecutive-failure exit window.
WATCH_LOCK_WAIT=8

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

read_snapshot() {
    XRANDR_STATE=$(xrandr "${1:---current}" 2>/dev/null) || return 1

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
                $1 ~ /^[0-9]+x[0-9]+/ && first_mode[selected] == "-" {
                first_mode[selected] = $1
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
                    print "output", name[i], connection[i], primary[i],
                        geometry[i], width[i], height[i], x[i], y[i],
                        mode_ready, first_mode[i], active, stale, pending
                }
            }
        ') || return 1

    [ -n "$XRANDR_PARSED" ]
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

topology_signature() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '
            $1 == "output" { printf "%s:%s:%s,", $2, $3, $11 }
        '
}

internal_output() {
    outputs=$1
    standard_output=$(printf '%s\n' "$outputs" |
        awk '$1 ~ /^(eDP|LVDS|DSI)-?[0-9]/ { print; exit }')
    if [ -n "$standard_output" ]; then
        printf '%s\n' "$standard_output"
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

output_right_of() {
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' -v output="$1" -v anchor="$2" '
            $1 == "output" && ($2 == output || $2 == anchor) && $12 == 1 {
                if ($2 == output) {
                    output_x = $8
                    output_y = $9
                    have_output = 1
                } else {
                    anchor_width = $6
                    anchor_x = $8
                    anchor_y = $9
                    have_anchor = 1
                }
            }
            END {
                exit !(have_output && have_anchor &&
                    output_x == anchor_x + anchor_width &&
                    output_y == anchor_y)
            }
        '
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
    timeout 2 "$restore_command" "$output" >/dev/null 2>&1 || true
    read_snapshot &&
        { output_ready "$output" || output_active "$output"; }
}

configure_single() {
    output=$1
    if output_active "$output" &&
        output_primary "$output" &&
        output_at_origin "$output"; then
        return 0
    fi

    if output_active "$output"; then
        xrandr --output "$output" --primary --pos 0x0 || return 1
    else
        output_ready "$output" || return 1
        xrandr --output "$output" --primary --auto --pos 0x0 || return 1
    fi

    read_snapshot &&
        output_active "$output" &&
        output_primary "$output" &&
        output_at_origin "$output"
}

configure_closed() {
    internal=$1
    externals=$(usable_outputs "$2")
    [ -n "$externals" ] || return 1
    primary=$(choose_primary "$externals")
    [ -n "$primary" ] || return 1

    if output_primary "$primary" &&
        output_at_origin "$primary" &&
        ! output_active "$internal" &&
        verify_active_outputs "$externals" &&
        outputs_extended_from "$primary" "$externals"; then
        return 0
    fi

    # If the external primary is not active yet, prepare it before turning off
    # the internal panel. This keeps a usable screen alive during link training.
    if ! output_active "$primary"; then
        output_ready "$primary" || return 1
        xrandr --output "$primary" --primary --auto --pos 0x0 || return 1
        read_snapshot || return 1
        output_active "$primary" || return 1
    fi

    set -- --output "$primary" --primary --pos 0x0 --output "$internal" --off
    anchor=$primary
    old_ifs=$IFS
    IFS='
'
    for output in $externals; do
        [ "$output" = "$primary" ] && continue
        set -- "$@" --output "$output"
        output_active "$output" || set -- "$@" --auto
        set -- "$@" --right-of "$anchor"
        anchor=$output
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    read_snapshot || return 1
    output_primary "$primary" &&
        output_at_origin "$primary" &&
        ! output_active "$internal" &&
        verify_active_outputs "$externals" &&
        outputs_extended_from "$primary" "$externals"
}

configure_open() {
    internal=$1
    externals=$(usable_outputs "$2")

    if output_primary "$internal" &&
        output_active "$internal" &&
        output_at_origin "$internal" &&
        verify_active_outputs "$externals" &&
        outputs_extended_from "$internal" "$externals"; then
        return 0
    fi

    if ! output_active "$internal"; then
        if ! output_ready "$internal"; then
            try_internal_restore "$internal"
            return 1
        fi
        xrandr --output "$internal" --primary --auto --pos 0x0 || return 1
        read_snapshot || return 1
        output_active "$internal" || return 1
    fi

    set -- --output "$internal" --primary --pos 0x0
    anchor=$internal
    old_ifs=$IFS
    IFS='
'
    for output in $externals; do
        set -- "$@" --output "$output"
        output_active "$output" || set -- "$@" --auto
        set -- "$@" --right-of "$anchor"
        anchor=$output
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    read_snapshot || return 1
    output_primary "$internal" &&
        output_active "$internal" &&
        output_at_origin "$internal" &&
        verify_active_outputs "$externals" &&
        outputs_extended_from "$internal" "$externals"
}

configure_mirror() {
    outputs=$(usable_outputs "$1")
    count=$(output_count "$outputs")
    [ "$count" -gt 0 ] || return 1
    [ "$count" -gt 1 ] || { configure_single "$outputs"; return; }

    primary=$(choose_primary "$outputs")
    if output_primary "$primary" &&
        output_at_origin "$primary" &&
        verify_active_outputs "$outputs" &&
        outputs_mirrored "$primary" "$outputs"; then
        return 0
    fi

    set -- --output "$primary" --primary --pos 0x0
    output_active "$primary" || set -- "$@" --auto

    old_ifs=$IFS
    IFS='
'
    for output in $outputs; do
        [ "$output" = "$primary" ] && continue
        set -- "$@" --output "$output"
        output_active "$output" || set -- "$@" --auto
        set -- "$@" --same-as "$primary"
    done
    IFS=$old_ifs

    xrandr "$@" || return 1
    read_snapshot || return 1
    output_primary "$primary" &&
        output_at_origin "$primary" &&
        verify_active_outputs "$outputs" &&
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
    printf '%s\n' "$XRANDR_PARSED" |
        awk -F '\t' '
            $1 == "screen" {
                printf "screen=number:%s minimum:%sx%s current:%sx%s maximum:%sx%s\n",
                    $2, $3, $4, $5, $6, $7, $8
            }
            $1 == "output" {
                printf "output=%s connection:%s primary:%s geometry:%s width:%s height:%s x:%s y:%s mode_ready:%s first_mode:%s active:%s stale:%s pending:%s\n",
                    $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
                    $13, $14
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
    outputs=$(connected_outputs)
    count=$(output_count "$outputs")
    [ "$count" -gt 0 ] || return 1
    internal=$(internal_output "$outputs")

    if [ "$count" -eq 1 ]; then
        if [ "$lid" = closed ] && [ "$outputs" = "$internal" ]; then
            return 0
        fi
        if [ "$outputs" = "$internal" ] && ! output_ready "$internal" &&
            ! output_active "$internal"; then
            try_internal_restore "$internal"
            return 1
        fi
        configure_single "$outputs"
        return
    fi

    case "$lid" in
        closed)
            if [ -n "$internal" ]; then
                configure_closed "$internal" "$(external_outputs "$outputs" "$internal")"
            else
                configure_mirror "$outputs"
            fi
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
    applied_key=
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
            if [ "$observed_key" != "$applied_key" ] ||
                [ "$pending_outputs" -eq 1 ]; then
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
                if [ "$current_key" != "$observed_key" ]; then
                    observed_key=$current_key
                    fast_checks=$FAST_WINDOW_CHECKS
                fi
                if [ "$current_key" != "$applied_key" ]; then
                    if apply_display_config "$current_lid"; then
                        applied_key=$LID_PRESENT:$current_lid\|$(topology_signature)
                        observed_key=$applied_key
                        if snapshot_has_pending_outputs "$current_lid"; then
                            pending_outputs=1
                        else
                            pending_outputs=0
                            fast_checks=0
                            hardware_probe_ticks=0
                        fi
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
        sleep 0.5
    done
}

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
