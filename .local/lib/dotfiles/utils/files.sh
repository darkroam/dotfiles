#!/usr/bin/env bash
# utils/files.sh - File constants and analysis for dotfiles commands
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_FILES_LOADED:-}" ]; then
	return 0
fi
_CFG_FILES_LOADED=1

CFG_SERVER_FILES=(
	".config/shell/profile"
	".config/shell/aliasrc"
	".config/shell/zshrc"
	".config/shell/tmux.conf.local"
	".bashrc"
	".zshrc"
	".profile"
	".config/tmux/tmux.conf"
	".config/tmux/tmux.conf.local"
	".tmux.conf"
	".config/git/gitconfig"
	".config/git/ignore"
	".gitconfig"
	".gitignore"
	".config/lf/lfrc"
	".config/lf/scope"
	".config/lf/cleaner"
	".config/lf/icons"
	".config/lf/shortcutrc"
	".local/share/docs/README.md"
	".local/share/docs/user/desktop-guide-zh.md"
)

CFG_DESKTOP_INDICATORS=(
	".xinitrc"
	".xprofile"
	".config/x11"
)

CFG_DESKTOP_ONLY_SYMLINKS=(
	".xinitrc"
	".xprofile"
	".asoundrc"
	".gtkrc-2.0"
	".tmux.conf"
	".gitconfig"
	".gitignore"
)

CFG_DESKTOP_ONLY_DIRS=(
	".config/x11"
	".config/alsa"
	".config/mpd"
	".config/nsxiv"
	".config/zathura"
)

cfg_analyze_files() {
	local git_dir="$1"
	shift
	local file_list=("$@")

	CFG_TO_INSTALL=()
	CFG_TO_BACKUP=()
	CFG_TO_SKIP=()

	local path
	for path in "${file_list[@]}"; do
		local full_path="$HOME/$path"
		if [ ! -e "$full_path" ] && [ ! -L "$full_path" ]; then
			CFG_TO_INSTALL+=("$path")
		elif cfg_should_backup_file "$git_dir" "$path"; then
			CFG_TO_BACKUP+=("$path")
		else
			CFG_TO_SKIP+=("$path")
		fi
	done
}

cfg_analyze_all_tracked() {
	local git_dir="$1"

	local config_fn
	config_fn() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

	mapfile -t tracked_paths < <(config_fn ls-tree -r --name-only HEAD)
	cfg_analyze_files "$git_dir" "${tracked_paths[@]}"
}

cfg_analyze_server_files() {
	local git_dir="$1"

	local config_fn
	config_fn() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

	local server_tracked=()
	local path
	for path in "${CFG_SERVER_FILES[@]}"; do
		if config_fn ls-tree -r --name-only HEAD 2>/dev/null | grep -qx "$path"; then
			server_tracked+=("$path")
		fi
	done
	cfg_analyze_files "$git_dir" "${server_tracked[@]}"
}
