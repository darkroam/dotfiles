#!/usr/bin/env bash
# Pack ~/.cfg as a git bundle. The generated installer checks out dotcfg only.
# It does not call bootstrap_finish_install, because that runs fresh_create_root_backup
# and would copy the new machine's ~/.config.

set -euo pipefail

offline_names=(st dmenu dwm dwmblocks)

offline_die() {
	printf '%s\n' "$1" >&2
	exit "${2:-1}"
}

offline_cfg() {
	printf '%s\n' "${DOTCFG_GIT_DIR:-$HOME/.cfg}"
}

offline_work() {
	printf '%s\n' "${OFFLINE_WORKTREE:-$HOME}"
}

offline_src() {
	printf '%s\n' "${SUCKLESS_SRC:-$HOME/src}"
}

offline_output() {
	printf '%s\n' "${OFFLINE_OUTPUT:-$HOME/src/dotfiles-offline.tar.gz}"
}

offline_tar_members_ok() {
	local tar=$1 got want
	got=$(tar -tzf "$tar" | LC_ALL=C sort)
	want=$(printf '%s\n' MANIFEST dotfiles.bundle dotfiles-offline-install | LC_ALL=C sort)
	[ "$got" = "$want" ]
}

offline_ahead() {
	local label=$1
	shift
	local n
	if ! n=$("$@" rev-list --count origin/master..HEAD 2>/dev/null); then
		offline_die "拒绝：${label} 无法比较 origin/master" 2
	fi
	if [ "$n" != 0 ]; then
		offline_die "拒绝：${label} 领先 origin/master ${n} 个提交" 2
	fi
}

offline_dirt() {
	local label=$1
	shift
	local tracked untracked
	tracked=$("$@" status --porcelain --untracked-files=no)
	if [ -n "$tracked" ]; then
		offline_die "拒绝：${label} 有未提交改动" 2
	fi
	untracked=$("$@" status --porcelain --untracked-files=all || true)
	if printf '%s\n' "$untracked" | grep -q '^??'; then
		printf '警告：%s 有未跟踪文件，继续打包\n' "$label" >&2
	fi
}

