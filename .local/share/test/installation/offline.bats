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
	export OFFLINE_OUTPUT="$HOME/out/dotcfg-offline.tar.gz"
	export DOTCFG_GIT_DIR="$HOME/.cfg"
	mkdir -p "$HOME/src" "$HOME/remotes" "$HOME/out"
	make_repo "$HOME/wt" "$HOME/remotes/dotfiles.git" 1
	seed_public_docs "$HOME/wt"
	git clone --bare "$HOME/wt" "$HOME/.cfg" >/dev/null
	git --git-dir="$HOME/.cfg" remote set-url origin "$HOME/remotes/dotfiles.git"
	git --git-dir="$HOME/.cfg" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
	git --git-dir="$HOME/.cfg" fetch origin >/dev/null
	git --git-dir="$HOME/.cfg" --work-tree="$HOME/wt" reset -q --mixed HEAD
	git --git-dir="$HOME/.cfg" branch x11 HEAD
	git --git-dir="$HOME/.cfg" branch wayland HEAD
	git --git-dir="$HOME/.cfg" symbolic-ref HEAD refs/heads/x11
	git --git-dir="$HOME/.cfg" push -q origin x11 wayland
	git --git-dir="$HOME/.cfg" fetch -q origin
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

seed_public_docs() {
	local dir=$1
	mkdir -p "$dir/.local/share/docs/user"
	printf 'docs index\n' > "$dir/.local/share/docs/README.md"
	printf 'desktop guide\n' > "$dir/.local/share/docs/user/desktop-guide-zh.md"
	git -C "$dir" add -- .local/share/docs/README.md .local/share/docs/user/desktop-guide-zh.md
	git -C "$dir" commit -m 'public docs' >/dev/null
	git -C "$dir" push -q origin master
}

on_branch() {
	local branch=$1
	git --git-dir="$DOTCFG_GIT_DIR" symbolic-ref HEAD "refs/heads/$branch"
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" reset -q --hard "$branch"
}

publish() {
	local branch=$1 msg=$2
	shift 2
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" add -- "$@"
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" commit -q -m "$msg"
	git --git-dir="$DOTCFG_GIT_DIR" push -q origin "$branch"
	git --git-dir="$DOTCFG_GIT_DIR" fetch -q origin
}

pack() {
	run "$DOTFILES_ROOT/.local/bin/dotcfg-offline" "$@"
}

assert_readme() {
	local want=$1 dir rc
	dir=$(mktemp -d)
	tar -xzf "$OFFLINE_OUTPUT" -C "$dir"
	git clone -q "$dir/dotfiles.bundle" "$dir/repo"
	printf '%s' "$want" > "$dir/want"
	git -C "$dir/repo" show HEAD:README > "$dir/got"
	cmp -s "$dir/want" "$dir/got"
	rc=$?
	rm -rf "$dir"
	return "$rc"
}

check_manifest() {
	local dir=$1
	(
		cd "$dir"
		awk '$1 ~ /\.bundle$/ { printf "%s  %s\n", $2, $1 }' MANIFEST > check
		sha256sum -c --status check
	)
}

@test "TC-OFF01: pack members are the installer, bundle, and manifest" {
	pack
	[ "$status" -eq 0 ]
	[[ "$output" != *"警告"* ]]
	local members want tmp
	members=$(tar -tzf "$OFFLINE_OUTPUT" | LC_ALL=C sort)
	want=$(printf '%s\n' MANIFEST dotcfg-offline-install dotfiles.bundle | LC_ALL=C sort)
	[ "$members" = "$want" ]
	tmp=$(mktemp -d)
	tar -xzf "$OFFLINE_OUTPUT" -C "$tmp"
	grep -q '^time ' "$tmp/MANIFEST"
	grep -qx 'target x11' "$tmp/MANIFEST"
	grep -q '^dotfiles ' "$tmp/MANIFEST"
	check_manifest "$tmp"
	git --git-dir="$DOTCFG_GIT_DIR" bundle verify "$tmp/dotfiles.bundle" >/dev/null
	[ ! -e "$HOME/src/st/.cleaned" ]
	rm -rf "$tmp"
}

@test "TC-OFF02: ahead, behind, and dirty still pack the current target" {
	printf 'ahead\n' >> "$OFFLINE_WORKTREE/README"
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" add README
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" commit -m ahead >/dev/null
	pack
	[ "$status" -eq 0 ]
	[[ "$output" == *"警告：dotfiles 当前 HEAD 领先 origin/x11 1 笔（含未合并任务分支提交）"* ]]
	assert_readme $'content\n'

	rm -f "$OFFLINE_OUTPUT"
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" push -q origin HEAD:x11
	git --git-dir="$DOTCFG_GIT_DIR" fetch -q origin
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" reset -q --hard HEAD~1
	pack
	[ "$status" -eq 0 ]
	assert_readme $'content\nahead\n'

	rm -f "$OFFLINE_OUTPUT"
	printf 'dirty\n' >> "$OFFLINE_WORKTREE/README"
	printf 'extra\n' > "$OFFLINE_WORKTREE/extra.txt"
	pack
	[ "$status" -eq 0 ]
	[[ "$output" == *"警告：dotfiles 有未提交改动，不进入包"* ]]
	[[ "$output" == *"未跟踪"* ]]
	assert_readme $'content\nahead\n'
}

