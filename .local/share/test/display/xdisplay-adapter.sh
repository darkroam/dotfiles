#!/bin/sh

set -eu

xdisplay=${XDISPLAY_UNDER_TEST:-$HOME/.local/bin/xdisplay.sh}
fixtures=$HOME/.local/share/xdisplay-transition-20260714/fixtures
fake_bin=$fixtures/bin
tests=0
test_root=$(mktemp -d "${TMPDIR:-/tmp}/xdisplay-adapter-test.XXXXXX")
trap 'rm -rf "$test_root"' 0 1 2 15

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

pass() {
    tests=$((tests + 1))
    printf 'ok %02d - %s\n' "$tests" "$1"
}

assert_contains() {
    value=$1
    expected=$2
    printf '%s\n' "$value" | grep -F -- "$expected" >/dev/null ||
        fail "missing: $expected"
}

setup_case() {
    name=$1
    case_dir=$test_root/$name
    home=$case_dir/home
    runtime=$case_dir/runtime
    calls=$case_dir/xrandr.calls
    mutations=$case_dir/xrandr.mutations
    adapter_calls=$case_dir/adapter.calls
    adapter_env=$case_dir/adapter.env
    legacy_calls=$case_dir/legacy.calls
    mkdir -p "$home/.config/x11" "$runtime" "$case_dir/test-root/proc" \
        "$case_dir/test-root/sys/class/drm"
    chmod 700 "$runtime"
    : > "$calls"
    : > "$mutations"
    : > "$adapter_calls"
    : > "$adapter_env"
    : > "$legacy_calls"
}

write_adapter() {
    cat > "$home/.config/x11/xdisplay-device.local" <<'ADAPTER'
#!/bin/sh
printf '%s\t%s\n' "$1" "${2:-}" >> "$ADAPTER_CALLS"
printf '%s\n' "DISPLAY=$DISPLAY" "XAUTHORITY=$XAUTHORITY" "PATH=$PATH" >> "$ADAPTER_ENV"
case "$1" in
    internal-outputs)
        [ -n "${ADAPTER_INTERNAL:-}" ] && printf '%s\n' "$ADAPTER_INTERNAL"
        ;;
    expected-mode)
        [ "${ADAPTER_SLEEP:-0}" -eq 0 ] || sleep "$ADAPTER_SLEEP"
        [ -n "${ADAPTER_EXPECTED:-}" ] || exit 69
        printf '%s\n' "$ADAPTER_EXPECTED"
        ;;
    restore-internal)
        [ "${ADAPTER_RESTORE_RESULT:-0}" -eq 0 ] || {
            printf '%s\n' 'restore failed' >&2
            exit "$ADAPTER_RESTORE_RESULT"
        }
        if [ -n "${ADAPTER_RESTORED_FIXTURE:-}" ]; then
            cp "$ADAPTER_RESTORED_FIXTURE" "$FAKE_XRANDR_FIXTURE"
        fi
        ;;
    *) exit 64 ;;
esac
ADAPTER
    chmod 700 "$home/.config/x11/xdisplay-device.local"
}

run_xdisplay() {
    fixture=$1
    mode=$2
    shift 2
    env HOME="$home" PATH="$fake_bin:$case_dir/bin:/usr/bin:/bin" \
        DISPLAY=:99 XAUTHORITY="$case_dir/Xauthority" XDG_RUNTIME_DIR="$runtime" \
        XDISPLAY_TEST_MODE=1 XDISPLAY_TEST_ROOT="$case_dir/test-root" \
        XDISPLAY_USE_ADAPTER="$mode" ADAPTER_CALLS="$adapter_calls" ADAPTER_ENV="$adapter_env" \
        FAKE_XRANDR_FIXTURE="$fixture" FAKE_XRANDR_CALLS="$calls" \
        FAKE_XRANDR_MUTATIONS="$mutations" "$@" "$xdisplay" \
        "${XDISPLAY_ACTION:---status}"
}

setup_case disabled
write_adapter
status=$(ADAPTER_INTERNAL=DP-2 ADAPTER_EXPECTED=1280x720 \
    run_xdisplay "$fixtures/mirror-unknown-internal.xrandr" 0)