offline_sensitive() {
	local cfg=$1 sha path typ hit=0
	while read -r sha path; do
		[ -n "${path:-}" ] || continue
		case "$path" in
			*id_rsa*|*id_ed25519*|*/.ssh/*|.ssh/*|*/secret/*|secret/*|*/secrets/*|*subscriptions.list*)
				printf '敏感对象已拒绝：%s\n' "$path" >&2
				hit=1
				continue
				;;
		esac
		typ=$(git --git-dir="$cfg" cat-file -t "$sha" 2>/dev/null || true)
		[ "$typ" = blob ] || continue
		if git --git-dir="$cfg" cat-file blob "$sha" | awk '
			/-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----/ { found = 1 }
			/ghp_[A-Za-z0-9]{20,}/ { found = 1 }
			/github_pat_[A-Za-z0-9_]{20,}/ { found = 1 }
			/AKIA[0-9A-Z]{16}/ { found = 1 }
			END { exit found ? 0 : 1 }
		'; then
			printf '敏感对象已拒绝：%s\n' "$path" >&2
			hit=1
		fi
	done < <(git --git-dir="$cfg" rev-list --objects HEAD master)
	[ "$hit" -eq 0 ] || exit 2
}

offline_write_installer() {
	local dest=$1
	cat > "$dest" << 'INSTALLER'
#!/bin/sh
# Offline restore. Does not run dotcfg switch, and does not back up ~/.config.

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
bundle=$here/dotfiles.bundle
manifest=$here/MANIFEST
home=${OFFLINE_HOME:-$HOME}
cfg=${DOTCFG_GIT_DIR:-$home/.cfg}
origin=git@github.com:darkroam/dotfiles.git

[ -f "$bundle" ] && [ -f "$manifest" ] || {
	printf '缺少 bundle 或 MANIFEST\n' >&2
	exit 1
}

check=$here/.bundle.sha256
awk '$1 == "bundle_sha256" { printf "%s  dotfiles.bundle\n", $2 }' "$manifest" > "$check"
if ! (cd "$here" && sha256sum -c "$check"); then
	rm -f "$check"
	printf 'MANIFEST 校验失败\n' >&2
	exit 1
fi
rm -f "$check"

if [ ! -e "$cfg" ]; then
	git clone --bare "$bundle" "$cfg"
elif ! git --git-dir="$cfg" rev-parse --git-dir >/dev/null 2>&1; then
	printf '.cfg 不是 git 仓：%s\n' "$cfg" >&2
	exit 1
fi

bare=$(git --git-dir="$cfg" rev-parse --is-bare-repository)
[ "$bare" = true ] || {
	printf '.cfg 不是 bare 仓：%s\n' "$cfg" >&2
	exit 1
}
git --git-dir="$cfg" rev-parse --verify HEAD >/dev/null

mismatch=$(find "$cfg" ! -uid "$(id -u)" -print -quit || true)
if [ -n "$mismatch" ]; then
	if [ ! -t 0 ] || [ ! -t 1 ]; then
		printf '需要终端才能修正 .cfg 所有权\n' >&2
		exit 1
	fi
	sudo -k chown -R "$(id -u):$(id -g)" "$cfg"
fi

current_bare=$(git --git-dir="$cfg" config --bool --get core.bare || true)
[ "$current_bare" = true ] || git --git-dir="$cfg" config core.bare true

current_origin=$(git --git-dir="$cfg" config --get remote.origin.url || true)
if [ "$current_origin" != "$origin" ]; then
	if [ -n "$current_origin" ]; then
		git --git-dir="$cfg" remote set-url origin "$origin"
	else
		git --git-dir="$cfg" remote add origin "$origin"
	fi
fi

show_untracked=$(git --git-dir="$cfg" config --get status.showUntrackedFiles || true)
[ "$show_untracked" = no ] || git --git-dir="$cfg" config status.showUntrackedFiles no

list=$here/.checkout-list
git --git-dir="$cfg" ls-tree -r --name-only HEAD > "$list"
wrote=0
while IFS= read -r path; do
	case $path in
		.local/bin/dotcfg|.local/lib/installation/cfg-validate.sh|.local/lib/installation/utils/*|.local/lib/installation/commands/*|.local/lib/installation/categories*.conf|.local/lib/installation/exclude.conf)
			dest=$home/$path
			if [ -e "$dest" ]; then
				continue
			fi
			mkdir -p "$(dirname -- "$dest")"
			git --git-dir="$cfg" show "HEAD:$path" > "$dest.tmp"
			mv -- "$dest.tmp" "$dest"
			case $path in
				.local/bin/dotcfg) chmod +x "$dest" ;;
			esac
			wrote=1
			;;
	esac
done < "$list"
rm -f "$list"
if [ ! -x "$home/.local/bin/dotcfg" ]; then
	printf 'HEAD 中没有可执行的 dotcfg\n' >&2
	exit 1
fi
if [ "$wrote" -eq 1 ]; then
	printf '已检出 dotcfg。未备份 ~/.config，也未执行 switch。\n'
else
	printf '已有 dotcfg，跳过检出。\n'
fi

if ! command -v timeout >/dev/null 2>&1; then
	printf '缺少命令：timeout\n' >&2
	exit 1
fi
if ! timeout 10 git --git-dir="$cfg" ls-remote --heads origin | grep -q 'refs/heads/master'; then
	printf '本地安装已完成，远端尚未就绪。\n请确认网络，以及到 %s 的 SSH。\n完成后重新运行本脚本。\n' "$origin" >&2
	exit 2
fi
git --git-dir="$cfg" fetch origin
git --git-dir="$cfg" rev-parse --verify refs/remotes/origin/master >/dev/null
exit 0
INSTALLER
	chmod 755 "$dest"
}

offline_pack() {
	local cfg work src out stage name dir bundle_sha head_sha repo_sha
	cfg=$(offline_cfg)
	work=$(offline_work)
	src=$(offline_src)
	out=$(offline_output)
	if [ -e "$out" ]; then
		offline_die "已存在，拒绝覆盖：$out" 2
	fi
	if [ ! -d "$cfg" ]; then
		offline_die "拒绝：没有 $cfg" 2
	fi
	offline_ahead dotfiles git --git-dir="$cfg"
	offline_dirt dotfiles git --git-dir="$cfg" --work-tree="$work"
	for name in "${offline_names[@]}"; do
		dir=$src/$name
		if [ ! -d "$dir" ]; then
			offline_die "拒绝：缺少源码仓 $name" 2
		fi
		offline_ahead "$name" git -C "$dir"
		offline_dirt "$name" git -C "$dir"
	done
	offline_sensitive "$cfg"

	stage=$(mktemp -d)
	trap 'rm -rf "$stage"' RETURN
	git --git-dir="$cfg" bundle create "$stage/dotfiles.bundle" HEAD master
	git --git-dir="$cfg" bundle verify "$stage/dotfiles.bundle" >/dev/null
	bundle_sha=$(sha256sum -- "$stage/dotfiles.bundle")
	bundle_sha=${bundle_sha%% *}
	head_sha=$(git --git-dir="$cfg" rev-parse HEAD)
	{
		printf 'bundle_sha256 %s\n' "$bundle_sha"
		printf 'dotfiles %s\n' "$head_sha"
		for name in "${offline_names[@]}"; do
			repo_sha=$(git -C "$src/$name" rev-parse HEAD)
			printf '%s %s\n' "$name" "$repo_sha"
		done
	} > "$stage/MANIFEST"
	offline_write_installer "$stage/dotfiles-offline-install"
	tar -C "$stage" -czf "$stage/pack.tgz" dotfiles-offline-install dotfiles.bundle MANIFEST
	offline_tar_members_ok "$stage/pack.tgz" || offline_die "tar 成员非法" 1
	mkdir -p "$(dirname -- "$out")"
	if [ -e "$out" ]; then
		offline_die "已存在，拒绝覆盖：$out" 2
	fi
	mv -n "$stage/pack.tgz" "$out"
	trap - RETURN
	rm -rf "$stage"
	printf '已打包：%s\n' "$out"
}

if [ "${OFFLINE_LIB_ONLY:-0}" != 1 ]; then
	if [ "$#" -ne 0 ]; then
		printf '用法：dotfiles-offline\n' >&2
		exit 2
	fi
	offline_pack
fi
