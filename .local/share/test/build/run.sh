#!/bin/sh
# Fake git/make/sudo coverage for suckless-rebuild. No real compile or install.

set -u

fail=0
root=$(CDPATH='' cd -- "$(dirname -- "$0")/../../../.." && pwd)
sync=$root/.local/bin/suckless-rebuild

bad() {
	printf 'FAIL %s\n' "$1" >&2
	fail=1
}

ok() {
	printf 'ok %s\n' "$1"
}

new_env() {
	if [ -n "${base:-}" ]; then
		rm -rf "$base"
	fi
	unset PGREP_PID
	base=$(mktemp -d)
	export XDG_RUNTIME_DIR="$base/run"
	mkdir -p "$XDG_RUNTIME_DIR"
	export SUCKLESS_SRC="$base/src"
	export SUCKLESS_PREFIX_BIN="$base/prefix"
	export SUCKLESS_ORIGIN="$base/origin"
	export SUCKLESS_PROC="$base/proc"
	export MAKE_LOG="$base/make.log"
	export GIT_LOG="$base/git.log"
	export SUDO_LOG="$base/sudo.log"
	export INFOCMP_RC="${INFOCMP_RC:-1}"
	mkdir -p "$SUCKLESS_SRC" "$SUCKLESS_PREFIX_BIN" "$base/bin" "$base/proc"
	: > "$MAKE_LOG"
	: > "$GIT_LOG"
	: > "$SUDO_LOG"
	ln -s /usr/bin/sha256sum "$base/bin/sha256sum"
	ln -s /usr/bin/mktemp "$base/bin/mktemp"
	ln -s /usr/bin/tail "$base/bin/tail"
	ln -s /usr/bin/rm "$base/bin/rm"
	ln -s /bin/readlink "$base/bin/readlink" 2>/dev/null || ln -s /usr/bin/readlink "$base/bin/readlink"
	cat > "$base/bin/git" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$GIT_LOG"
case $1 in
	clone)
		dest=$3
		mkdir -p "$dest"
		/usr/bin/git init -b master "$dest" >/dev/null
		/usr/bin/git -C "$dest" config user.email test@test.com
		/usr/bin/git -C "$dest" config user.name Test
		printf 'readme\n' > "$dest/README"
		/usr/bin/git -C "$dest" add README
		/usr/bin/git -C "$dest" commit -m init >/dev/null
		exit 0
		;;
esac
exec /usr/bin/git "$@"
EOS
	cat > "$base/bin/make" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$MAKE_LOG"
dir=
if [ "$1" = -C ]; then
	dir=$2
	shift 2
fi
name=${dir##*/}
if [ "${1:-}" = clean ]; then
	exit 0
fi
if [ "${1:-}" = install ]; then
	/usr/bin/cp "$dir/$name" "$SUCKLESS_PREFIX_BIN/$name"
	exit 0
fi
printf 'built\n' > "$dir/$name"
exit 0
EOS
	cat > "$base/bin/sudo" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$SUDO_LOG"
shift
exec "$@"
EOS
	cat > "$base/bin/pkg-config" << 'EOS'
#!/bin/sh
exit 0
EOS
	cat > "$base/bin/gcc" << 'EOS'
#!/bin/sh
exit 0
EOS
	cat > "$base/bin/tic" << 'EOS'
#!/bin/sh
exit 0
EOS
	cat > "$base/bin/infocmp" << 'EOS'
#!/bin/sh
exit "$INFOCMP_RC"
EOS
	cat > "$base/bin/pgrep" << 'EOS'
#!/bin/sh
if [ -n "${PGREP_PID:-}" ]; then
	printf '%s\n' "$PGREP_PID"
fi
exit 0
EOS
	chmod 755 "$base/bin/git" "$base/bin/make" "$base/bin/sudo" "$base/bin/pkg-config" \
		"$base/bin/gcc" "$base/bin/tic" "$base/bin/infocmp" "$base/bin/pgrep"
	# PATH stays real for the harness. sync_run hides it.
}

sync_run() {
	PATH=$base/bin "$sync" "$@"
}

seed_repo() {
	name=$1
	dir=$SUCKLESS_SRC/$name
	mkdir -p "$dir"
	/usr/bin/git init -b master "$dir" >/dev/null
	/usr/bin/git -C "$dir" config user.email test@test.com
	/usr/bin/git -C "$dir" config user.name Test
	printf 'readme\n' > "$dir/README"
	/usr/bin/git -C "$dir" add README
	/usr/bin/git -C "$dir" commit -m init >/dev/null
}

# usage
new_env
if sync_run foo >/dev/null 2>"$base/err"; then
	bad "bad name should fail"
else
	ok "bad name rejected"