[ ! -s "$adapter_calls" ] || fail 'disabled gate invoked adapter'
[ ! -e "$home/.local/share/x11/xdisplay-adapter.log" ] ||
    fail 'disabled gate wrote adapter log'
assert_contains "$status" 'policy=mirror-fallback'
pass 'disabled gate preserves legacy behavior'

setup_case missing
status=$(run_xdisplay "$fixtures/single.xrandr" 1)
assert_contains "$status" 'policy=single-output'
log=$(cat "$home/.local/share/x11/xdisplay-adapter.log")
assert_contains "$log" 'status=UNAVAILABLE'
assert_contains "$log" 'detail=adapter_missing'
pass 'missing adapter degrades and logs once'

setup_case identify
write_adapter
status=$(ADAPTER_INTERNAL=DP-2 run_xdisplay \
    "$fixtures/mirror-unknown-internal.xrandr" 1)
assert_contains "$status" 'policy=extend-from-internal'
grep -q '^internal-outputs' "$adapter_calls" || fail 'internal-outputs not called'
grep -q '^DISPLAY=:99$' "$adapter_env" || fail 'DISPLAY was not passed explicitly'
grep -q "^XAUTHORITY=$case_dir/Xauthority$" "$adapter_env" || fail 'XAUTHORITY was not passed explicitly'
grep -q "^PATH=$fake_bin:" "$adapter_env" || fail 'PATH was not passed explicitly'
pass 'validated adapter candidate identifies nonstandard internal output'

setup_case invalid
write_adapter
status=$(ADAPTER_INTERNAL='DP-2 invalid candidate' XDISPLAY_INTERNAL_OUTPUTS=DP-2 \
    run_xdisplay "$fixtures/mirror-unknown-internal.xrandr" 1)
assert_contains "$status" 'policy=extend-from-internal'
log=$(cat "$home/.local/share/x11/xdisplay-adapter.log")
assert_contains "$log" 'status=INVALID detail=invalid_candidate'
pass 'invalid candidate falls back to legacy internal output'

setup_case expected
write_adapter
status=$(ADAPTER_EXPECTED=1920x1080@60 run_xdisplay "$fixtures/single.xrandr" 1)
assert_contains "$status" 'target_mode:1920x1080 target_rate:60'
log=$(cat "$home/.local/share/x11/xdisplay-adapter.log")
assert_contains "$log" 'subcommand=expected-mode output=eDP-1'
assert_contains "$log" 'status=SUCCESS'
pass 'expected mode overrides RandR preferred target'

setup_case restore
write_adapter
mkdir "$case_dir/bin"
cat > "$case_dir/bin/legacy-restore" <<'LEGACY'
#!/bin/sh
printf '%s\n' "$1" >> "$LEGACY_CALLS"
LEGACY
chmod 700 "$case_dir/bin/legacy-restore"
cp "$fixtures/single.xrandr" "$case_dir/current.xrandr"
cat > "$case_dir/restored.xrandr" <<'XRANDR'
Screen 0: minimum 320 x 200, current 2560 x 1600, maximum 16384 x 16384
eDP-1 connected primary 2560x1600+0+0 (normal left inverted right x axis y axis) 312mm x 195mm
   2560x1600     60.00*+
   1920x1200     60.00
XRANDR
set +e
ADAPTER_EXPECTED=2560x1600 ADAPTER_RESTORE_RESULT=0 \
ADAPTER_RESTORED_FIXTURE="$case_dir/restored.xrandr" XDISPLAY_ACTION=--apply \
XDISPLAY_RESTORE_COMMAND=legacy-restore LEGACY_CALLS="$legacy_calls" \
run_xdisplay "$case_dir/current.xrandr" 1 >/dev/null
restore_result=$?
set -e
[ "$restore_result" -eq 0 ] || fail 'status failed after missing expected mode'
[ "$(grep -c '^restore-internal' "$adapter_calls")" -eq 1 ] ||
    fail 'restore-internal was not bounded to one call'
