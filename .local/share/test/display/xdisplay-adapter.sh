#!/bin/sh

set -eu

xdisplay=${XDISPLAY_UNDER_TEST:-$HOME/.local/bin/xdisplay}
xdisplay_compat=${XDISPLAY_COMPAT_UNDER_TEST:-$HOME/.local/bin/xdisplay.sh}
fixtures=$HOME/.local/share/xdisplay-transition-20260714/fixtures
fake_bin=$fixtures/bin
tests=0
test_root=$(mktemp -d "${TMPDIR:-/tmp}/xdisplay-adapter-test.XXXXXX")
trap 'rm -rf "$test_root"' 0 1 2 15

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

ignore_file=${XDISPLAY_GITIGNORE_UNDER_TEST:-$HOME/.gitignore}
grep -qxF '.config/x11/xdisplay-device.local' "$ignore_file" ||
    fail 'device-local adapter is not precisely ignored'

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

state_test() {
    XDISPLAY_STATE_TEST=1 "$xdisplay" "$1" "$2" "$(printf '%b' "$3")"
}

[ "$(state_test open eDP-1 '')" = INTERNAL_ONLY ] || fail 'open with no external state mismatch'
pass 'state INTERNAL_ONLY: open with zero external outputs'
[ "$(state_test open eDP-1 HDMI-1)" = DUAL_EXTEND ] || fail 'dual extend state mismatch'
pass 'state DUAL_EXTEND: open with one external output'
[ "$(state_test open eDP-1 'HDMI-1\nDP-1')" = MULTI_EXTEND ] || fail 'multi extend state mismatch'
pass 'state MULTI_EXTEND: open with multiple external outputs'
[ "$(state_test closed '' HDMI-1)" = EXTERNAL_ONLY ] || fail 'external only state mismatch'
pass 'state EXTERNAL_ONLY: closed with one external output'
[ "$(state_test closed '' 'HDMI-1\nDP-1')" = MULTI_EXTERNAL ] || fail 'multi external state mismatch'
pass 'state MULTI_EXTERNAL: closed with multiple external outputs'
[ "$(state_test open '' '')" = NONE ] || fail 'none state mismatch'
pass 'state NONE: no available outputs'

[ "$($xdisplay version)" = 'xdisplay 2.0.0' ] || fail 'version output mismatch'
assert_contains "$($xdisplay help)" 'Usage: xdisplay [COMMAND]'
assert_contains "$($xdisplay_compat --help)" 'Usage: xdisplay [COMMAND]'
pass 'new command and legacy wrapper expose the same command interface'