fi
if sync_run st dmenu >/dev/null 2>>"$base/err"; then
	bad "two names should fail"
else
	ok "two names rejected"
fi

# missing compiler
new_env
rm -f "$base/bin/gcc"
if sync_run st </dev/null >/dev/null 2>"$base/err"; then
	bad "missing gcc should fail"
elif ! grep -q '缺少命令：gcc' "$base/err"; then
	bad "missing gcc message"
else
	ok "missing gcc"
fi

# not a git repo
new_env
mkdir -p "$SUCKLESS_SRC/st"
if sync_run st </dev/null >/dev/null 2>"$base/err"; then
	bad "non-repo should fail"
elif ! grep -q '不是 git 仓库' "$base/err"; then
	bad "non-repo message"
else
	ok "non-repo rejected"
fi

# dirty tree, same sha, no pull, terminfo warning
new_env
seed_repo st
printf 'dirty\n' >> "$SUCKLESS_SRC/st/README"
printf 'built\n' > "$SUCKLESS_PREFIX_BIN/st"
if sync_run st </dev/null >"$base/out" 2>"$base/err"; then
	:
else
	bad "dirty sync failed: $(cat "$base/err")"
fi
mods=$(grep -c '本地修改：st' "$base/err" || true)
if [ "$mods" -ne 1 ]; then
	bad "local modification line count $mods"
else
	ok "one local modification line"
fi
if grep -Eq 'pull|reset|stash' "$GIT_LOG"; then
	bad "git history rewritten"
else
	ok "no pull reset stash"
fi
if [ -s "$SUDO_LOG" ]; then
	bad "sudo used for same sha"
else
	ok "same sha skips sudo"
fi
if ! grep -q 'terminfo 风险：缺少 st-256color' "$base/err"; then
	bad "terminfo warning missing"
else
	ok "terminfo warning"
fi

# different sha, no tty
new_env
seed_repo dmenu
printf 'old\n' > "$SUCKLESS_PREFIX_BIN/dmenu"
if sync_run dmenu </dev/null >/dev/null 2>"$base/err"; then
	bad "non-tty install should fail"
elif ! grep -q '需要终端才能安装：dmenu' "$base/err"; then
	bad "non-tty message"
elif [ -s "$SUDO_LOG" ]; then
	bad "sudo called without tty"
else
	ok "non-tty refuses sudo"
fi

# clean is not a command
new_env
seed_repo dwm
if sync_run clean >/dev/null 2>"$base/err"; then
	bad "clean should fail"
elif ! grep -q '用法：suckless-rebuild' "$base/err"; then
	bad "clean usage: $(cat "$base/err")"
elif [ -s "$MAKE_LOG" ]; then
	bad "clean ran make"
else
	ok "clean rejected"
fi

# clone failure
new_env
cat > "$base/bin/git" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$GIT_LOG"
exit 1
EOS
chmod 755 "$base/bin/git"
if sync_run dwmblocks </dev/null >/dev/null 2>"$base/err"; then
	bad "clone failure should stop"
elif ! grep -q 'clone 失败：dwmblocks' "$base/err"; then
	bad "clone failure message"
else
	ok "clone failure stops"
fi

# old process is reported, not killed
new_env
export PGREP_PID=9
seed_repo st
printf 'built\n' > "$SUCKLESS_PREFIX_BIN/st"
mkdir -p "$SUCKLESS_PROC/9"
printf 'old\n' > "$base/old-st"
ln -s "$base/old-st" "$SUCKLESS_PROC/9/exe"
if sync_run st </dev/null >/dev/null 2>"$base/err"; then
	:
else
	bad "old process sync failed"
fi
if ! grep -q '旧进程仍在运行：st pid 9（不结束进程）' "$base/err"; then
	bad "old process not reported: $(cat "$base/err")"
else
	ok "old process reported"
fi
if grep -q 'kill' "$base/err" "$SUDO_LOG" "$MAKE_LOG"; then
	bad "process was killed"
else
	ok "process not killed"
fi

# tty install
new_env
seed_repo st
export INFOCMP_RC=0
printf 'other\n' > "$SUCKLESS_PREFIX_BIN/st"
if script -q -e -c "PATH=\"$base/bin\" \"$sync\" st" /dev/null >"$base/out" 2>"$base/err"; then
	if ! grep -q '^-k make -C '"$SUCKLESS_SRC"'/st install$' "$SUDO_LOG"; then
		bad "tty sudo args: $(cat "$SUDO_LOG")"
	else
		ok "tty runs sudo make install"
	fi
else
	bad "tty install failed: $(cat "$base/err")"
fi

rm -rf "$base"
if [ "$fail" -eq 0 ]; then
	printf 'build tests passed\n'
	exit 0
fi
exit 1
