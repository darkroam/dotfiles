#!/bin/sh
# shellcheck disable=SC2086,SC2015
# Status bar memory cells, music pause/play text, and backlight percent.

set -u
fail=0
bad() { printf 'FAIL %s\n' "$1" >&2; fail=1; }
ok() { printf 'ok %s\n' "$1"; }

SB_MUSIC=$HOME/.local/bin/statusbar/sb-music
SB_MEM=$HOME/.local/bin/statusbar/sb-memory

new_root() {
	PATH=/usr/bin:/bin
	root=$(mktemp -d)
	export XDG_RUNTIME_DIR=$root/run
	mkdir -p "$XDG_RUNTIME_DIR" "$root/bin"
	export PATH=$root/bin:/usr/bin:/bin
	export MPC_OUT=$root/mpc.out
	export MPC_STATUS=$root/mpc.status
	cat > "$root/bin/mpc" << 'EOS'
#!/bin/sh
if [ "${1:-}" = "status" ]; then
	cat "$MPC_STATUS"
else
	cat "$MPC_OUT"
fi
EOS
	cat > "$root/bin/free" << 'EOS'
#!/bin/sh
cat "$FREE_OUT"
EOS
	cat > "$root/bin/notify-send" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "${NOTIFY_LOG:-/dev/null}"
EOS
	chmod 755 "$root/bin/mpc" "$root/bin/free" "$root/bin/notify-send"
	ln -s "$(command -v sed)" "$(command -v paste)" "$root/bin/"
}

song() {
	state=$2
	cat > "$MPC_OUT" << EOF
$1
[$state] #1/1 0:01/3:00 (1%)
volume: 10%   repeat: off   random: off   single: off   consume: off
EOF
	cp "$MPC_OUT" "$MPC_STATUS"
}

new_root
song 'Artist - Title' playing
"$SB_MUSIC" > "$root/got"
[ "$(cat "$root/got")" = 'Artist - Title' ] && ok 'playing title' || bad 'playing title'

new_root
song 'Artist - Title' paused
"$SB_MUSIC" > "$root/got"
[ "$(cat "$root/got")" = 'Artist - Title ⏸' ] && ok 'paused mark' || bad 'paused mark'

mem_case() {
	name=$1
	shift
	new_root
	export FREE_OUT=$root/free.out
	cat > "$FREE_OUT" << EOF
              total        used        free      shared  buff/cache   available
$*
EOF
	"$SB_MEM" > "$root/got"
	if [ "$(cat "$root/got")" = "$name" ]; then
		ok "memory $name"
	else
		bad "memory $name"
		printf ' got %s\n' "$(cat "$root/got")" >&2
	fi
}
mem_case '████▓▓░░' 'Mem:           1000         500         200           0         300         400'
mem_case '███▓▓▓░░' 'Mem:              3           1           1           0           1           1'
mem_case '░░░░░░░░' 'Mem:              0           0           0           0           0           0'

new_root
export FREE_OUT=$root/free.out
export NOTIFY_LOG=$root/notify
printf '%s\n%s\n' '              total        used        free      shared  buff/cache   available' 'Mem:           1000         500         200           0         300         400' > "$FREE_OUT"
BLOCK_BUTTON=1 "$SB_MEM" > "$root/got"
if [ "$(cat "$root/got")" = '████▓▓░░' ] && [ -s "$NOTIFY_LOG" ]; then
	ok 'memory button kept'
else
	bad 'memory button kept'
fi

if grep -q sb-musicwave "$SB_MUSIC"; then
	bad 'music still calls waveform'
else
	ok 'music has no waveform'
fi

XB=$HOME/.local/bin/xbacklight
SB_BR=$HOME/.local/bin/statusbar/sb-brightness

backlight() {
	root=$1
	mkdir -p "$root/panel_backlight"
	printf '%s\n' "$2" > "$root/panel_backlight/brightness"
	printf '%s\n' "$3" > "$root/panel_backlight/max_brightness"
}

run_xb() {
	root=$1
	shift
	XBACKLIGHT_ROOT=$root "$XB" "$@"
}

br_root=$(mktemp -d)
backlight "$br_root" 0 27
got=$(run_xb "$br_root" -get)
[ "$got" = 0 ] && ok 'get 0' || bad 'get 0'

run_xb "$br_root" -set 50
[ "$(cat "$br_root/panel_backlight/brightness")" = 14 ] && ok 'set 50 -> 14' || bad 'set 50 -> 14'
[ "$(run_xb "$br_root" -get)" = 52 ] && ok 'get 14 -> 52' || bad 'get 14 -> 52'

run_xb "$br_root" -set 100
[ "$(cat "$br_root/panel_backlight/brightness")" = 27 ] && ok 'set 100' || bad 'set 100'
[ "$(run_xb "$br_root" -get)" = 100 ] && ok 'get 100' || bad 'get 100'

