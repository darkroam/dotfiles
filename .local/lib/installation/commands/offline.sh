#!/usr/bin/env bash
# Pack origin/master. The installer checks out dotcfg only and does not call
# bootstrap_finish_install, because that runs fresh_create_root_backup.

set -euo pipefail

offline_names=(st dmenu dwm dwmblocks)
offline_stage=

offline_die() {
	printf '%s\n' "$1" >&2
	exit "${2:-1}"
}

offline_cleanup() {
	[ -z "${offline_stage:-}" ] && return 0
	rm -rf "$offline_stage"
	offline_stage=
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
	printf '%s\n' "${OFFLINE_OUTPUT:-$HOME/src/dotcfg-offline.tar.gz}"
}

offline_tar_members_ok() {
	local tar=$1 with=${2:-0} got want
	got=$(tar -tzf "$tar" | LC_ALL=C sort)
	if [ "$with" -eq 1 ]; then
		want=$(printf '%s\n' MANIFEST dotcfg-offline-install dotfiles.bundle \
			src/st.bundle src/dmenu.bundle src/dwm.bundle src/dwmblocks.bundle | LC_ALL=C sort)
	else
		want=$(printf '%s\n' MANIFEST dotcfg-offline-install dotfiles.bundle | LC_ALL=C sort)
	fi
	[ "$got" = "$want" ]
}

offline_warn_ahead() {
	local label=$1 count
	shift
	count=$("$@" rev-list --count origin/master..HEAD 2>/dev/null || printf '0')
	[ "${count:-0}" -eq 0 ] || printf '警告：%s 领先 origin/master %s 笔，包取 origin/master\n' "$label" "$count" >&2
}

offline_warn_untracked() {
	local label=$1 untracked
	shift
	untracked=$("$@" status --porcelain --untracked-files=normal 2>/dev/null | awk '$1 == "??" { print }')
	[ -z "$untracked" ] || printf '警告：%s 有未跟踪文件，不进入包\n' "$label" >&2
}

offline_require_origin() {
	local label=$1
	shift
	"$@" rev-parse --verify origin/master >/dev/null 2>&1 ||
		offline_die "拒绝：${label} 无法解析 origin/master" 2
}

offline_warn_dirt() {
	local label=$1 tracked
	shift
	tracked=$("$@" status --porcelain --untracked-files=no)
	if [ -n "$tracked" ]; then
		printf '警告：%s 有未提交改动，不进入包\n' "$label" >&2
	fi
}

