# X11 observation roots, lid state, and shared runtime lock paths.
# Functions: xdisplay_init_*, xdisplay_normalize_display,
# xdisplay_open_apply_lock, xdisplay_read_lid_state, xdisplay_lid_state,
# xdisplay_drm_signature.

xdisplay_init_observation_roots() {
    proc_root=/proc
    sys_root=/sys
    if [ "${XDISPLAY_TEST_MODE:-0}" = 1 ]; then
        test_root=${XDISPLAY_TEST_ROOT:-}
        case "$test_root" in
            /*) ;;
            *)
                xdisplay_notify_problem "XDISPLAY_TEST_ROOT must be an absolute path in test mode."
                return 1
                ;;
        esac
        proc_root=$test_root/proc
        sys_root=$test_root/sys
    fi
}

xdisplay_normalize_display() {
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

xdisplay_init_runtime_paths() {
    user_id=${UID:-$(id -u)}
    case "$user_id" in
        ''|*[!0-9]*)
            xdisplay_notify_problem "Cannot determine a valid numeric user ID for display locks."
            return 1
            ;;
    esac

    runtime_dir=
    if [ -n "${XDG_RUNTIME_DIR:-}" ] &&
        [ -d "$XDG_RUNTIME_DIR" ] &&
        [ ! -L "$XDG_RUNTIME_DIR" ] &&
        [ -w "$XDG_RUNTIME_DIR" ] &&
        [ -x "$XDG_RUNTIME_DIR" ] &&
        [ "$(xdisplay_path_uid "$XDG_RUNTIME_DIR")" = "$user_id" ] &&
        [ "$(xdisplay_path_mode "$XDG_RUNTIME_DIR")" = 700 ]; then
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
            xdisplay_notify_problem "No writable and searchable runtime directory is available."
            return 1
        fi

        runtime_dir=$runtime_base/xdisplay-$user_id
        if [ -L "$runtime_dir" ]; then
            xdisplay_notify_problem "Refusing symlinked display runtime directory: $runtime_dir"
            return 1
        fi
        old_umask=$(umask)
        umask 077
        if ! mkdir -p "$runtime_dir"; then
            umask "$old_umask"
            xdisplay_notify_problem "Cannot create display runtime directory: $runtime_dir"
            return 1
        fi
        umask "$old_umask"

        if [ -L "$runtime_dir" ] || [ ! -d "$runtime_dir" ]; then
            xdisplay_notify_problem "Refusing unsafe display runtime directory: $runtime_dir"
            return 1
        fi
        if [ "$(xdisplay_path_uid "$runtime_dir")" != "$user_id" ]; then
            xdisplay_notify_problem "Display runtime directory is not owned by UID $user_id: $runtime_dir"
            return 1
        fi
        if [ "$(xdisplay_path_mode "$runtime_dir")" != 700 ]; then
            chmod 700 "$runtime_dir" 2>/dev/null || :
        fi
        if [ "$(xdisplay_path_mode "$runtime_dir")" != 700 ]; then
            xdisplay_notify_problem "Display runtime directory must have mode 0700: $runtime_dir"
            return 1
        fi
    fi

    xdisplay_normalize_display
    lock_prefix=$runtime_dir/xdisplay-$user_id-$display_key
    apply_lock=$lock_prefix.apply.lock
    watch_lock=$lock_prefix.watch.lock
    generation_file=$lock_prefix.generation
    manual_marker=$lock_prefix.manual
}

xdisplay_open_apply_lock() {
    [ "${apply_lock_open:-0}" -eq 1 ] && return 0
    exec 8>"$apply_lock" || return 1
    apply_lock_open=1
}

xdisplay_read_lid_state() {
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

xdisplay_lid_state() {
    xdisplay_read_lid_state
    printf '%s\n' "$LID_STATE"
}

xdisplay_drm_signature() {
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