layout_test() {
    XDISPLAY_LAYOUT_TEST=1 HOME="$home" \
        XDISPLAY_CUSTOM_LAYOUT_DIR="$home/.config/x11/display-layouts/custom" \
        "$xdisplay" "$1" "$2" "$3" "${4:-}"
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

config_test() {
    XDISPLAY_CONFIG_TEST=1 HOME="$home" \
        XDISPLAY_ENGINE_CONFIG="$engine_config" \
        XDISPLAY_LAYOUT_CONFIG="$layout_config" "$xdisplay"
}

setup_case config-defaults
engine_config=$home/.config/x11/display-engine.conf
layout_config=$home/.config/x11/display-layouts/default.conf
defaults=$(config_test)
assert_contains "$defaults" 'timeout=2'
assert_contains "$defaults" 'kill-after=1'
assert_contains "$defaults" 'external-position=right'
pass 'missing configuration uses built-in defaults'

setup_case config-valid
engine_config=$home/.config/x11/display-engine.conf
layout_config=$home/.config/x11/display-layouts/default.conf
mkdir -p "$(dirname "$layout_config")"
cat > "$engine_config" <<'CONF'
[engine]
timeout_seconds = 7
kill_after_seconds = 4
apply_failure_limit = 8
apply_retry_ticks = 12
hardware_probe_ticks = 30
pending_probe_ticks = 5
log_max_bytes = 2048
log_path = ~/.cache/xdisplay/test.log
CONF
cat > "$layout_config" <<'CONF'
[defaults]
external_position = above
external_primary = largest
mirror_on_duplicate = true
CONF
valid=$(config_test)
assert_contains "$valid" 'timeout=7'
assert_contains "$valid" 'kill-after=4'
assert_contains "$valid" 'apply-failure-limit=8'
assert_contains "$valid" 'log-path='
assert_contains "$valid" '/.cache/xdisplay/test.log'
assert_contains "$valid" 'external-position=above'
assert_contains "$valid" 'external-primary=largest'
assert_contains "$valid" 'mirror-on-duplicate=true'
pass 'valid engine and layout configuration loads'

setup_case config-missing-key
engine_config=$home/.config/x11/display-engine.conf
layout_config=$home/.config/x11/display-layouts/default.conf
cat > "$engine_config" <<'CONF'
[engine]
timeout_seconds = 9
CONF
mkdir -p "$(dirname "$layout_config")"
: > "$layout_config"
partial=$(config_test)
assert_contains "$partial" 'timeout=9'
assert_contains "$partial" 'kill-after=1'
assert_contains "$partial" 'log-max-bytes=1048576'
pass 'missing configuration keys retain individual defaults'

setup_case config-invalid
engine_config=$home/.config/x11/display-engine.conf
layout_config=$home/.config/x11/display-layouts/default.conf
cat > "$engine_config" <<'CONF'
[engine]
timeout_seconds = 2s
log_max_bytes = nope
CONF
mkdir -p "$(dirname "$layout_config")"
cat > "$layout_config" <<'CONF'
[defaults]
external_position = diagonal
CONF
invalid=$(config_test 2>"$case_dir/config.err")
assert_contains "$invalid" 'timeout=2'
assert_contains "$invalid" 'log-max-bytes=1048576'
assert_contains "$invalid" 'external-position=right'
assert_contains "$(cat "$case_dir/config.err")" 'invalid value'
pass 'invalid configuration reports diagnostics and falls back'

setup_case config-above-layout
engine_config=$home/.config/x11/display-engine.conf
layout_config=$home/.config/x11/display-layouts/default.conf
mkdir -p "$(dirname "$layout_config")"
cat > "$layout_config" <<'CONF'
[defaults]
external_position = above
CONF
above=$(XDISPLAY_CONFIG_TEST=0 XDISPLAY_LAYOUT_TEST=1 HOME="$home" \
    XDISPLAY_LAYOUT_CONFIG="$layout_config" "$xdisplay" open eDP-1 'HDMI-1 DP-1')
assert_contains "$above" 'direction=above'
assert_contains "$above" 'relation=--above anchor=eDP-1'
assert_contains "$above" 'relation=--above anchor=HDMI-1'
pass 'external_position=above uses --above chain relations'

setup_case custom-exact
custom_dir=$home/.config/x11/display-layouts/custom
mkdir -p "$custom_dir"
cat > "$custom_dir/exact-dock.conf" <<'CONF'
[identity]
outputs = eDP-1,HDMI-1
lid = open
match_mode = exact

[layout]
primary = eDP-1
order = eDP-1,HDMI-1
output_1 = eDP-1|0|0|1920x1080|60
output_2 = HDMI-1|120|80|2560x1440|60
CONF
custom=$(HOME="$home" XDISPLAY_CUSTOM_LAYOUT_DIR="$custom_dir" \
    XDISPLAY_LAYOUT_TEST=1 "$xdisplay" open eDP-1 HDMI-1)
assert_contains "$custom" 'layout=custom name=exact-dock'
assert_contains "$custom" 'custom_primary=eDP-1'
assert_contains "$custom" 'custom_output=HDMI-1 pos=120x80 mode=2560x1440 rate=60'
pass 'exact custom layout is selected and applied'

setup_case custom-contains
custom_dir=$home/.config/x11/display-layouts/custom
mkdir -p "$custom_dir"
cat > "$custom_dir/contains-dock.conf" <<'CONF'
[identity]
outputs = eDP-1,HDMI-1
lid = open
match_mode = contains

[layout]
primary = eDP-1
order = eDP-1,HDMI-1
output_1 = eDP-1|0|0|1920x1080|60
output_2 = HDMI-1|100|0|2560x1440|60
CONF
custom=$(HOME="$home" XDISPLAY_CUSTOM_LAYOUT_DIR="$custom_dir" \
    XDISPLAY_LAYOUT_TEST=1 "$xdisplay" open eDP-1 'HDMI-1 DP-1')
assert_contains "$custom" 'layout=custom name=contains-dock'
assert_contains "$custom" 'custom_extra=DP-1 relation=--right-of anchor=HDMI-1'
pass 'contains custom layout remains eligible with an extra output'

setup_case custom-priority
custom_dir=$home/.config/x11/display-layouts/custom
mkdir -p "$custom_dir"
cat > "$custom_dir/any.conf" <<'CONF'
[identity]
outputs = eDP-1,HDMI-1
lid = any
match_mode = exact
[layout]
primary = HDMI-1
order = HDMI-1,eDP-1
output_1 = HDMI-1|0|0|1920x1080|60
output_2 = eDP-1|1920|0|1920x1080|60
CONF
cat > "$custom_dir/exact.conf" <<'CONF'
[identity]
outputs = eDP-1,HDMI-1
lid = open
match_mode = exact
[layout]
primary = eDP-1
order = eDP-1,HDMI-1
output_1 = eDP-1|0|0|1920x1080|60
output_2 = HDMI-1|1920|0|1920x1080|60
CONF
custom=$(HOME="$home" XDISPLAY_CUSTOM_LAYOUT_DIR="$custom_dir" \
    XDISPLAY_LAYOUT_TEST=1 "$xdisplay" open eDP-1 HDMI-1)
assert_contains "$custom" 'layout=custom name=exact'
pass 'custom matching prioritizes exact lid over any'

setup_case custom-invalid
custom_dir=$home/.config/x11/display-layouts/custom
mkdir -p "$custom_dir"
cat > "$custom_dir/broken.conf" <<'CONF'
[identity]
outputs = eDP-1,HDMI-1
lid = open
match_mode = exact
[layout]
primary = eDP-1
output_1 = eDP-1|not-a-position|0|bad-mode|oops
CONF
custom=$(HOME="$home" XDISPLAY_CUSTOM_LAYOUT_DIR="$custom_dir" \
    XDISPLAY_LAYOUT_TEST=1 "$xdisplay" open eDP-1 HDMI-1 2>"$case_dir/custom.err")
assert_contains "$custom" 'layout=extend_chain direction=right'
custom_log=$home/.local/share/x11/xdisplay-adapter.log
assert_contains "$(cat "$custom_log")" 'parse_failed'
pass 'invalid custom layout falls back and records a diagnostic'

setup_case custom-save
mkdir -p "$case_dir/bin"
cat > "$case_dir/bin/xrandr" <<'XRANDR_MOCK'
#!/bin/sh
if [ "$1" = --query ] || [ "$1" = -q ]; then
    cat "$FAKE_XRANDR_FIXTURE"
else
    printf '%s\n' "$*" >> "$FAKE_XRANDR_MUTATIONS"
fi
XRANDR_MOCK
chmod 700 "$case_dir/bin/xrandr"
save_dir=$home/.config/x11/display-layouts/custom
HOME="$home" PATH="$case_dir/bin:/usr/bin:/bin" \
    DISPLAY=:99 XAUTHORITY="$case_dir/Xauthority" \
    XDISPLAY_CUSTOM_LAYOUT_DIR="$save_dir" \
    FAKE_XRANDR_FIXTURE="$fixtures/extended.xrandr" \
    "$HOME/.local/bin/displayselect" --save test-dock >/dev/null
[ -f "$save_dir/test-dock.conf" ] || fail 'save did not create custom layout'
[ "$(stat -c %a "$save_dir")" = 700 ] || fail 'custom directory is not private'
[ "$(stat -c %a "$save_dir/test-dock.conf")" = 600 ] || fail 'custom layout is not private'
assert_contains "$(cat "$save_dir/test-dock.conf")" '[identity]'
assert_contains "$(cat "$save_dir/test-dock.conf")" 'output_1 = '
list=$(HOME="$home" XDISPLAY_CUSTOM_LAYOUT_DIR="$save_dir" \
        PATH="$case_dir/bin:/usr/bin:/bin" \
        DISPLAY=:99 XAUTHORITY="$case_dir/Xauthority" \
        "$HOME/.local/bin/displayselect" --list)
assert_contains "$list" 'test-dock'
HOME="$home" XDISPLAY_CUSTOM_LAYOUT_DIR="$save_dir" \
    PATH="$case_dir/bin:/usr/bin:/bin" DISPLAY=:99 \
    XAUTHORITY="$case_dir/Xauthority" \
"$HOME/.local/bin/displayselect" --delete test-dock
[ ! -e "$save_dir/test-dock.conf" ] || fail 'delete did not remove custom layout'
fallback=$(HOME="$home" XDISPLAY_CUSTOM_LAYOUT_DIR="$save_dir" \
    XDISPLAY_LAYOUT_TEST=1 "$xdisplay" open eDP-1 HDMI-1)
assert_contains "$fallback" 'layout=extend_chain direction=right'
pass 'displayselect saves, lists and deletes private custom layouts'

HOME="$home" XDISPLAY_CUSTOM_LAYOUT_DIR="$save_dir" \
    PATH="$case_dir/bin:/usr/bin:/bin" DISPLAY=:99 \
    XAUTHORITY="$case_dir/Xauthority" \
    FAKE_XRANDR_FIXTURE="$fixtures/extended.xrandr" \
    "$HOME/.local/bin/displayselect" save test-dock-new >/dev/null
list=$(HOME="$home" XDISPLAY_CUSTOM_LAYOUT_DIR="$save_dir" \
    PATH="$case_dir/bin:/usr/bin:/bin" DISPLAY=:99 \
    XAUTHORITY="$case_dir/Xauthority" \
    "$HOME/.local/bin/displayselect" list)
assert_contains "$list" 'test-dock-new'
HOME="$home" XDISPLAY_CUSTOM_LAYOUT_DIR="$save_dir" \
    PATH="$case_dir/bin:/usr/bin:/bin" DISPLAY=:99 \
    XAUTHORITY="$case_dir/Xauthority" \
    "$HOME/.local/bin/displayselect" delete test-dock-new
assert_contains "$("$HOME/.local/bin/displayselect" help)" \
    'Usage: displayselect [COMMAND]'
pass 'displayselect supports self-explaining layout subcommands'

auto_path=$(HOME="$home" PATH="$case_dir/bin:/usr/bin:/bin" \
    DISPLAY=:99 XAUTHORITY="$case_dir/Xauthority" \
    XDISPLAY_CUSTOM_LAYOUT_DIR="$save_dir" \
    FAKE_XRANDR_FIXTURE="$fixtures/extended.xrandr" \
    "$HOME/.local/bin/displayselect" --save)
auto_name=${auto_path##*/}
auto_name=${auto_name%.conf}
printf '%s\n' "$auto_name" | grep -Eq '^auto-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$' ||
    fail 'automatic custom layout name has unexpected format'
rm -f "$auto_path"
pass 'displayselect generates timestamped automatic names'

layout=$(layout_test open eDP-1 'HDMI-1 DP-1')
assert_contains "$layout" 'state=MULTI_EXTEND'
assert_contains "$layout" 'layout=extend_chain direction=right'
assert_contains "$layout" 'primary=eDP-1'
assert_contains "$layout" 'output=HDMI-1 relation=--right-of anchor=eDP-1'
assert_contains "$layout" 'output=DP-1 relation=--right-of anchor=HDMI-1'
pass 'open with two externals uses a rightward chain'

layout=$(layout_test open eDP-1 'HDMI-1 DP-1 DP-2')
assert_contains "$layout" 'state=MULTI_EXTEND'
assert_contains "$layout" 'output=DP-2 relation=--right-of anchor=DP-1'
pass 'open with three externals extends the chain'

layout=$(layout_test closed '' 'HDMI-1 DP-1')
assert_contains "$layout" 'state=MULTI_EXTERNAL'
assert_contains "$layout" 'primary=HDMI-1'
assert_contains "$layout" 'output=DP-1 relation=--right-of anchor=HDMI-1'
pass 'closed with two externals uses first connector as primary'

layout=$(layout_test closed '' 'HDMI-1 DP-1 DP-2')
assert_contains "$layout" 'state=MULTI_EXTERNAL'
assert_contains "$layout" 'output=DP-2 relation=--right-of anchor=DP-1'
pass 'closed with three externals extends the chain'

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

setup_case apply-open-chain
cat > "$case_dir/open-chain.xrandr" <<'XRANDR'
Screen 0: minimum 320 x 200, current 6400 x 1440, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 300mm x 190mm
   1920x1080     60.00*+
HDMI-1 connected primary 2560x1440+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   2560x1440     60.00*+
DP-1 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   1920x1080     60.00*+
XRANDR
set +e
FAKE_XRANDR_MUTATION_RESULT=0 XDISPLAY_ACTION=--apply \
    run_xdisplay "$case_dir/open-chain.xrandr" 0 >/dev/null 2>&1
set -e
assert_contains "$(cat "$mutations")" '--right-of eDP-1'
assert_contains "$(cat "$mutations")" '--right-of HDMI-1'
pass 'configure_open applies a two-external rightward chain'

setup_case apply-closed-chain
mkdir -p "$case_dir/test-root/proc/acpi/button/lid/LID0"
printf 'state:      closed\n' > "$case_dir/test-root/proc/acpi/button/lid/LID0/state"
cat > "$case_dir/closed-chain.xrandr" <<'XRANDR'
Screen 0: minimum 320 x 200, current 4480 x 1440, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 300mm x 190mm
   1920x1080     60.00+
HDMI-1 connected 2560x1440+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   2560x1440     60.00*+
DP-1 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   1920x1080     60.00*+
XRANDR
set +e
FAKE_XRANDR_MUTATION_RESULT=0 XDISPLAY_ACTION=--apply \
    run_xdisplay "$case_dir/closed-chain.xrandr" 0 >/dev/null 2>&1
set -e
assert_contains "$(cat "$mutations")" '--right-of HDMI-1'
assert_contains "$(cat "$mutations")" '--output eDP-1 --off'
pass 'configure_closed applies the chain before disabling the internal output'

setup_case apply-closed-dock-single
mkdir -p "$case_dir/test-root/proc/acpi/button/lid/LID0"
printf 'state:      closed\n' > "$case_dir/test-root/proc/acpi/button/lid/LID0/state"
cat > "$case_dir/closed-dock-single.xrandr" <<'XRANDR'
Screen 0: minimum 320 x 200, current 2560 x 1440, maximum 16384 x 16384
HDMI-1 connected primary 2560x1440+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   2560x1440     60.00*+
XRANDR
FAKE_XRANDR_MUTATION_RESULT=0 XDISPLAY_ACTION=--apply \
    run_xdisplay "$case_dir/closed-dock-single.xrandr" 0 >/dev/null 2>&1 ||
    fail 'single-output closed dock did not converge'
[ ! -s "$mutations" ] || fail 'converged single-output closed dock mutated'
pass 'closed external-only dock converges without an internal output'

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
assert_contains "$status" 'state=DUAL_EXTEND internal=1 external=1'
assert_contains "$status" 'layout=extend_chain'
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

write_watch_sleep() {
    mkdir -p "$case_dir/bin"
    cat > "$case_dir/bin/sleep" <<'SLEEP_MOCK'
#!/bin/sh
count=0
if [ -r "$WATCH_SLEEP_COUNT" ]; then
    IFS= read -r count < "$WATCH_SLEEP_COUNT" || count=0
fi
count=$((count + 1))
printf '%s\n' "$count" > "$WATCH_SLEEP_COUNT"
mutation_count=$(wc -l < "$FAKE_XRANDR_MUTATIONS")
printf '%s\t%s\n' "$count" "$mutation_count" >> "$WATCH_SLEEP_TRACE"
if [ "$count" -ge "$WATCH_STOP_TICKS" ]; then
    kill -TERM "$PPID"
fi
SLEEP_MOCK
    chmod 700 "$case_dir/bin/sleep"
}

setup_watch_case() {
    setup_case "$1"
    scenario=$case_dir/scenario
    state=$case_dir/sequence.state
    sleep_count=$case_dir/sleep.count
    sleep_trace=$case_dir/sleep.trace
    watch_log=$case_dir/watch.log
    mkdir -p "$scenario" "$case_dir/bin" \
        "$case_dir/test-root/proc/acpi/button/lid/LID0"
    printf 'state:      closed\n' > \
        "$case_dir/test-root/proc/acpi/button/lid/LID0/state"
    printf '0\n' > "$state"
    : > "$sleep_count"
    : > "$sleep_trace"
    write_watch_sleep
}

run_watch_case() {
    display=$1
    ticks=$2
    set +e
    env HOME="$home" PATH="$fake_bin:$case_dir/bin:/usr/bin:/bin" \
        DISPLAY="$display" XAUTHORITY="$case_dir/Xauthority" XDG_RUNTIME_DIR="$runtime" \
        XDISPLAY_TEST_MODE=1 XDISPLAY_TEST_ROOT="$case_dir/test-root" \
        XDISPLAY_USE_ADAPTER=0 FAKE_XRANDR_SEQUENCE_DIR="$scenario" \
        FAKE_XRANDR_SEQUENCE_STATE="$state" FAKE_XRANDR_CALLS="$calls" \
        FAKE_XRANDR_MUTATIONS="$mutations" FAKE_XRANDR_MUTATION_RESULT=0 \
        WATCH_SLEEP_COUNT="$sleep_count" WATCH_SLEEP_TRACE="$sleep_trace" \
        WATCH_STOP_TICKS="$ticks" "$xdisplay" --watch > "$watch_log" 2>&1
    watch_result=$?
    set -e
    [ "$watch_result" -eq 143 ] ||
        fail "watcher fixture returned unexpected status $watch_result"
}

first_mutation_tick() {
    awk -F '\t' '$2 > 0 { print $1; exit }' "$sleep_trace"
}

write_initial_preferred() {
    cat > "$1" <<'XRANDR'
Screen 0: minimum 320 x 200, current 4480 x 1440, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 300mm x 190mm
   1920x1080     60.00*+
HDMI-1 connected 1920x1080+1920+0 (normal left inverted right x axis y axis) 600mm x 340mm
   2560x1440     60.00+
   1920x1080     60.00*
XRANDR
}

write_initial_current_divergent() {
    cat > "$1" <<'XRANDR'
Screen 0: minimum 320 x 200, current 4480 x 1440, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 300mm x 190mm
   1920x1080     60.00*+
HDMI-1 connected 1920x1080+1920+0 (normal left inverted right x axis y axis) 600mm x 340mm
   1920x1080     60.00*
   2560x1440     60.00
XRANDR
}

write_initial_unpreferred() {
    cat > "$1" <<'XRANDR'
Screen 0: minimum 320 x 200, current 3840 x 1080, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 300mm x 190mm
   1920x1080     60.00*+
HDMI-1 connected 1280x720+1920+0 (normal left inverted right x axis y axis) 600mm x 340mm
   1920x1080     60.00
   1280x720      60.00*
XRANDR
}

write_converged_preferred() {
    cat > "$1" <<'XRANDR'
Screen 0: minimum 320 x 200, current 2560 x 1440, maximum 16384 x 16384
eDP-1 connected (normal left inverted right x axis y axis) 300mm x 190mm
   1920x1080     60.00+
HDMI-1 connected primary 2560x1440+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   2560x1440     60.00*+
   1920x1080     60.00
XRANDR
}

write_converged_current_divergent() {
    cat > "$1" <<'XRANDR'
Screen 0: minimum 320 x 200, current 2560 x 1440, maximum 16384 x 16384
eDP-1 connected (normal left inverted right x axis y axis) 300mm x 190mm
   1920x1080     60.00+
HDMI-1 connected primary 2560x1440+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   1920x1080     60.00
   2560x1440     60.00*
XRANDR
}

write_converged_unpreferred() {
    cat > "$1" <<'XRANDR'
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
eDP-1 connected (normal left inverted right x axis y axis) 300mm x 190mm
   1920x1080     60.00+
HDMI-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   1920x1080     60.00*
   1280x720      60.00
XRANDR
}

write_extra_output_snapshot() {
    position=$2
    cat > "$1" <<XRANDR
Screen 0: minimum 320 x 200, current 4480 x 1440, maximum 16384 x 16384
eDP-1 connected (normal left inverted right x axis y axis) 300mm x 190mm
   1920x1080     60.00+
HDMI-1 connected primary 2560x1440+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   2560x1440     60.00*+
   1920x1080     60.00
DP-1 connected 1920x1080+${position}+0 (normal left inverted right x axis y axis) 600mm x 340mm
   1920x1080     60.00*+
XRANDR
}

write_steady_divergence_scenario() {
    write_initial_preferred "$scenario/0.xrandr"
    write_initial_current_divergent "$scenario/1.xrandr"
    write_converged_preferred "$scenario/2.xrandr"
    write_converged_preferred "$scenario/4.xrandr"
    write_converged_current_divergent "$scenario/5.xrandr"
    cat > "$scenario/transitions.tsv" <<'TRANSITIONS'
0	query	1
1	current	0
0	mutation	2
2	current	4
4	query	5
5	current	4
TRANSITIONS
}

setup_watch_case gate-normalized-key
write_steady_divergence_scenario
query_status=$(run_xdisplay "$scenario/0.xrandr" 0)
current_status=$(run_xdisplay "$scenario/1.xrandr" 0)
query_key=$(printf '%s\n' "$query_status" | sed -n 's/^topology_signature=//p')
current_key=$(printf '%s\n' "$current_status" | sed -n 's/^topology_signature=//p')
[ "$query_key" != "$current_key" ] || fail 'G-01 fixture did not reproduce raw key divergence'
run_watch_case :90 4
[ "$(first_mutation_tick)" = 2 ] || fail 'G-01 normalized gate did not converge at tick 2'
pass 'G-01 authoritative query key normalizes alternating snapshot sources'

setup_watch_case gate-ready
write_steady_divergence_scenario
run_watch_case :91 4
[ "$(sed -n '1p' "$sleep_trace")" = "1	0" ] ||
    fail 'G-02 startup gate applied on the first tick'
[ "$(first_mutation_tick)" = 2 ] || fail 'G-02 startup gate did not open on tick 2'
[ "$(wc -l < "$mutations")" -eq 1 ] || fail 'G-02 emitted more than one mutation'
pass 'G-02 preferred-ready stable startup applies once on tick 2'

setup_watch_case gate-preferred-delay
write_initial_unpreferred "$scenario/0.xrandr"
write_initial_current_divergent "$scenario/1.xrandr"
write_initial_preferred "$scenario/2.xrandr"
write_initial_current_divergent "$scenario/3.xrandr"
write_converged_preferred "$scenario/4.xrandr"
cat > "$scenario/transitions.tsv" <<'TRANSITIONS'
0	query	1
1	current	2
2	query	3
3	current	2
2	mutation	4
TRANSITIONS
run_watch_case :92 6
[ "$(first_mutation_tick)" = 4 ] || fail 'G-03 applied before delayed preferred stabilized'
assert_contains "$(cat "$mutations")" '--mode 2560x1440'
pass 'G-03 delayed preferred mode gates apply until a stable authoritative snapshot'

setup_watch_case gate-timeout
write_initial_unpreferred "$scenario/0.xrandr"
write_initial_unpreferred "$scenario/1.xrandr"
write_converged_unpreferred "$scenario/2.xrandr"
cat > "$scenario/transitions.tsv" <<'TRANSITIONS'
0	query	1
1	current	0
0	mutation	2
TRANSITIONS
run_watch_case :93 12
[ "$(first_mutation_tick)" = 10 ] || fail 'G-04 timeout did not release on tick 10'
assert_contains "$(cat "$mutations")" '--mode 1920x1080'
pass 'G-04 missing preferred mode follows the bounded tick-10 fallback'

setup_watch_case key-repeat
write_steady_divergence_scenario
run_watch_case :94 20
[ "$(wc -l < "$mutations")" -eq 1 ] || fail 'G-05 alternating sources repeated apply'
pass 'G-05 normalized key prevents repeated apply across 20 alternating ticks'

setup_watch_case apply-hotplug
write_initial_preferred "$scenario/0.xrandr"
write_initial_current_divergent "$scenario/1.xrandr"
write_extra_output_snapshot "$scenario/2.xrandr" 0
write_extra_output_snapshot "$scenario/4.xrandr" 0
write_converged_current_divergent "$scenario/5.xrandr"
write_extra_output_snapshot "$scenario/6.xrandr" 2560
cat >> "$scenario/5.xrandr" <<'XRANDR'
DP-1 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   1920x1080     60.00*+
XRANDR
cat > "$scenario/transitions.tsv" <<'TRANSITIONS'
0	query	1
1	current	0
0	mutation	2
2	current	4
4	query	5
5	mutation	6
TRANSITIONS
run_watch_case :95 5
[ "$(sed -n '2p' "$sleep_trace")" = "2	1" ] ||
    fail 'G-06 first transaction did not observe the hotplug'
[ "$(sed -n '3p' "$sleep_trace")" = "3	2" ] ||
    fail 'G-06 hotplug was not replanned on the next tick'
assert_contains "$(sed -n '2p' "$mutations")" '--right-of HDMI-1'
pass 'G-06 connection projection change forces next-tick replan'

printf 'PASS: %s adapter fixture tests\n' "$tests"