[ ! -s "$legacy_calls" ] || fail 'status unexpectedly called legacy restore'
log=$(cat "$home/.local/share/x11/xdisplay-adapter.log")
assert_contains "$log" 'status=MISSING detail=expected_mode_missing'
pass 'status observes missing expected mode without mutating layout'

setup_case failure
write_adapter
mkdir "$case_dir/bin"
cat > "$case_dir/bin/legacy-restore" <<'LEGACY'
#!/bin/sh
printf '%s\n' "$1" >> "$LEGACY_CALLS"
exit 1
LEGACY
chmod 700 "$case_dir/bin/legacy-restore"
set +e
ADAPTER_EXPECTED=2560x1600 ADAPTER_RESTORE_RESULT=42 \
XDISPLAY_ACTION=--apply XDISPLAY_RESTORE_COMMAND=legacy-restore \
LEGACY_CALLS="$legacy_calls" run_xdisplay "$fixtures/single.xrandr" 1 >/dev/null 2>&1
failure_result=$?
set -e
[ "$failure_result" -eq 0 ] || fail 'failed restore did not degrade successfully'
[ "$(grep -c '^restore-internal' "$adapter_calls")" -eq 1 ] ||
    fail 'failed adapter restore was not bounded to one call'
[ -s "$legacy_calls" ] || fail 'legacy restore fallback not called'
log=$(cat "$home/.local/share/x11/xdisplay-adapter.log")
assert_contains "$log" 'subcommand=restore-internal output=eDP-1'
assert_contains "$log" 'exit=42 status=FAILURE'
assert_contains "$log" 'restore failed'
pass 'failed adapter restore logs diagnostics and invokes legacy fallback'

setup_case legacy-pending
write_adapter
mkdir "$case_dir/bin"
cat > "$case_dir/bin/legacy-restore" <<'LEGACY'
#!/bin/sh
printf '%s\n' "$1" >> "$LEGACY_CALLS"
LEGACY
chmod 700 "$case_dir/bin/legacy-restore"
cat > "$case_dir/pending-internal.xrandr" <<'XRANDR'
Screen 0: minimum 320 x 200, current 0 x 0, maximum 16384 x 16384
eDP-1 connected (normal left inverted right x axis y axis) 300mm x 190mm
XRANDR
set +e
XDISPLAY_ACTION=--apply XDISPLAY_RESTORE_COMMAND=legacy-restore \
LEGACY_CALLS="$legacy_calls" run_xdisplay "$case_dir/pending-internal.xrandr" 1 \
    >/dev/null 2>&1
pending_result=$?
set -e
[ "$pending_result" -ne 0 ] || fail 'pending internal unexpectedly converged'
[ -s "$legacy_calls" ] || fail 'pending internal skipped legacy restore'
! grep -q '^restore-internal' "$adapter_calls" ||
    fail 'adapter restore ran without a valid missing expected mode'
pass 'missing expected-mode uses only the legacy restore path'

setup_case timeout
write_adapter
status=$(ADAPTER_SLEEP=3 run_xdisplay "$fixtures/single.xrandr" 1)
assert_contains "$status" 'policy=single-output'
log=$(cat "$home/.local/share/x11/xdisplay-adapter.log")
assert_contains "$log" 'subcommand=expected-mode output=eDP-1'
assert_contains "$log" 'status=TIMEOUT'
pass 'timed out adapter query degrades without blocking layout'

setup_case log-rotation
write_adapter
mkdir -p "$home/.local/share/x11"
log_path=$home/.local/share/x11/xdisplay-adapter.log
old_log=$log_path.1
dd if=/dev/zero of="$log_path" bs=1024 count=1025 2>/dev/null
printf '%s\n' old-rotation > "$old_log"
status=$(ADAPTER_EXPECTED=1920x1080 run_xdisplay "$fixtures/single.xrandr" 1)
[ -s "$log_path" ] || fail 'rotated adapter log was not recreated'
assert_contains "$(cat "$log_path")" 'subcommand=expected-mode'
[ "$(wc -c < "$old_log")" -ge 1048576 ] || fail 'rotated adapter log did not preserve old contents'
pass 'adapter log rotates at the size limit without blocking'

printf 'PASS: %s adapter fixture tests\n' "$tests"
