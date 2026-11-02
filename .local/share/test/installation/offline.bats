#!/usr/bin/env bats
# Offline bundle pack and restore. Uses a temporary HOME and real git.
# ls-remote/fetch/sudo are faked. No network and no real install.

load helpers.bash

setup() {
	setup_test_home
	git config --file "$GIT_CONFIG_GLOBAL" user.email test@test.com
	git config --file "$GIT_CONFIG_GLOBAL" user.name Test
	git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch master
	export SUCKLESS_SRC="$HOME/src"
	export OFFLINE_WORKTREE="$HOME/wt"
	export OFFLINE_OUTPUT="$HOME/out/dotfiles-offline.tar.gz"
	export DOTCFG_GIT_DIR="$HOME/.cfg"
	mkdir -p "$HOME/src" "$HOME/remotes" "$HOME/out"
	make_repo "$HOME/wt" "$HOME/remotes/dotfiles.git" 1
	git clone --bare "$HOME/wt" "$HOME/.cfg" >/dev/null
	git --git-dir="$HOME/.cfg" remote set-url origin "$HOME/remotes/dotfiles.git"
	git --git-dir="$HOME/.cfg" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
	git --git-dir="$HOME/.cfg" fetch origin >/dev/null
	git --git-dir="$HOME/.cfg" --work-tree="$HOME/wt" reset -q --mixed HEAD
	local name
	for name in st dmenu dwm dwmblocks; do
		make_repo "$HOME/src/$name" "$HOME/remotes/$name.git" 0
	done
}

teardown() {
	teardown_test_home
}

make_repo() {
	local dir=$1 remote=$2 with_dotcfg=$3
	git init -b master "$dir" >/dev/null
	if [ "$with_dotcfg" -eq 1 ]; then
		mkdir -p "$dir/.local/bin" "$dir/.local/lib/installation"
		printf '#!/bin/sh\nexit 0\n' > "$dir/.local/bin/dotcfg"
		chmod 755 "$dir/.local/bin/dotcfg"
		printf 'validate\n' > "$dir/.local/lib/installation/cfg-validate.sh"
	fi
	printf 'content\n' > "$dir/README"
	git -C "$dir" add -A
	git -C "$dir" commit -m init >/dev/null
	git init --bare "$remote" >/dev/null
	git -C "$dir" remote add origin "$remote"
	git -C "$dir" push -u origin master >/dev/null
}

pack() {
	run "$DOTFILES_ROOT/.local/bin/dotfiles-offline"
}

@test "TC-OFF01: pack members are the installer, bundle, and manifest" {
	pack
	[ "$status" -eq 0 ]
	local members
	members=$(tar -tzf "$OFFLINE_OUTPUT" | LC_ALL=C sort)
	[ "$members" = $'MANIFEST\ndotfiles-offline-install\ndotfiles.bundle' ]
	tar -xOf "$OFFLINE_OUTPUT" MANIFEST | grep -q '^bundle_sha256 '
	local tmp hex
	tmp=$(mktemp -d)
	tar -xzf "$OFFLINE_OUTPUT" -C "$tmp"
	hex=$(awk '$1 == "bundle_sha256" { print $2 }' "$tmp/MANIFEST")
	(
		cd "$tmp"
		printf '%s  dotfiles.bundle\n' "$hex" > check
		sha256sum -c check
	)
	git --git-dir="$DOTCFG_GIT_DIR" bundle verify "$tmp/dotfiles.bundle" >/dev/null
	rm -rf "$tmp"
}

@test "TC-OFF02: tracked dirt and unpushed commits are rejected" {
	printf 'dirty\n' >> "$OFFLINE_WORKTREE/README"
	pack
	[ "$status" -eq 2 ]
	[[ "$output" == *"拒绝：dotfiles 有未提交改动"* ]]
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" reset -q --hard HEAD
	printf 'ahead\n' >> "$OFFLINE_WORKTREE/README"
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" add README
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" commit -m ahead >/dev/null
	pack
	[ "$status" -eq 2 ]
	[[ "$output" == *"拒绝：dotfiles 领先 origin/master "* ]]
}

@test "TC-OFF03: untracked files warn and still pack" {
	printf 'extra\n' > "$OFFLINE_WORKTREE/extra.txt"
	pack
	[ "$status" -eq 0 ]
	[[ "$output" == *"警告：dotfiles 有未跟踪文件，继续打包"* ]]
	[ -f "$OFFLINE_OUTPUT" ]
}

@test "TC-OFF04: an existing archive is not overwritten" {
	pack
	[ "$status" -eq 0 ]
	local before
	before=$(sha256sum "$OFFLINE_OUTPUT")
	pack
	[ "$status" -eq 2 ]
	[[ "$output" == *"拒绝覆盖"* ]]
	[ "$before" = "$(sha256sum "$OFFLINE_OUTPUT")" ]
}