offline_sensitive() {
	local repo=$1 commit=$2 sha path typ hit=0
	while read -r sha path; do
		[ -n "${path:-}" ] || continue
		case "$path" in
			*id_rsa*|*id_ed25519*|*/.ssh/*|.ssh/*|*/secret/*|secret/*|*/secrets/*|*subscriptions.list*)
				printf '敏感对象已拒绝：%s\n' "$path" >&2
				hit=1
				continue
				;;
		esac
		typ=$(git -C "$repo" cat-file -t "$sha" 2>/dev/null || true)
		[ "$typ" = blob ] || continue
		# Historical offline.bats only: fixture PEM header plus fake marker
		# not-a-real-key-body-xyz. Not key material. Exact blob SHA, not a path.
		case $sha in
		b5cff72a0acf8274a05680a6832486e5dd9de939|\
		f4facf1406b833c92ff1dd7faabb18d55c2f860f|\
		a116f41508aa7a424850964b82c0dbacfc8c47ca)
			continue
			;;
		esac
		if git -C "$repo" cat-file blob "$sha" | awk '
			/-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----/ { found = 1 }
			/ghp_[A-Za-z0-9]{20,}/ { found = 1 }
			/github_pat_[A-Za-z0-9_]{20,}/ { found = 1 }
			/AKIA[0-9A-Z]{16}/ { found = 1 }
			END { exit found ? 0 : 1 }
		'; then
			printf '敏感对象已拒绝：%s\n' "$path" >&2
			hit=1
		fi
	done < <(git -C "$repo" rev-list --objects "$commit")
	[ "$hit" -eq 0 ] || exit 2
}

# A shared clone does not carry the source's origin/master ref.
offline_bundle_at() {
	local repo=$1 dest=$2 commit scratch rc
	commit=$(git -C "$repo" rev-parse --verify origin/master) || return 1
	scratch=$(mktemp -d)
	rc=0
	git clone -q --shared --bare "$repo" "$scratch/repo" &&
		git --git-dir="$scratch/repo" update-ref refs/heads/master "$commit" &&
		git --git-dir="$scratch/repo" symbolic-ref HEAD refs/heads/master &&
		git --git-dir="$scratch/repo" bundle create "$dest" master &&
		git --git-dir="$scratch/repo" bundle verify "$dest" >/dev/null || rc=1
	rm -rf "$scratch"
	return "$rc"
}

offline_sha256() {
	local sum
	sum=$(sha256sum -- "$1") || return 1
	printf '%s\n' "${sum%% *}"
}

offline_write_installer() {
	local dest=$1
	cat > "$dest" << 'INSTALLER'
#!/bin/sh
# Offline restore. Does not run dotcfg switch or bootstrap_finish_install.

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
bundle=$here/dotfiles.bundle
manifest=$here/MANIFEST
home=${OFFLINE_HOME:-$HOME}
cfg=${DOTCFG_GIT_DIR:-$home/.cfg}
origin=${OFFLINE_ORIGIN:-git@github.com:darkroam/dotfiles.git}

[ -f "$bundle" ] && [ -f "$manifest" ] || {
	printf '缺少 bundle 或 MANIFEST\n' >&2
	exit 1
}

check=$here/.bundle.sha256
awk '$1 ~ /\.bundle$/ { printf "%s  %s\n", $2, $1 }' "$manifest" > "$check"
if [ ! -s "$check" ] || ! (cd "$here" && sha256sum -c --status "$check"); then
	rm -f "$check"
	printf 'MANIFEST 校验失败\n' >&2
	exit 1
fi
rm -f "$check"

if [ ! -e "$cfg" ]; then
	git clone -q --bare --config remote.origin.fetch='+refs/heads/*:refs/remotes/origin/*' "$bundle" "$cfg"
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
case "$current_origin" in
	""|"$bundle")
		if [ -n "$current_origin" ]; then
			git --git-dir="$cfg" remote set-url origin "$origin"
		else
			git --git-dir="$cfg" remote add origin "$origin"
		fi
		;;
esac

git --git-dir="$cfg" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
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

src_base=${origin%/}
src_base=${src_base%.git}
case $src_base in
	*/dotfiles) src_base=${src_base%/dotfiles} ;;
	*)
		printf '无法从 OFFLINE_ORIGIN 推导源码地址：%s\n' "$origin" >&2
		exit 1
		;;
esac

for name in st dmenu dwm dwmblocks; do
	src_bundle=$here/src/$name.bundle
	[ -f "$src_bundle" ] || continue
	src_url=$src_base/$name.git
	dest=$home/src/$name
	if [ -e "$dest" ]; then
		if git -C "$dest" rev-parse --git-dir >/dev/null 2>&1; then
			current_src=$(git -C "$dest" config --get remote.origin.url || true)
			case $current_src in
				"$src_bundle"|*"/src/$name.bundle")
					git -C "$dest" remote set-url origin "$src_url"
					;;
			esac
		fi
		printf '已有源码，保留：%s\n' "$name"
		continue
	fi
	mkdir -p "$home/src"
	git clone -q "$src_bundle" "$dest" || {
		printf '源码 clone 失败：%s\n' "$name" >&2
		exit 1
	}
	git -C "$dest" remote set-url origin "$src_url"
