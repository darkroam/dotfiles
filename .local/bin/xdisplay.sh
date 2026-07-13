#!/bin/sh

# Keep the X11 layout aligned with lid and RandR output state. Machines whose
# internal panel uses nonstandard names can list them in
# XDISPLAY_INTERNAL_OUTPUTS. XDISPLAY_RESTORE_COMMAND may name an optional
# device-local recovery helper.

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

require_command xrandr
require_command flock

runtime_dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
user_id=${UID:-$(id -u)}
apply_lock=$runtime_dir/xdisplay-$user_id.apply.lock
watch_lock=$runtime_dir/xdisplay-$user_id.watch.lock
FAST_WINDOW_CHECKS=10
FAST_QUERY_INTERVAL=2
HARDWARE_PROBE_TICKS=20
STABLE_POLL_TICKS=1

exec 8>"$apply_lock"

lid_state() {
    for state_file in /proc/acpi/button/lid/*/state; do
        [ -r "$state_file" ] || continue
        IFS=' ' read -r _ state < "$state_file"
        case "$state" in
            open|closed) printf '%s\n' "$state"; return ;;
        esac
    done
    printf '%s\n' unknown
}

drm_signature() {
    found=0
    for status_file in /sys/class/drm/card*-*/status; do
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
}

connected_outputs() {
    printf '%s\n' "$XRANDR_STATE" |
        awk '$2 == "connected" { print $1 }'
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
    printf '%s\n' "$XRANDR_STATE" |
        awk -v output="$1" '
            $1 == output && $2 == "connected" {
                for (i = 3; i <= NF; i++)
                    if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/) found = 1
            }
            END { exit !found }
        '
}

output_primary() {
    printf '%s\n' "$XRANDR_STATE" |
        awk -v output="$1" '
            $1 == output && $2 == "connected" {
                for (i = 3; i <= NF; i++)
                    if ($i == "primary") found = 1
            }
            END { exit !found }
        '
}

output_at_origin() {
    printf '%s\n' "$XRANDR_STATE" |
        awk -v output="$1" '
            $1 == output && $2 == "connected" {
                for (i = 3; i <= NF; i++) {
                    if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/) {
                        split($i, geometry, /[x+]/)
                        found = (geometry[3] == 0 && geometry[4] == 0)
                    }
                }
            }
            END { exit !found }
        '
}

output_ready() {
    printf '%s\n' "$XRANDR_STATE" |
        awk -v output="$1" '
            /^[^ \t]/ {
                selected = ($1 == output && $2 == "connected")
                next
            }
            selected && $1 ~ /^[0-9][^ \t]*x[0-9]/ { found = 1 }
            END { exit !found }
        '
}

topology_signature() {
    printf '%s\n' "$XRANDR_STATE" |
        awk '
            /^[^ \t]/ {
                selected = 0
                if ($2 == "connected") {
                    count++
                    name[count] = $1
                    selected = count
                }
                next
            }
            selected && $1 ~ /^[0-9][^ \t]*x[0-9]/ {
                modes[selected] = modes[selected] $1 ";"
            }
            END {
                for (i = 1; i <= count; i++)
                    printf "%s:%s,", name[i], modes[i]
            }
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

output_right_of() {
    printf '%s\n' "$XRANDR_STATE" |
        awk -v output="$1" -v anchor="$2" '
            ($1 == output || $1 == anchor) && $2 == "connected" {
                for (i = 3; i <= NF; i++) {
                    if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/) {
                        split($i, geometry, /[x+]/)
                        if ($1 == output) {
                            output_x = geometry[3]
                            output_y = geometry[4]
                            have_output = 1
                        } else {
                            anchor_width = geometry[1]
                            anchor_x = geometry[3]
                            anchor_y = geometry[4]
                            have_anchor = 1
                        }
                    }
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
        printf '%s\n' "$XRANDR_STATE" |
            awk -v output="$output" -v primary="$primary" '
                ($1 == output || $1 == primary) && $2 == "connected" {
                    for (i = 3; i <= NF; i++) {
                        if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/) {
                            split($i, geometry, /[x+]/)
                            if ($1 == output) {
                                output_x = geometry[3]
                                output_y = geometry[4]
                                have_output = 1
                            } else {
                                primary_x = geometry[3]
                                primary_y = geometry[4]
                                have_primary = 1
                            }
                        }
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
        open|unknown)
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

watch_displays() {
    exec 9>"$watch_lock"
    if ! flock -n 9; then
        printf '%s\n' "xdisplay.sh watcher is already running." >&2
        return 0
    fi

    observed_lid=
    observed_drm=
    observed_key=
    applied_key=
    poll_ticks=0
    fast_checks=0
    hardware_probe_ticks=$HARDWARE_PROBE_TICKS

    while :; do
        current_lid=$(lid_state)
        current_drm=$(drm_signature)
        force_probe=0
        if [ "$current_lid" != "$observed_lid" ]; then
            fast_checks=$FAST_WINDOW_CHECKS
            poll_ticks=0
        fi
        if [ "$current_drm" != "$observed_drm" ]; then
            force_probe=1
            fast_checks=$FAST_WINDOW_CHECKS
            poll_ticks=0
        fi

        if [ "$poll_ticks" -le 0 ]; then
            snapshot_option=--current
            if [ "$force_probe" -eq 1 ] ||
                [ "$hardware_probe_ticks" -ge "$HARDWARE_PROBE_TICKS" ] ||
                { [ "$fast_checks" -gt 0 ] &&
                    [ $((fast_checks % FAST_QUERY_INTERVAL)) -eq 0 ]; }; then
                snapshot_option=--query
                hardware_probe_ticks=0
            fi
            if read_snapshot "$snapshot_option"; then
                current_key=$current_lid\|$(topology_signature)
                if [ "$current_key" != "$observed_key" ]; then
                    observed_key=$current_key
                    fast_checks=$FAST_WINDOW_CHECKS
                fi
                if [ "$current_key" != "$applied_key" ]; then
                    if apply_display_config "$current_lid"; then
                        applied_key=$current_lid\|$(topology_signature)
                    fi
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

case "${1:-}" in
    "")
        current_lid=$(lid_state)
        read_snapshot && apply_display_config "$current_lid"
        result=$?
        if [ "$result" -eq 75 ]; then
            notify_problem "Another display configuration is currently in progress."
        elif [ "$result" -ne 0 ]; then
            notify_problem "The display layout is not ready yet; try again after the outputs finish connecting."
        fi
        exit "$result"
        ;;
    --watch) watch_displays ;;
    *)
        printf 'Usage: %s [--watch]\n' "$0" >&2
        exit 2
        ;;
esac