run_xb "$br_root" -set 150
[ "$(cat "$br_root/panel_backlight/brightness")" = 27 ] && ok 'clamp high' || bad 'clamp high'
run_xb "$br_root" -set 0
run_xb "$br_root" -dec 10
[ "$(cat "$br_root/panel_backlight/brightness")" = 1 ] && ok 'clamp low' || bad 'clamp low'
run_xb "$br_root" -inc 10 -time 200 -steps 1
[ "$(cat "$br_root/panel_backlight/brightness")" = 4 ] && ok 'inc ignores time' || bad 'inc ignores time'

if run_xb "$br_root" -set -1 >/dev/null 2>"$br_root/neg.err"; then
	bad 'reject negative'
else
	ok 'reject negative'
fi

empty=$(mktemp -d)
if run_xb "$empty" -get >/dev/null 2>"$empty/err"; then
	bad 'no node'
else
	grep -q 'no backlight device' "$empty/err" && ok 'no node' || bad 'no node'
fi

mkdir -p "$br_root/zzz"
printf '%s\n' 1 > "$br_root/zzz/brightness"
printf '%s\n' 100 > "$br_root/zzz/max_brightness"
backlight "$br_root" 10 100
[ "$(run_xb "$br_root" -get)" = 10 ] && ok 'prefer panel' || bad 'prefer panel'
[ "$(XBACKLIGHT_DEVICE=zzz run_xb "$br_root" -get)" = 1 ] && ok 'device override' || bad 'device override'

first=$(mktemp -d)
mkdir -p "$first/aaa" "$first/zzz"
printf '%s\n' 5 > "$first/aaa/brightness"
printf '%s\n' 27 > "$first/aaa/max_brightness"
printf '%s\n' 0 > "$first/zzz/brightness"
printf '%s\n' 27 > "$first/zzz/max_brightness"
[ "$(run_xb "$first" -get)" = 19 ] && ok 'first node' || bad 'first node'

chmod a-w "$br_root/panel_backlight/brightness"
if run_xb "$br_root" -get >/dev/null; then
	ok 'get ignores write bit'
else
	bad 'get ignores write bit'
fi
before=$(cat "$br_root/panel_backlight/brightness")
if run_xb "$br_root" -set 10 >/dev/null 2>"$br_root/perm.err"; then
	bad 'unwritable'
else
	grep -q 'permission denied' "$br_root/perm.err" && [ "$(cat "$br_root/panel_backlight/brightness")" = "$before" ] && ok 'unwritable' || bad 'unwritable'
fi

none=$(mktemp -d)
export XBACKLIGHT_ROOT=$none
export XDG_RUNTIME_DIR=$none/run
mkdir -p "$XDG_RUNTIME_DIR"
export NOTIFY_LOG=$none/notify
: > "$NOTIFY_LOG"
PATH=$none/bin:$HOME/.local/bin:/usr/bin:/bin
mkdir -p "$none/bin"
cat > "$none/bin/notify-send" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$NOTIFY_LOG"
EOS
chmod 755 "$none/bin/notify-send"
"$SB_BR" > "$none/out"
[ ! -s "$none/out" ] && [ ! -s "$NOTIFY_LOG" ] && ok 'empty no notify' || bad 'empty no notify'

show=$(mktemp -d)
backlight "$show" 0 27
export XBACKLIGHT_ROOT=$show
"$SB_BR" > "$show/out"
[ "$(cat "$show/out")" = '🔆0%' ] && ok 'block 0' || bad 'block 0'
printf '%s\n' 27 > "$show/panel_backlight/brightness"
"$SB_BR" > "$show/out"
[ "$(cat "$show/out")" = '🔆100%' ] && ok 'block 100' || bad 'block 100'

cfg=$HOME/src/dwmblocks/config.h
if grep -F '"sb-brightness",	5,	9,' "$cfg" >/dev/null; then
	ok 'signal 9'
else
	bad 'signal 9'
fi

cool=$(mktemp -d)
export XDG_RUNTIME_DIR=$cool/run
mkdir -p "$XDG_RUNTIME_DIR" "$cool/bin"
export NOTIFY_LOG=$cool/notify
: > "$NOTIFY_LOG"
cat > "$cool/bin/xbacklight" << 'EOS'
#!/bin/sh
exit 1
EOS
cat > "$cool/bin/notify-send" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$NOTIFY_LOG"
EOS
chmod 755 "$cool/bin/xbacklight" "$cool/bin/notify-send"
PATH=$cool/bin:/usr/bin:/bin
BLOCK_BUTTON=4 "$SB_BR" > "$cool/out"
BLOCK_BUTTON=4 "$SB_BR" > "$cool/out"
[ "$(wc -l < "$NOTIFY_LOG")" -eq 1 ] && ok 'cooldown holds' || bad 'cooldown holds'
now=$(date +%s)
printf '%s\n' "$((now - 61))" > "$XDG_RUNTIME_DIR/sb-brightness.$(id -u)/warn"
BLOCK_BUTTON=4 "$SB_BR" > "$cool/out"
[ "$(wc -l < "$NOTIFY_LOG")" -eq 2 ] && [ ! -s "$cool/out" ] && ok 'cooldown expires' || bad 'cooldown expires'

exit "$fail"