done

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
	local with=$1 cfg work src out name dir commit
	cfg=$(offline_cfg)
	work=$(offline_work)
	src=$(offline_src)
	out=$(offline_output)
	if [ -e "$out" ]; then
		offline_die "已存在，拒绝覆盖：$out" 2
	fi
	if [ ! -d "$cfg" ] || ! git --git-dir="$cfg" rev-parse --git-dir >/dev/null 2>&1; then
		offline_die "拒绝：没有 $cfg" 2
	fi
	offline_require_origin dotfiles git --git-dir="$cfg"
	offline_warn_dirt dotfiles git --git-dir="$cfg" --work-tree="$work"
	offline_warn_ahead dotfiles git --git-dir="$cfg" --work-tree="$work"
	offline_warn_untracked dotfiles git --git-dir="$cfg" --work-tree="$work"
	if [ "$with" -eq 1 ]; then
		for name in "${offline_names[@]}"; do
			dir=$src/$name
			if [ ! -d "$dir" ]; then
				offline_die "拒绝：缺少源码仓 $name" 2
			fi
			if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
				offline_die "拒绝：${name} 不是 git 仓库" 2
			fi
			offline_require_origin "$name" git -C "$dir"
			offline_warn_dirt "$name" git -C "$dir"
			offline_warn_ahead "$name" git -C "$dir"
			offline_warn_untracked "$name" git -C "$dir"
		done
	fi
	commit=$(git --git-dir="$cfg" rev-parse --verify origin/master)
	offline_sensitive "$cfg" "$commit"
	if [ "$with" -eq 1 ]; then
		for name in "${offline_names[@]}"; do
			commit=$(git -C "$src/$name" rev-parse --verify origin/master)
			offline_sensitive "$src/$name" "$commit"
		done
	fi

	offline_stage=$(mktemp -d)
	trap offline_cleanup EXIT
	offline_bundle_at "$cfg" "$offline_stage/dotfiles.bundle" || offline_die "bundle 失败：dotfiles" 1
	if [ "$with" -eq 1 ]; then
		mkdir -p "$offline_stage/src"
		for name in "${offline_names[@]}"; do
			offline_bundle_at "$src/$name" "$offline_stage/src/$name.bundle" ||
				offline_die "bundle 失败：$name" 1
		done
	fi
	{
		printf 'time %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		printf 'dotfiles %s\n' "$(git --git-dir="$cfg" rev-parse --verify origin/master)"
		printf 'dotfiles.bundle %s\n' "$(offline_sha256 "$offline_stage/dotfiles.bundle")"
		if [ "$with" -eq 1 ]; then
			for name in "${offline_names[@]}"; do
				printf '%s %s\n' "$name" "$(git -C "$src/$name" rev-parse --verify origin/master)"
				printf 'src/%s.bundle %s\n' "$name" "$(offline_sha256 "$offline_stage/src/$name.bundle")"
			done
		fi
	} > "$offline_stage/MANIFEST"
	offline_write_installer "$offline_stage/dotcfg-offline-install"
	if [ "$with" -eq 1 ]; then
		tar -C "$offline_stage" -czf "$offline_stage/pack.tgz" \
			dotcfg-offline-install dotfiles.bundle MANIFEST \
			src/st.bundle src/dmenu.bundle src/dwm.bundle src/dwmblocks.bundle
	else
		tar -C "$offline_stage" -czf "$offline_stage/pack.tgz" \
			dotcfg-offline-install dotfiles.bundle MANIFEST
	fi
	offline_tar_members_ok "$offline_stage/pack.tgz" "$with" || offline_die "tar 成员非法" 1
	mkdir -p "$(dirname -- "$out")"
	if [ -e "$out" ]; then
		offline_die "已存在，拒绝覆盖：$out" 2
	fi
	mv -n "$offline_stage/pack.tgz" "$out"
	offline_cleanup
	trap - EXIT
	printf '已打包：%s\n' "$out"
}

if [ "${OFFLINE_LIB_ONLY:-0}" != 1 ]; then
	if [ "$#" -eq 1 ] && [ "$1" = "--with-suckless" ]; then
		offline_pack 1
	elif [ "$#" -ne 0 ]; then
		printf '用法：dotcfg-offline [--with-suckless]\n' >&2
		exit 2
	else
		offline_pack 0
	fi
fi
