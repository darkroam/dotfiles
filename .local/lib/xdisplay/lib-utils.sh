# Common diagnostics, dependency checks, and path metadata helpers.
# Functions: xdisplay_notify_problem, xdisplay_require_command,
# xdisplay_path_uid, xdisplay_path_mode.

xdisplay_notify_problem() {
    message=$1
    printf '%s\n' "$message" >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Display configuration unavailable" "$message"
    fi
}

xdisplay_require_command() {
    command -v "$1" >/dev/null 2>&1 && return
    xdisplay_notify_problem "xdisplay requires $1. Install it before using this feature."
    exit 127
}

xdisplay_path_uid() {
    stat -c %u "$1" 2>/dev/null
}

xdisplay_path_mode() {
    stat -c %a "$1" 2>/dev/null
}
