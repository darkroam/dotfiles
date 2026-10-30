#!/bin/sh
# Fake bluetoothctl coverage for btmenu and sb-bluetooth.

set -u

HOME_BIN=${HOME}/.local/bin
BTMENU=$HOME_BIN/btmenu
sb_bluetooth=$HOME_BIN/statusbar/sb-bluetooth
fail=0

bad() {
	printf 'FAIL %s\n' "$1" >&2
	fail=1
}

ok() {
	printf 'ok %s\n' "$1"
}

new_env() {
	root=$(mktemp -d)
	export BT_LOG="$root/log"
	export BT_NOTIFY="$root/notify"
	export BT_DMENU_LOG="$root/dmenu"
	export BT_LAST_MENU="$root/last-menu"
	export BT_PICKS="$root/picks"
	export BT_STATE="$root/state"
	export BT_PKILL="$root/pkill"
	export BT_FZF="$root/fzf"
	export BT_ST="$root/st"
	export BT_HTTP="$root/http"
	export XDG_RUNTIME_DIR="$root/run"
	mkdir -p "$BT_STATE" "$root/bin" "$XDG_RUNTIME_DIR"
	: > "$BT_LOG"
	: > "$BT_NOTIFY"
	: > "$BT_DMENU_LOG"
	: > "$BT_PICKS"
	: > "$BT_PKILL"
	: > "$BT_FZF"
	: > "$BT_ST"
	: > "$BT_HTTP"
	cat > "$root/bin/bluetoothctl" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$BT_LOG"
while [ $# -gt 0 ]; do
	case $1 in
		--timeout|--agent) shift 2 ;;
		--) shift; break ;;
		-*) printf 'bad opt %s\n' "$1" >> "$BT_LOG"; exit 2 ;;
		*) break ;;
	esac
done
cmd=$1
shift
case $cmd in
	list) cat "$BT_STATE/list" 2>/dev/null; exit 0 ;;
	show)
		if ! grep -q '^Controller ' "$BT_STATE/list" 2>/dev/null; then
			printf '%s\n' SHOW_WITHOUT_ADAPTER >> "$BT_LOG"
			exit 1
		fi
		cat "$BT_STATE/show" 2>/dev/null
		exit 0
		;;
	devices)
		key=${1:-all}
		f=$BT_STATE/devices.$key
		if [ "$key" = all ] && [ -f "$BT_STATE/scanned" ]; then
			f=$BT_STATE/devices.after
		fi
		cat "$f" 2>/dev/null
		exit 0
		;;
	scan)
		if [ "${1:-}" = on ]; then
			: > "$BT_STATE/scanned"
		fi
		exit 0
		;;
	pair)
		if [ -f "$BT_STATE/pair.err" ]; then
			cat "$BT_STATE/pair.err" >&2
		fi
		rc=$(cat "$BT_STATE/pair.rc" 2>/dev/null || printf '%s\n' 0)
		exit "$rc"
		;;
	info)
		mac=${1:-}
		if [ -n "$mac" ] && [ -f "$BT_STATE/info.$mac" ]; then
			cat "$BT_STATE/info.$mac"
		else
			cat "$BT_STATE/info" 2>/dev/null
		fi
		exit 0
		;;
	*) exit 0 ;;
esac
EOS
	cat > "$root/bin/dmenu" << 'EOS'
#!/bin/sh
cat > "$BT_LAST_MENU"
cat "$BT_LAST_MENU" >> "$BT_DMENU_LOG"
printf '\n---\n' >> "$BT_DMENU_LOG"
if [ ! -s "$BT_PICKS" ]; then
	exit 1
fi
pick=$(awk 'NR == 1 { print; exit }' "$BT_PICKS")
awk 'NR > 1 { print }' "$BT_PICKS" > "$BT_PICKS.next"
mv "$BT_PICKS.next" "$BT_PICKS"
if [ "$pick" = CANCEL ]; then
	exit 1
fi
if [ "$pick" = AUTO ]; then
	awk 'NF { print; exit }' "$BT_LAST_MENU"
	exit 0
fi
printf '%s\n' "$pick"
EOS
	cat > "$root/bin/notify-send" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$BT_NOTIFY"
EOS
	cat > "$root/bin/pkill" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$BT_PKILL"
exit 0
EOS
	cat > "$root/bin/timeout" << 'EOS'
#!/bin/sh
printf '%s\n' "timeout $*" >> "$BT_LOG"
shift
"$@"
EOS
	cat > "$root/bin/st" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$BT_ST"
exit 0
EOS
	cat > "$root/bin/curl" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$BT_HTTP"
exit 0
EOS
	cat > "$root/bin/fzf" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$BT_FZF"