@test "TC-OFF05: a reachable private key rejects the pack and is not printed" {
	local marker=not-a-real-key-body-xyz
	mkdir -p "$OFFLINE_WORKTREE/notes"
	printf '%s\n' "-----BEGIN OPENSSH PRIVATE KEY-----" "$marker" "-----END OPENSSH PRIVATE KEY-----" > "$OFFLINE_WORKTREE/notes/leak.txt"
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" add notes/leak.txt
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" commit -m leak >/dev/null
	git --git-dir="$DOTCFG_GIT_DIR" update-ref refs/remotes/origin/master HEAD
	pack
	[ "$status" -eq 2 ]
	[[ "$output" == *"敏感对象已拒绝：notes/leak.txt"* ]]
	[[ "$output" != *"$marker"* ]]
	[[ "$output" != *"BEGIN OPENSSH PRIVATE KEY"* ]]
}

@test "TC-OFF06: illegal tar members are rejected" {
	local tmp tar
	tmp=$(mktemp -d)
	printf 'x\n' > "$tmp/evil"
	tar -C "$tmp" -czf "$tmp/bad.tgz" evil
	run bash -c 'OFFLINE_LIB_ONLY=1 . "$1"; offline_tar_members_ok "$2"' _ \
		"$DOTFILES_ROOT/.local/lib/installation/commands/offline.sh" "$tmp/bad.tgz"
	[ "$status" -ne 0 ]
	rm -rf "$tmp"
}

@test "TC-OFF07: remote failure exits 2, retry exits 0, and nothing is repeated" {
	pack
	[ "$status" -eq 0 ]
	local new=$HOME/new
	mkdir -p "$new/.config"
	printf 'canary\n' > "$new/.config/canary"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	install_fake_git "$new"
	HOME=$new OFFLINE_HOME=$new DOTCFG_GIT_DIR=$new/.cfg OFFLINE_LS_FAIL=$new/fail \
		PATH=$new/bin:$PATH run "$new/dotfiles-offline-install" </dev/null
	[ "$status" -eq 2 ]
	[ -x "$new/.local/bin/dotcfg" ]
	[ ! -e "$new/.config-backup" ]
	[ "$(cat "$new/.config/canary")" = "canary" ]
	[[ "$output" == *"已检出 dotcfg"* ]]
	[[ "$output" != *"switch fresh"* ]]
	rm -f "$new/fail"
	HOME=$new OFFLINE_HOME=$new DOTCFG_GIT_DIR=$new/.cfg \
		PATH=$new/bin:$PATH run "$new/dotfiles-offline-install" </dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"已有 dotcfg，跳过检出。"* ]]
	[ "$(grep -c 'clone --bare' "$new/git.log")" -eq 1 ]
	[ "$(grep -c ' show ' "$new/git.log")" -eq 2 ]
	[ ! -e "$new/.config-backup" ]
}

@test "TC-OFF08: fixing ownership without a terminal does not call sudo" {
	pack
	[ "$status" -eq 0 ]
	local new=$HOME/new
	mkdir -p "$new"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	install_fake_git "$new"
	cat > "$new/bin/id" << 'EOS'
#!/bin/sh
case ${1:-} in
	-un) printf 'other\n' ;;
	-u|-g) printf '1\n' ;;
	*) exec /usr/bin/id "$@" ;;
esac
EOS
	cat > "$new/bin/sudo" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$SUDO_LOG"
exit 0
EOS
	chmod 755 "$new/bin/id" "$new/bin/sudo"
	: > "$new/sudo.log"
	HOME=$new OFFLINE_HOME=$new DOTCFG_GIT_DIR=$new/.cfg SUDO_LOG=$new/sudo.log \
		OFFLINE_LS_FAIL=$new/fail PATH=$new/bin:$PATH \
		run "$new/dotfiles-offline-install" </dev/null
	[ "$status" -eq 1 ]
	[[ "$output" == *"需要终端才能修正 .cfg 所有权"* ]]
	[ ! -s "$new/sudo.log" ]
}

install_fake_git() {
	local new=$1
	mkdir -p "$new/bin"
	: > "$new/fail"
	: > "$new/git.log"
	cat > "$new/bin/git" << 'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$GIT_LOG"
case " $* " in
	*" ls-remote "*)
		if [ -f "${OFFLINE_LS_FAIL:-}" ]; then
			exit 1
		fi
		printf 'refs/heads/master\t0123456789abcdef\n'
		exit 0
		;;
	*" fetch "*)
		/usr/bin/git --git-dir="$DOTCFG_GIT_DIR" update-ref refs/remotes/origin/master HEAD
		exit 0
		;;
esac
exec /usr/bin/git "$@"
EOS
	chmod 755 "$new/bin/git"
	export GIT_LOG=$new/git.log
}