@test "TC-OFF03: --with-suckless bundles origin/master" {
	local origin_sha tmp new name members want
	origin_sha=$(git -C "$HOME/src/st" rev-parse origin/master)
	printf 'ahead\n' >> "$HOME/src/st/README"
	git -C "$HOME/src/st" add README
	git -C "$HOME/src/st" commit -m ahead >/dev/null
	printf 'dirty\n' >> "$HOME/src/st/README"
	pack --with-suckless
	[ "$status" -eq 0 ]
	[[ "$output" == *"警告：st 有未提交改动，不进入包"* ]]
	[[ "$output" != *"Makefile"* ]]
	members=$(tar -tzf "$OFFLINE_OUTPUT" | LC_ALL=C sort)
	want=$(printf '%s\n' MANIFEST dotcfg-offline-install dotfiles.bundle \
		src/st.bundle src/dmenu.bundle src/dwm.bundle src/dwmblocks.bundle | LC_ALL=C sort)
	[ "$members" = "$want" ]
	tmp=$(mktemp -d)
	tar -xzf "$OFFLINE_OUTPUT" -C "$tmp"
	check_manifest "$tmp"
	git clone -q "$tmp/src/st.bundle" "$tmp/st"
	[ "$(git -C "$tmp/st" rev-parse HEAD)" = "$origin_sha" ]
	new=$HOME/new
	mkdir -p "$new"
	install_fake_git "$new"
	rm -f "$new/fail"
	OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$tmp/dotcfg-offline-install" </dev/null
	[ "$status" -eq 0 ]
	[[ "$output" != *"已有源码"* ]]
	[ -d "$new/src/st/.git" ]
	[ "$(git -C "$new/src/st" remote get-url origin)" = "$HOME/remotes/st.git" ]
	OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$tmp/dotcfg-offline-install" </dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"已有源码，保留：st"* ]]
	[[ "$output" == *"已有 dotcfg，跳过检出。"* ]]
	[ "$(grep -c 'src/st.bundle' "$new/git.log")" -eq 1 ]
	rm -rf "$tmp"
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

@test "TC-OFF05: only a key reachable from the target ref is rejected" {
	local marker=not-a-real-key-body-xyz dir begin end
	begin=$(printf '%s%s%s' '-----BE' 'GIN OPENSSH ' 'PRIVATE KEY-----')
	end=$(printf '%s%s%s' '-----E' 'ND OPENSSH ' 'PRIVATE KEY-----')
	mkdir -p "$OFFLINE_WORKTREE/notes"
	printf '%s\n' "$begin" "$marker" "$end" > "$OFFLINE_WORKTREE/notes/leak.txt"
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" add notes/leak.txt
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" commit -m leak >/dev/null
	pack
	[ "$status" -eq 0 ]
	[[ "$output" != *"$marker"* ]]
	dir=$(mktemp -d)
	tar -xzf "$OFFLINE_OUTPUT" -C "$dir"
	git clone -q "$dir/dotfiles.bundle" "$dir/repo"
	! git -C "$dir/repo" cat-file -e 'HEAD:notes/leak.txt'
	rm -rf "$dir" "$OFFLINE_OUTPUT"
	git --git-dir="$DOTCFG_GIT_DIR" update-ref refs/remotes/origin/x11 HEAD
	pack
	[ "$status" -eq 2 ]
	[[ "$output" == *"敏感对象已拒绝：notes/leak.txt"* ]]
	[[ "$output" != *"$marker"* ]]
	[[ "$output" != *"$begin"* ]]
}

@test "TC-OFF06: illegal tar members and path escape are rejected" {
	local tmp
	tmp=$(mktemp -d)
	printf 'x\n' > "$tmp/evil"
	tar -C "$tmp" -czf "$tmp/bad.tgz" evil
	run bash -c 'OFFLINE_LIB_ONLY=1 . "$1"; offline_tar_members_ok "$2"' _ \
		"$DOTFILES_ROOT/.local/lib/installation/commands/offline.sh" "$tmp/bad.tgz"
	[ "$status" -ne 0 ]
	python3 - "$tmp/escape.tgz" << 'ENDTAR'
import io, sys, tarfile
tar = tarfile.open(sys.argv[1], "w:gz")
data = b"x\n"
info = tarfile.TarInfo("../secret")
info.size = len(data)
tar.addfile(info, io.BytesIO(data))
tar.close()
ENDTAR
	run bash -c 'OFFLINE_LIB_ONLY=1 . "$1"; offline_tar_members_ok "$2"' _ \
		"$DOTFILES_ROOT/.local/lib/installation/commands/offline.sh" "$tmp/escape.tgz"
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
	OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new DOTCFG_GIT_DIR=$new/.cfg OFFLINE_LS_FAIL=$new/fail \
		PATH=$new/bin:$PATH run "$new/dotcfg-offline-install" </dev/null
	[ "$status" -eq 2 ]
	[ "$(git --git-dir="$new/.cfg" symbolic-ref --short HEAD)" = x11 ]
	! git --git-dir="$new/.cfg" rev-parse --verify --quiet refs/heads/master >/dev/null
	[ -x "$new/.local/bin/dotcfg" ]
	[ ! -e "$new/.config-backup" ]
	[ "$(cat "$new/.config/canary")" = "canary" ]
	[[ "$output" == *"已检出 dotcfg"* ]]
	[[ "$output" != *"switch fresh"* ]]
	[[ "$output" != *"bundle verify"* ]]
	rm -f "$new/fail"
	HOME=$new OFFLINE_HOME=$new DOTCFG_GIT_DIR=$new/.cfg \
		PATH=$new/bin:$PATH run "$new/dotcfg-offline-install" </dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"已有 dotcfg，跳过检出。"* ]]
	[[ "$(git --git-dir="$new/.cfg" config --get remote.origin.fetch)" == *refs/remotes/origin/* ]]
	[ "$(grep -c -- '--bare' "$new/git.log")" -eq 1 ]
	[ "$(grep -c ' show ' "$new/git.log")" -eq 4 ]
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
		run "$new/dotcfg-offline-install" </dev/null
	[ "$status" -eq 1 ]
	[[ "$output" == *"需要终端才能修正 .cfg 所有权"* ]]
	[ ! -s "$new/sudo.log" ]
}

@test "TC-OFF09: invalid source origin fails before cloning sources" {
	pack --with-suckless
	[ "$status" -eq 0 ]
	local new=$HOME/new
	mkdir -p "$new"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	install_fake_git "$new"
	OFFLINE_ORIGIN=https://mirror.invalid/group/notdotfiles HOME=$new OFFLINE_HOME=$new \
		DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$new/dotcfg-offline-install" </dev/null
	[ "$status" -eq 1 ]
	[[ "$output" == *"无法从 OFFLINE_ORIGIN 推导源码地址"* ]]
	[ ! -e "$new/src/st" ]
	rm -rf "$new"
}

@test "TC-OFF10: an existing source repo with bundle origin is repaired" {
	pack --with-suckless
	[ "$status" -eq 0 ]
	local new=$HOME/new tmp
	tmp=$(mktemp -d)
	tar -xzf "$OFFLINE_OUTPUT" -C "$tmp"
	mkdir -p "$new/src"
	git clone -q "$tmp/src/st.bundle" "$new/src/st"
	install_fake_git "$new"
	OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new \
		DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$tmp/dotcfg-offline-install" </dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"已有源码，保留：st"* ]]
	[ "$(git -C "$new/src/st" remote get-url origin)" = "$HOME/remotes/st.git" ]
	rm -rf "$new" "$tmp"
}


@test "TC-OFF11: --branch selects x11 or wayland and does not retarget sources" {
	local way_sha src_sha tmp
	git --git-dir="$DOTCFG_GIT_DIR" symbolic-ref HEAD refs/heads/wayland
	printf 'wayland\n' > "$OFFLINE_WORKTREE/README"
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" add README
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" commit -q -m wayland
	way_sha=$(git --git-dir="$DOTCFG_GIT_DIR" rev-parse HEAD)
	git --git-dir="$DOTCFG_GIT_DIR" push -q origin wayland
	git --git-dir="$DOTCFG_GIT_DIR" fetch -q origin
	git --git-dir="$DOTCFG_GIT_DIR" symbolic-ref HEAD refs/heads/x11
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" reset -q --hard x11
	src_sha=$(git -C "$HOME/src/st" rev-parse origin/master)
	pack --branch wayland --with-suckless
	[ "$status" -eq 0 ]
	tmp=$(mktemp -d)
	tar -xzf "$OFFLINE_OUTPUT" -C "$tmp"
	grep -qx 'target wayland' "$tmp/MANIFEST"
	! grep -q '冻结锚点' "$tmp/MANIFEST"
	git clone -q "$tmp/dotfiles.bundle" "$tmp/repo"
	[ "$(git -C "$tmp/repo" rev-parse HEAD)" = "$way_sha" ]
	git clone -q "$tmp/src/st.bundle" "$tmp/st"
	[ "$(git -C "$tmp/st" rev-parse HEAD)" = "$src_sha" ]
	rm -rf "$tmp" "$OFFLINE_OUTPUT"
	pack --branch x11 --with-suckless
	[ "$status" -eq 0 ]
	tmp=$(mktemp -d)
	tar -xzf "$OFFLINE_OUTPUT" -C "$tmp"
	grep -qx 'target x11' "$tmp/MANIFEST"
	[ -f "$tmp/src/st.bundle" ]
	git clone -q "$tmp/dotfiles.bundle" "$tmp/repo"
	git -C "$tmp/repo" show HEAD:README > "$tmp/got"
	printf 'content\n' > "$tmp/want"
	cmp -s "$tmp/want" "$tmp/got"
	git clone -q "$tmp/src/st.bundle" "$tmp/st"
	[ "$(git -C "$tmp/st" rev-parse HEAD)" = "$src_sha" ]
	rm -rf "$tmp"
}

@test "TC-OFF12: master is refused unless the stale target is explicit" {
	git --git-dir="$DOTCFG_GIT_DIR" symbolic-ref HEAD refs/heads/master
	pack
	[ "$status" -eq 2 ]
	[[ "$output" == *"冻结锚点"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]
	pack --allow-stale-target
	[ "$status" -eq 0 ]
	local tmp
	tmp=$(mktemp -d)
	tar -xzf "$OFFLINE_OUTPUT" -C "$tmp"
	grep -qx 'target master' "$tmp/MANIFEST"
	grep -qx 'note 冻结锚点' "$tmp/MANIFEST"
	rm -rf "$tmp"
	git --git-dir="$DOTCFG_GIT_DIR" branch task/nope HEAD
	git --git-dir="$DOTCFG_GIT_DIR" symbolic-ref HEAD refs/heads/task/nope
	rm -f "$OFFLINE_OUTPUT"
	pack
	[ "$status" -eq 2 ]
	[[ "$output" == *"无法确定"* ]]

	git --git-dir="$DOTCFG_GIT_DIR" symbolic-ref HEAD refs/heads/master
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" reset -q --hard master
	printf 'local-master\n' >> "$OFFLINE_WORKTREE/README"
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" add README
	git --git-dir="$DOTCFG_GIT_DIR" --work-tree="$OFFLINE_WORKTREE" commit -qm local-master
	pack --allow-stale-target
	[ "$status" -eq 2 ]
	[[ "$output" == *"HEAD 不等于 origin/master"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]

	git --git-dir="$DOTCFG_GIT_DIR" symbolic-ref HEAD refs/heads/x11
	pack --allow-stale-target
	[ "$status" -eq 2 ]
	[[ "$output" == *"只适用于冻结 master"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]
	pack --branch wayland --allow-stale-target
	[ "$status" -eq 2 ]
	[[ "$output" == *"只适用于冻结 master"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]
}

@test "TC-OFF13: the installer remote gate follows the manifest target" {
	local new=$HOME/new
	pack --branch wayland
	[ "$status" -eq 0 ]
	mkdir -p "$new"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	install_fake_git "$new"
	rm -f "$new/fail"
	OFFLINE_LS_HEAD=x11 OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new \
		DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$new/dotcfg-offline-install" </dev/null
	[ "$status" -eq 2 ]
	[[ "$output" == *"wayland"* ]]
	OFFLINE_LS_HEAD=wayland OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new \
		DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$new/dotcfg-offline-install" </dev/null
	[ "$status" -eq 0 ]
	rm -rf "$new" "$OFFLINE_OUTPUT"
	pack --branch x11
	[ "$status" -eq 0 ]
	mkdir -p "$new"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	install_fake_git "$new"
	rm -f "$new/fail"
	OFFLINE_LS_HEAD=wayland OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new \
		DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$new/dotcfg-offline-install" </dev/null
	[ "$status" -eq 2 ]
	OFFLINE_LS_HEAD=x11 OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new \
		DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$new/dotcfg-offline-install" </dev/null
	[ "$status" -eq 0 ]
	rm -rf "$new"
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
		printf 'refs/heads/%s\t0123456789abcdef\n' "${OFFLINE_LS_HEAD:-x11}"
		exit 0
		;;
esac
exec /usr/bin/git "$@"
EOS
	chmod 755 "$new/bin/git"
	export GIT_LOG=$new/git.log
}

@test "TC-OFF14: an existing cfg takes the manifest branch and can pack again" {
	pack
	[ "$status" -eq 0 ]
	local new=$HOME/new bad=$HOME/bad
	mkdir -p "$new"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	git clone -q --bare "$new/dotfiles.bundle" "$new/.cfg"
	install_fake_git "$new"
	rm -f "$new/fail"
	OFFLINE_LS_HEAD=x11 OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new \
		DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$new/dotcfg-offline-install" </dev/null
	[ "$status" -eq 0 ]
	[ "$(git --git-dir="$new/.cfg" symbolic-ref --short HEAD)" = x11 ]
	! git --git-dir="$new/.cfg" rev-parse --verify --quiet refs/heads/master >/dev/null
	mkdir -p "$new/wt" "$new/out"
	git --git-dir="$new/.cfg" --work-tree="$new/wt" checkout -q -f HEAD -- .
	OFFLINE_WORKTREE=$new/wt OFFLINE_OUTPUT=$new/out/again.tar.gz DOTCFG_GIT_DIR=$new/.cfg \
		HOME=$new run "$DOTFILES_ROOT/.local/bin/dotcfg-offline"
	[ "$status" -eq 0 ]
	[[ "$output" != *"无法确定"* ]]
	grep -qx 'target x11' <(tar -xOzf "$new/out/again.tar.gz" MANIFEST)

	mkdir -p "$bad"
	tar -xzf "$OFFLINE_OUTPUT" -C "$bad"
	git clone -q --bare "$bad/dotfiles.bundle" "$bad/.cfg"
	git --git-dir="$bad/.cfg" branch x11 HEAD
	install_fake_git "$bad"
	rm -f "$bad/fail"
	OFFLINE_LS_HEAD=x11 OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$bad OFFLINE_HOME=$bad \
		DOTCFG_GIT_DIR=$bad/.cfg PATH=$bad/bin:$PATH \
		run "$bad/dotcfg-offline-install" </dev/null
	[ "$status" -eq 1 ]
	[[ "$output" == *"无法将 master 改名为 x11"* ]]
	[ "$(git --git-dir="$bad/.cfg" symbolic-ref --short HEAD)" = master ]

	local weird=$HOME/weird det=$HOME/det head_sha
	mkdir -p "$weird"
	tar -xzf "$OFFLINE_OUTPUT" -C "$weird"
	git clone -q --bare "$weird/dotfiles.bundle" "$weird/.cfg"
	git --git-dir="$weird/.cfg" branch weird HEAD
	git --git-dir="$weird/.cfg" symbolic-ref HEAD refs/heads/weird
	head_sha=$(git --git-dir="$weird/.cfg" rev-parse HEAD)
	install_fake_git "$weird"
	rm -f "$weird/fail"
	OFFLINE_LS_HEAD=x11 OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$weird OFFLINE_HOME=$weird \
		DOTCFG_GIT_DIR=$weird/.cfg PATH=$weird/bin:$PATH \
		run "$weird/dotcfg-offline-install" </dev/null
	[ "$status" -eq 1 ]
	[[ "$output" == *"本地分支是 weird"* ]]
	[ "$(git --git-dir="$weird/.cfg" symbolic-ref --short HEAD)" = weird ]
	[ "$(git --git-dir="$weird/.cfg" rev-parse HEAD)" = "$head_sha" ]
	! git --git-dir="$weird/.cfg" rev-parse --verify --quiet refs/heads/x11 >/dev/null

	mkdir -p "$det"
	tar -xzf "$OFFLINE_OUTPUT" -C "$det"
	git clone -q --bare "$det/dotfiles.bundle" "$det/.cfg"
	head_sha=$(git --git-dir="$det/.cfg" rev-parse HEAD)
	git --git-dir="$det/.cfg" update-ref --no-deref HEAD "$head_sha"
	install_fake_git "$det"
	rm -f "$det/fail"
	OFFLINE_LS_HEAD=x11 OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$det OFFLINE_HOME=$det \
		DOTCFG_GIT_DIR=$det/.cfg PATH=$det/bin:$PATH \
		run "$det/dotcfg-offline-install" </dev/null
	[ "$status" -eq 1 ]
	[[ "$output" == *"本地分支是 detached"* ]]
	! git --git-dir="$det/.cfg" symbolic-ref --short HEAD >/dev/null
	[ "$(git --git-dir="$det/.cfg" rev-parse HEAD)" = "$head_sha" ]
	! git --git-dir="$det/.cfg" rev-parse --verify --quiet refs/heads/x11 >/dev/null
	rm -rf "$new" "$bad" "$weird" "$det"
}

run_install() {
	local new=$1 target=$2
	install_fake_git "$new"
	rm -f "$new/fail"
	OFFLINE_LS_HEAD=$target OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new \
		DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$new/dotcfg-offline-install" </dev/null
}

assert_same_line_blobs() {
	local gitdir=$1 old=$2 new=$3 a b
	a=$(git --git-dir="$gitdir" rev-parse "HEAD:$old")
	b=$(git --git-dir="$gitdir" rev-parse "HEAD:$new")
	[ "$a" = "$b" ]
}

@test "TC-OFF15: a non-whitelist path is not written after a hit" {
	on_branch x11
	printf 'nope\n' > "$OFFLINE_WORKTREE/.local/lib/installation/notes.txt"
	printf 'nope\n' > "$OFFLINE_WORKTREE/zzz-outside.txt"
	publish x11 outside .local/lib/installation/notes.txt zzz-outside.txt
	pack
	[ "$status" -eq 0 ]
	local new=$HOME/new
	mkdir -p "$new"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	run_install "$new" x11
	[ "$status" -eq 0 ]
	[ -f "$new/.local/share/docs/README.md" ]
	[ -f "$new/.local/share/docs/user/desktop-guide-zh.md" ]
	[ ! -e "$new/.local/lib/installation/notes.txt" ]
	[ ! -e "$new/zzz-outside.txt" ]
	[ "$(grep -c ' show ' "$new/git.log")" -eq 4 ]
}

@test "TC-OFF16: each target checks out only its own stack and does not rewrite" {
	on_branch x11
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11"
	printf 'x11 display\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/display.md"
	publish x11 'x11 stacks' .local/share/docs/stacks/x11/display.md
	pack --branch x11
	[ "$status" -eq 0 ]
	local new=$HOME/new shows
	mkdir -p "$new"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	run_install "$new" x11
	[ "$status" -eq 0 ]
	[ "$(cat "$new/.local/share/docs/stacks/x11/display.md")" = "x11 display" ]
	[ ! -e "$new/.local/share/docs/stacks/wayland" ]
	printf 'edited\n' > "$new/.local/share/docs/stacks/x11/display.md"
	printf 'edited-public\n' > "$new/.local/share/docs/README.md"
	shows=$(grep -c ' show ' "$new/git.log")
	OFFLINE_LS_HEAD=x11 OFFLINE_ORIGIN=$HOME/remotes/dotfiles.git HOME=$new OFFLINE_HOME=$new \
		DOTCFG_GIT_DIR=$new/.cfg PATH=$new/bin:$PATH \
		run "$new/dotcfg-offline-install" </dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"已有 dotcfg，跳过检出。"* ]]
	[ "$(cat "$new/.local/share/docs/stacks/x11/display.md")" = "edited" ]
	[ "$(cat "$new/.local/share/docs/README.md")" = "edited-public" ]
	[ "$(grep -c ' show ' "$new/git.log")" -eq "$shows" ]

	on_branch wayland
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/wayland"
	printf 'wayland ghostty\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/wayland/ghostty.md"
	publish wayland 'wayland stacks' .local/share/docs/stacks/wayland/ghostty.md
	rm -rf "$new" "$OFFLINE_OUTPUT"
	pack --branch wayland
	[ "$status" -eq 0 ]
	mkdir -p "$new"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	run_install "$new" wayland
	[ "$status" -eq 0 ]
	[ "$(cat "$new/.local/share/docs/stacks/wayland/ghostty.md")" = "wayland ghostty" ]
	[ ! -e "$new/.local/share/docs/stacks/x11" ]
}

@test "TC-OFF17: a line switch deletes only manifest files and warns" {
	on_branch x11
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11"
	printf 'display\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/display.md"
	publish x11 'clean x11' .local/share/docs/stacks/x11/display.md
	pack --branch x11
	[ "$status" -eq 0 ]
	local x11home=$HOME/x11home way=$HOME/way
	mkdir -p "$x11home"
	tar -xzf "$OFFLINE_OUTPUT" -C "$x11home"
	run_install "$x11home" x11
	[ "$status" -eq 0 ]
	[ -f "$x11home/.cfg/offline-docs-manifest" ]
	[ ! -e "$x11home/.local/state/dotcfg/offline-docs-manifest" ]
	[ ! -e "$x11home/.local/share/docs/.offline-docs-manifest" ]
	grep -qx '.local/share/docs/stacks/x11/display.md' \
		"$x11home/.cfg/offline-docs-manifest"
	grep -qxF .cfg "$x11home/.cfg/info/exclude"
	! git --git-dir="$x11home/.cfg" ls-tree -r --name-only HEAD | grep -q offline-docs-manifest
	[[ "$output" != *"删除 0"* ]]
	git --git-dir="$x11home/.cfg" --work-tree="$x11home" add -A
	! git --git-dir="$x11home/.cfg" --work-tree="$x11home" diff --cached --name-only | grep -q offline-docs-manifest
	run git --git-dir="$x11home/.cfg" --work-tree="$x11home" add -- .cfg/offline-docs-manifest
	[ "$status" -ne 0 ]

	on_branch wayland
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/wayland"
	printf 'ghostty\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/wayland/ghostty.md"
	publish wayland 'clean wayland' .local/share/docs/stacks/wayland/ghostty.md
	rm -f "$OFFLINE_OUTPUT"
	pack --branch wayland
	[ "$status" -eq 0 ]
	mkdir -p "$way/.local/share/docs/stacks/x11" "$way/.local/share/docs/stacks/wayland"
	cp "$x11home/.local/share/docs/stacks/x11/display.md" \
		"$way/.local/share/docs/stacks/x11/display.md"
	printf 'mine\n' > "$way/.local/share/docs/stacks/x11/user-note.md"
	printf 'local\n' > "$way/.local/share/docs/stacks/wayland/local.md"
	printf 'keep-public\n' > "$way/.local/share/docs/README.md"
	tar -xzf "$OFFLINE_OUTPUT" -C "$way"
	git clone -q --bare "$way/dotfiles.bundle" "$way/.cfg"
	cp "$x11home/.cfg/offline-docs-manifest" "$way/.cfg/offline-docs-manifest"
	run_install "$way" wayland
	[ "$status" -eq 0 ]
	[[ "$output" == *"删除 .local/share/docs/stacks/x11/display.md"* ]]
	[[ "$output" == *"删除 1 个清单文件"* ]]
	[[ "$output" == *"警告：工作树仍有对面栈目录 .local/share/docs/stacks/x11"* ]]
	[ ! -e "$way/.local/share/docs/stacks/x11/display.md" ]
	[ "$(cat "$way/.local/share/docs/stacks/x11/user-note.md")" = "mine" ]
	[ "$(cat "$way/.local/share/docs/stacks/wayland/local.md")" = "local" ]
	[ "$(cat "$way/.local/share/docs/stacks/wayland/ghostty.md")" = "ghostty" ]
	[ "$(cat "$way/.local/share/docs/README.md")" = "keep-public" ]
	grep -qx '.local/share/docs/stacks/wayland/ghostty.md' \
		"$way/.cfg/offline-docs-manifest"
	! grep -q 'display.md' "$way/.cfg/offline-docs-manifest"
	! grep -q 'user-note' "$way/.cfg/offline-docs-manifest"
	! grep -q 'local.md' "$way/.cfg/offline-docs-manifest"
	[[ "$output" == *"已检出 dotcfg"* ]]
	[[ "$output" == *"删除 1 个清单文件。"* ]]
}

@test "TC-OFF18: master packing refuses a non-empty stacks tree" {
	on_branch master
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11" \
		"$OFFLINE_WORKTREE/.local/share/docs/stacks/wayland"
	printf 'x\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/display.md"
	printf 'w\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/wayland/ghostty.md"
	publish master 'master stacks' \
		.local/share/docs/stacks/x11/display.md \
		.local/share/docs/stacks/wayland/ghostty.md
	pack --allow-stale-target
	[ "$status" -eq 2 ]
	[[ "$output" == *"拒绝：master 的 stacks/ 必须为空"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]
}

@test "TC-OFF19: only an opposite-stack markdown link is rejected" {
	local new=$HOME/new
	on_branch x11
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11"
	printf 'see stacks/x11 and stacks/wayland\n' > "$OFFLINE_WORKTREE/.local/share/docs/README.md"
	printf 'see stacks/wayland in a stack file\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/plain.md"
	publish x11 'plain names' .local/share/docs/README.md .local/share/docs/stacks/x11/plain.md
	pack --branch x11
	[ "$status" -eq 0 ]
	mkdir -p "$new"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	run_install "$new" x11
	[ "$status" -eq 0 ]
	run git --git-dir="$new/.cfg" grep -F -e 'stacks/wayland' HEAD -- .local/share/docs
	[ "$status" -eq 0 ]

	on_branch x11
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11"
	printf 'see [display](stacks/x11/display.md)\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/display.md"
	publish x11 'same stack link' .local/share/docs/stacks/x11/display.md
	rm -rf "$new" "$OFFLINE_OUTPUT"
	pack --branch x11
	[ "$status" -eq 0 ]
	mkdir -p "$new"
	tar -xzf "$OFFLINE_OUTPUT" -C "$new"
	run_install "$new" x11
	[ "$status" -eq 0 ]
	[ -f "$new/.local/share/docs/stacks/x11/display.md" ]

	on_branch x11
	printf 'see stacks/wayland\n```\n[bad](stacks/wayland/a.md)\n```\nsee `[bad](stacks/wayland/b.md)`\n' > \
		"$OFFLINE_WORKTREE/.local/share/docs/README.md"
	publish x11 'code is not a link' .local/share/docs/README.md
	rm -rf "$new" "$OFFLINE_OUTPUT"
	pack --branch x11
	[ "$status" -eq 0 ]

	on_branch x11
	printf 'see [ghostty](stacks/wayland/ghostty.md)\n' > "$OFFLINE_WORKTREE/.local/share/docs/README.md"
	publish x11 'public opposite link' .local/share/docs/README.md
	rm -f "$OFFLINE_OUTPUT"
	pack --branch x11
	[ "$status" -eq 2 ]
	[[ "$output" == *"文档链接越界：stacks/wayland 命中 1"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]

	on_branch x11
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11"
	printf 'see stacks/x11 and stacks/wayland\n' > "$OFFLINE_WORKTREE/.local/share/docs/README.md"
	printf '[ghostty][wl]\n[wl]: stacks/wayland/ghostty.md\n' > \
		"$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/display.md"
	publish x11 'ref link' .local/share/docs/README.md .local/share/docs/stacks/x11/display.md
	rm -f "$OFFLINE_OUTPUT"
	pack --branch x11
	[ "$status" -eq 2 ]
	[[ "$output" == *"文档链接越界：stacks/wayland 命中 2"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]

	on_branch x11
	cat > "$OFFLINE_WORKTREE/.local/share/docs/README.md" << 'EOF'
see <a href="../stacks/wayland/ghostty.md">x</a>
<a href = "../stacks/wayland/a.md">y</a>
<a href='stacks/wayland/b.md'>z</a>
EOF
	printf 'plain stack note\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/display.md"
	publish x11 'html link' .local/share/docs/README.md .local/share/docs/stacks/x11/display.md
	rm -f "$OFFLINE_OUTPUT"
	pack --branch x11
	[ "$status" -eq 2 ]
	[[ "$output" == *"文档链接越界：stacks/wayland 命中 3"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]

	on_branch wayland
	printf 'see [display](stacks/x11/display.md)\n' > "$OFFLINE_WORKTREE/.local/share/docs/README.md"
	publish wayland 'wayland public link' .local/share/docs/README.md
	rm -f "$OFFLINE_OUTPUT"
	pack --branch wayland
	[ "$status" -eq 2 ]
	[[ "$output" == *"文档链接越界：stacks/x11 命中 1"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]
}

@test "TC-OFF20: mapped blobs must match on the same line before a master delete" {
	on_branch x11
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11"
	printf 'same body\n' > "$OFFLINE_WORKTREE/.local/share/docs/display-management.md"
	printf 'same body\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/display-management.md"
	publish x11 'mapped copy' \
		.local/share/docs/display-management.md \
		.local/share/docs/stacks/x11/display-management.md
	assert_same_line_blobs "$DOTCFG_GIT_DIR" \
		.local/share/docs/display-management.md \
		.local/share/docs/stacks/x11/display-management.md
	printf 'different\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/display-management.md"
	publish x11 'mapped drift' .local/share/docs/stacks/x11/display-management.md
	run assert_same_line_blobs "$DOTCFG_GIT_DIR" \
		.local/share/docs/display-management.md \
		.local/share/docs/stacks/x11/display-management.md
	[ "$status" -ne 0 ]
	git --git-dir="$DOTCFG_GIT_DIR" cat-file -e HEAD:.local/share/docs/display-management.md
}

@test "TC-OFF21: packing refuses a non-empty opposite stack" {
	on_branch x11
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11" \
		"$OFFLINE_WORKTREE/.local/share/docs/stacks/wayland"
	printf 'own\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/display.md"
	printf 'other\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/wayland/poison.md"
	publish x11 'foreign stack' \
		.local/share/docs/stacks/x11/display.md \
		.local/share/docs/stacks/wayland/poison.md
	pack --branch x11
	[ "$status" -eq 2 ]
	[[ "$output" == *"拒绝：x11 含不允许的栈文档 .local/share/docs/stacks/wayland/poison.md"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]

	on_branch wayland
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/wayland" \
		"$OFFLINE_WORKTREE/.local/share/docs/stacks/x11"
	printf 'own\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/wayland/ghostty.md"
	printf 'other\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/x11/poison.md"
	publish wayland 'foreign stack' \
		.local/share/docs/stacks/wayland/ghostty.md \
		.local/share/docs/stacks/x11/poison.md
	rm -f "$OFFLINE_OUTPUT"
	pack --branch wayland
	[ "$status" -eq 2 ]
	[[ "$output" == *"拒绝：wayland 含不允许的栈文档 .local/share/docs/stacks/x11/poison.md"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]

	on_branch x11
	mkdir -p "$OFFLINE_WORKTREE/.local/share/docs/stacks/foo"
	printf 'other\n' > "$OFFLINE_WORKTREE/.local/share/docs/stacks/foo/note.md"
	publish x11 'unknown stack' .local/share/docs/stacks/foo/note.md
	rm -f "$OFFLINE_OUTPUT"
	pack --branch x11
	[ "$status" -eq 2 ]
	[[ "$output" == *"拒绝：x11 含不允许的栈文档 .local/share/docs/stacks/foo/note.md"* ]]
	[ ! -e "$OFFLINE_OUTPUT" ]
}