sock=
for arg in "$@"; do
	case $arg in
		--listen=*) sock=${arg#--listen=} ;;
	esac
done
if [ -f "$BT_STATE/fzf.hold" ] && [ -n "$sock" ]; then
	: > "$sock"
	sleep 2
fi
if [ -f "$BT_STATE/fzf.out" ]; then
	cat "$BT_STATE/fzf.out"
fi
if [ -f "$BT_STATE/fzf.rc" ]; then
	exit "$(cat "$BT_STATE/fzf.rc")"
fi
exit 1
EOS
	chmod 755 "$root/bin/"*
	if [ -z "${BT_BASE_PATH:-}" ]; then
		BT_BASE_PATH=$PATH
		export BT_BASE_PATH
	fi
	export PATH="$root/bin:$HOME_BIN:$HOME_BIN/statusbar:$BT_BASE_PATH"
	export STATUSBAR=dwmblocks
}

finish() {
	rm -f "${XDG_RUNTIME_DIR:-}/btmenu-scan.lock"
	rm -rf "$root"
}

assert_eq() {
	if [ "$1" != "$2" ]; then
		bad "$3: got [$1] want [$2]"
	else
		ok "$3"
	fi
}

assert_no_timeout() {
	if grep -q -- '--timeout' "$BT_LOG"; then
		bad "$1 has timeout"
	else
		ok "$1 has no timeout"
	fi
}

assert_rc() {
	if [ "$1" -eq "$2" ]; then
		ok "$3"
	else
		bad "$3: rc $1 want $2"
	fi
}

# no adapter: one list, no show, menu fails, status is empty
new_env
: > "$BT_STATE/list"
out=$( "$BTMENU" --status ); rc=$?
assert_rc "$rc" 0 "no-adapter status rc"
assert_eq "$out" "" "no-adapter empty"
if grep -q '^show$' "$BT_LOG" || grep -q SHOW_WITHOUT_ADAPTER "$BT_LOG"; then
	bad "no-adapter called show"
else
	ok "no-adapter skipped show"
fi
: > "$BT_LOG"
"$BTMENU" >/dev/null 2>&1; rc=$?
assert_rc "$rc" 1 "no-adapter menu rc"
if grep -q '无蓝牙适配器' "$BT_NOTIFY"; then
	ok "no-adapter notify"
else
	bad "no-adapter notify missing"
fi
if grep -q '^show$' "$BT_LOG"; then
	bad "no-adapter menu called show"
else
	ok "no-adapter menu one list"
fi
assert_no_timeout "no-adapter"
finish

# adapter on, no devices
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
: > "$BT_STATE/devices.Connected"
out=$( "$BTMENU" --status )
assert_eq "$out" "🔵" "no-device status"
assert_no_timeout "no-device"
finish

# powered off
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: no' > "$BT_STATE/show"
out=$( "$BTMENU" --status )
assert_eq "$out" "⛔" "powered-off status"
assert_no_timeout "powered-off"
finish

# Powered missing, list non-empty
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Name: Test' > "$BT_STATE/show"
: > "$BT_STATE/devices.Connected"
out=$( "$BTMENU" --status )
assert_eq "$out" "🔵" "powered-missing status"
assert_no_timeout "powered-missing"
finish

# connected
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' 'Device 00:11:22:33:44:55 Headphones' > "$BT_STATE/devices.Connected"
out=$( "$BTMENU" --status )
assert_eq "$out" "🔵1" "connected status"
if grep -q -- '--timeout' "$BT_LOG"; then
	bad "connected query timeout"
else
	ok "connected query has no timeout"
fi
finish

# dmenu cancel exits 0
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' CANCEL > "$BT_PICKS"
"$BTMENU"; rc=$?
assert_rc "$rc" 0 "dmenu cancel rc"
if grep -q '扫描并配对' "$BT_DMENU_LOG"; then
	ok "dmenu cancel saw menu"
else
	bad "dmenu cancel menu missing"
fi
finish

# pair failure does not trust or connect
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
: > "$BT_STATE/devices.all"
printf '%s\n' 'Device AA:BB:CC:DD:EE:FF Headset' > "$BT_STATE/devices.after"
printf '%s\n' '	Paired: no' > "$BT_STATE/info"
printf '%s\n' 'Failed to pair' > "$BT_STATE/pair.err"
printf '%s\n' 1 > "$BT_STATE/pair.rc"
printf '%s\n' '扫描并配对' AUTO > "$BT_PICKS"
"$BTMENU" >/dev/null 2>&1; rc=$?
assert_rc "$rc" 1 "pair-fail rc"
if grep -q '^trust ' "$BT_LOG" || grep -q '^connect ' "$BT_LOG"; then
	bad "pair-fail continued"
else
	ok "pair-fail stopped"
fi
if grep -q 'Failed to pair' "$BT_NOTIFY"; then
	ok "pair-fail notify"
else
	bad "pair-fail notify missing"
