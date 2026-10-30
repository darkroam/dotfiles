#!/bin/sh
# shellcheck disable=SC2086,SC2015
# Status bar memory cells, plus music pause/play text. No waveform.

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
mem_case '█████▓▓▓░░' 'Mem:           1000         500         200           0         300         400'
mem_case '████▓▓▓░░░' 'Mem:              3           1           1           0           1           1'
mem_case '░░░░░░░░░░' 'Mem:              0           0           0           0           0           0'

new_root
export FREE_OUT=$root/free.out
export NOTIFY_LOG=$root/notify
printf '%s\n%s\n' '              total        used        free      shared  buff/cache   available' 'Mem:           1000         500         200           0         300         400' > "$FREE_OUT"
BLOCK_BUTTON=1 "$SB_MEM" > "$root/got"
if [ "$(cat "$root/got")" = '█████▓▓▓░░' ] && [ -s "$NOTIFY_LOG" ]; then
	ok 'memory button kept'
else
	bad 'memory button kept'
fi

if grep -q sb-musicwave "$SB_MUSIC"; then
	bad 'music still calls waveform'
else
	ok 'music has no waveform'
fi

exit "$fail"
