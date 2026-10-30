#!/bin/sh
# Fake bluetoothctl coverage for btmenu and sb-bluetooth.

set -u

HOME_BIN=${HOME}/.local/bin
BTMENU=$HOME_BIN/btmenu
SB=$HOME_BIN/statusbar/sb-bluetooth
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
	export XDG_RUNTIME_DIR="$root/run"
	mkdir -p "$BT_STATE" "$root/bin" "$XDG_RUNTIME_DIR"
	: > "$BT_LOG"
	: > "$BT_NOTIFY"
	: > "$BT_DMENU_LOG"
	: > "$BT_PICKS"
	: > "$BT_PKILL"
	cat > "$root/bin/bluetoothctl" << 'EOS'
#!/bin/sh
while [ $# -gt 0 ]; do
	case $1 in
		--timeout|--agent) shift 2 ;;
		--) shift; break ;;
		-*) printf 'bad opt %s\n' "$1" >> "$BT_LOG"; exit 2 ;;
		*) break ;;
	esac
done
printf '%s\n' "$*" >> "$BT_LOG"
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
	info) cat "$BT_STATE/info" 2>/dev/null; exit 0 ;;
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
	chmod 755 "$root/bin/"*
	export PATH="$root/bin:$HOME_BIN:$HOME_BIN/statusbar:$PATH"
	export STATUSBAR=dwmblocks
}

finish() {
	rm -rf "$root"
}

assert_eq() {
	if [ "$1" != "$2" ]; then
		bad "$3: got [$1] want [$2]"
	else
		ok "$3"
	fi
}

assert_rc() {
	if [ "$1" -eq "$2" ]; then
		ok "$3"
	else
		bad "$3: rc $1 want $2"
	fi
}

# no adapter: one list, no show, menu fails, status is ⛔
new_env
: > "$BT_STATE/list"
out=$( "$BTMENU" --status ); rc=$?
assert_rc "$rc" 0 "no-adapter status rc"
assert_eq "$out" "⛔" "no-adapter status"
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
finish

# adapter on, no devices
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
: > "$BT_STATE/devices.Connected"
out=$( "$BTMENU" --status )
assert_eq "$out" "🔵" "no-device status"
finish

# powered off
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: no' > "$BT_STATE/show"
out=$( "$BTMENU" --status )
assert_eq "$out" "⛔" "powered-off status"
finish

# Powered missing, list non-empty
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Name: Test' > "$BT_STATE/show"
: > "$BT_STATE/devices.Connected"
out=$( "$BTMENU" --status )
assert_eq "$out" "🔵" "powered-missing status"
finish

# connected
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' 'Device 00:11:22:33:44:55 Headphones' > "$BT_STATE/devices.Connected"
out=$( "$BTMENU" --status )
assert_eq "$out" "🔵1" "connected status"
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
finish

# middle click lists connected devices and still signals on cancel
new_env
printf '%s\n' 'Controller 00:00:00:00:00:01 Test' > "$BT_STATE/list"
printf '%s\n' '	Powered: yes' > "$BT_STATE/show"
printf '%s\n' 'Device 00:11:22:33:44:55 Headphones' > "$BT_STATE/devices.Connected"
printf '%s\n' CANCEL > "$BT_PICKS"
BLOCK_BUTTON=2 "$SB" >/dev/null; rc=$?
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
out=$(BLOCK_BUTTON=3 "$SB"); rc=$?
assert_rc "$rc" 0 "right-click rc"
assert_eq "$out" "🔵1" "right-click status"
if grep -q '左键：主菜单' "$BT_NOTIFY" && ! [ -s "$BT_DMENU_LOG" ]; then
	ok "right-click help"
else
	bad "right-click help"
fi
: > "$BT_DMENU_LOG"
out=$(BLOCK_BUTTON=6 "$SB")
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
out=$(BLOCK_BUTTON=1 "$SB"); rc=$?
assert_rc "$rc" 0 "bar no-adapter rc"
assert_eq "$out" "⛔" "bar no-adapter status"
if [ -s "$BT_PKILL" ]; then
	bad "bar no-adapter signaled"
else
	ok "bar no-adapter no signal"
fi
finish

if [ "$fail" -ne 0 ]; then
	printf 'desktop bluetooth tests failed\n' >&2
	exit 1
fi
printf 'desktop bluetooth tests passed\n'