fi
if grep -qx -- '--timeout 8 scan on' "$BT_LOG" \
	&& grep -q -- '--timeout 20 pair ' "$BT_LOG"; then
	ok "pair-fail keeps scan and pair timeouts"
else
	bad "pair-fail timeout shape"
fi
if grep -- '--timeout' "$BT_LOG" | grep -Ev -e '--timeout 8 scan on' -e '--timeout 20 pair ' | grep -q .; then
	bad "pair-fail extra timeout"
else
	ok "pair-fail queries have no timeout"
fi
if [ -e "$XDG_RUNTIME_DIR/btmenu-scan.lock" ]; then
	bad "scan lock left behind"
else
	ok "scan lock removed"
fi
finish

# middle click lists connected devices and still signals on cancel
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' 'Device 00:11:22:33:44:55 Headphones' > "$BT_STATE/devices.Connected"
printf '%s\n' CANCEL > "$BT_PICKS"
BLOCK_BUTTON=2 "$sb_bluetooth" >/dev/null; rc=$?
assert_rc "$rc" 0 "middle-click rc"
if grep -q 'Headphones' "$BT_DMENU_LOG"; then
	ok "middle-click list"
else
	bad "middle-click list missing"
fi
if grep -q 'RTMIN+2' "$BT_PKILL"; then
	ok "middle-click signal"
else
	bad "middle-click signal missing"
fi
finish

# right click is help, not a menu; button 6 is not a menu
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' 'Device 00:11:22:33:44:55 Headphones' > "$BT_STATE/devices.Connected"
out=$(BLOCK_BUTTON=3 "$sb_bluetooth"); rc=$?
assert_rc "$rc" 0 "right-click rc"
assert_eq "$out" "🔵1" "right-click status"
if grep -q '左键：主菜单' "$BT_NOTIFY" && ! [ -s "$BT_DMENU_LOG" ]; then
	ok "right-click help"
else
	bad "right-click help"
fi
: > "$BT_DMENU_LOG"
out=$(BLOCK_BUTTON=6 "$sb_bluetooth")
assert_eq "$out" "🔵1" "button-6 status only"
if [ -s "$BT_DMENU_LOG" ]; then
	bad "button-6 opened dmenu"
else
	ok "button-6 no menu"
fi
finish

# no adapter from the bar does not signal
new_env
: > "$BT_STATE/list"
out=$(BLOCK_BUTTON=1 "$sb_bluetooth"); rc=$?
assert_rc "$rc" 0 "bar no-adapter rc"
assert_eq "$out" "" "bar no-adapter empty"
if [ -s "$BT_PKILL" ]; then
	bad "bar no-adapter signaled"
else
	ok "bar no-adapter no signal"
fi
finish


icon_file() {
	printf '%s\n' "	Icon: $2" > "$BT_STATE/info.$1"
}

# known type icons, deduped, with a space before the count
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' 'Device 11:11:11:11:11:01 Keys' 'Device 11:11:11:11:11:02 Phone' > "$BT_STATE/devices.Connected"
icon_file 11:11:11:11:11:01 input-keyboard
icon_file 11:11:11:11:11:02 phone
out=$( "$BTMENU" --status )
assert_eq "$out" "⌨️📱 2" "two-type status"
if grep -q 'timeout 5 bluetoothctl info 11:11:11:11:11:01' "$BT_LOG" \
	&& grep -q 'timeout 5 bluetoothctl info 11:11:11:11:11:02' "$BT_LOG"; then
	ok "icon info uses timeout 5"
else
	bad "icon info timeout shape"
fi
assert_no_timeout "icon info"
finish

# same type twice counts both devices and keeps one icon
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' 'Device 11:11:11:11:11:03 A' 'Device 11:11:11:11:11:04 B' > "$BT_STATE/devices.Connected"
icon_file 11:11:11:11:11:03 audio-headset
icon_file 11:11:11:11:11:04 audio-card
out=$( "$BTMENU" --status )
assert_eq "$out" "🎧 2" "duplicate-type status"
finish

# unknown icons keep the old compact form
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' 'Device 11:11:11:11:11:05 Cam' > "$BT_STATE/devices.Connected"
icon_file 11:11:11:11:11:05 camera-photo
out=$( "$BTMENU" --status )
assert_eq "$out" "🔵1" "unknown-icon status"
finish

# a known type keeps one unknown icon; five types overflow
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' \
	'Device 11:11:11:11:11:11 K' \
	'Device 11:11:11:11:11:12 M' \
	'Device 11:11:11:11:11:13 P' \
	'Device 11:11:11:11:11:14 H' \
	'Device 11:11:11:11:11:15 S' \
	'Device 11:11:11:11:11:16 U' > "$BT_STATE/devices.Connected"
icon_file 11:11:11:11:11:11 input-keyboard
icon_file 11:11:11:11:11:12 input-mouse
icon_file 11:11:11:11:11:13 phone
icon_file 11:11:11:11:11:14 audio-headset
icon_file 11:11:11:11:11:15 audio-speakers
icon_file 11:11:11:11:11:16 camera-photo
out=$( "$BTMENU" --status )
assert_eq "$out" "⌨️🖱️📱🎧+2 6" "overflow status"
finish

# dynamic entry opens st and does not start the 8 second scan
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' '动态扫描（fzf）' > "$BT_PICKS"
"$BTMENU"; rc=$?
assert_rc "$rc" 0 "dynamic menu rc"
assert_eq "$(cat "$BT_ST")" "-e btmenu --dynamic" "dynamic menu launches st"
if grep -q 'scan on' "$BT_LOG"; then
	bad "dynamic menu started scan"
else
	ok "dynamic menu did not scan"
fi
finish

# missing fzf exits 0 and does not scan
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
mkdir -p "$root/sys"
ln -s "$(command -v awk)" "$root/sys/awk"
ln -s "$(command -v grep)" "$root/sys/grep"
ln -s "$(command -v cat)" "$root/sys/cat"
rm -f "$root/bin/fzf" "$root/bin/curl"
PATH="$root/bin:$root/sys" "$BTMENU" --dynamic; rc=$?
assert_rc "$rc" 0 "missing fzf rc"
if grep -q '未安装 fzf' "$BT_NOTIFY"; then
	ok "missing fzf notify"
else
	bad "missing fzf notify"
fi
if grep -q 'scan on' "$BT_LOG"; then
	bad "missing fzf scanned"
else
	ok "missing fzf did not scan"
fi
finish

# cancel stops the scan and does not pair
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' 1 > "$BT_STATE/fzf.rc"
"$BTMENU" --dynamic; rc=$?
assert_rc "$rc" 0 "dynamic cancel rc"
if grep -q 'scan on' "$BT_LOG" && grep -qx 'scan off' "$BT_LOG"; then
	ok "dynamic cancel scan off"
else
	bad "dynamic cancel scan off"
fi
if grep -q '^pair ' "$BT_LOG" || grep -q 'pair ' "$BT_LOG"; then
	bad "dynamic cancel paired"
else
	ok "dynamic cancel did not pair"
fi
if grep -q -- '--listen=' "$BT_FZF" && grep -q '\.sock' "$BT_FZF" && ! grep -q 'listen-unsafe' "$BT_FZF"; then
	ok "dynamic listen socket"
else
	bad "dynamic listen socket"
fi
if [ -e "$XDG_RUNTIME_DIR/btmenu-fzf.sock" ] || [ -e "$XDG_RUNTIME_DIR/btmenu-scan.lock" ]; then
	bad "dynamic cancel left socket or lock"
else
	ok "dynamic cancel cleaned up"
fi
finish

# a selection reuses pair, trust and connect
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' '	Paired: no' '	Trusted: no' '	Connected: no' > "$BT_STATE/info"
printf '%s\n' 0 > "$BT_STATE/pair.rc"
printf '%s\n' 0 > "$BT_STATE/fzf.rc"
printf 'Headset\tAA:BB:CC:DD:EE:FF\n' > "$BT_STATE/fzf.out"
"$BTMENU" --dynamic >/dev/null 2>&1; rc=$?
assert_rc "$rc" 0 "dynamic select rc"
if grep -q -- '--timeout 20 pair AA:BB:CC:DD:EE:FF' "$BT_LOG" \
	&& grep -qx 'trust AA:BB:CC:DD:EE:FF' "$BT_LOG" \
	&& grep -qx 'connect AA:BB:CC:DD:EE:FF' "$BT_LOG"; then
	ok "dynamic select reuses bring-up"
else
	bad "dynamic select reuses bring-up"
fi
if grep -qx 'scan off' "$BT_LOG"; then
	ok "dynamic select scan off"
else
	bad "dynamic select scan off"
fi
finish

# reload is posted to the unix socket and does not open tcp
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' 1 > "$BT_STATE/fzf.rc"
: > "$BT_STATE/fzf.hold"
"$BTMENU" --dynamic >/dev/null 2>&1; rc=$?
assert_rc "$rc" 0 "dynamic reload rc"
if grep -q -- '--unix-socket' "$BT_HTTP" 	&& grep -q 'reload(btmenu --list)' "$BT_HTTP" 	&& grep -q '\.sock' "$BT_HTTP" 	&& ! grep -q 'listen-unsafe' "$BT_FZF"; then
	ok "dynamic reload post"
else
	bad "dynamic reload post: $(cat "$BT_HTTP") / $(cat "$BT_FZF")"
fi
finish

if [ "$fail" -ne 0 ]; then
	printf 'desktop bluetooth tests failed\n' >&2
	exit 1
fi
printf 'desktop bluetooth tests passed\n'
