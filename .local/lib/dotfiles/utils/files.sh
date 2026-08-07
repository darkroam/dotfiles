#!/usr/bin/env bash
# utils/files.sh - File analysis for dotfiles commands
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_FILES_LOADED:-}" ]; then
	return 0
fi
_CFG_FILES_LOADED=1

cfg_analyze_files() {
	local git_dir="$1"
	shift
	local file_list=("$@")

	CFG_TO_INSTALL=()
	CFG_TO_BACKUP=()
	CFG_TO_SKIP=()

	local path
	for path in "${file_list[@]}"; do
		if cfg_exclude_match "$path"; then
			CFG_TO_SKIP+=("$path")
			continue
		fi
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

cfg_get_files_for_state() {
	local git_dir="$1" state="$2"

	cfg_categories_load

	local category_files
	category_files=$(cfg_category_get_files "$state")

	local config_fn
	config_fn() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

	local tracked
	tracked=$(config_fn ls-tree -r --name-only HEAD 2>/dev/null)

	local matched=()
	while IFS= read -r tpath; do
		[ -z "$tpath" ] && continue
		while IFS= read -r cpath; do
			[ -z "$cpath" ] && continue
			if [ "$tpath" = "$cpath" ] || [[ "$tpath" == "$cpath"/* ]]; then
				matched+=("$tpath")
				break
			fi
		done <<< "$category_files"
	done <<< "$tracked"

	cfg_analyze_files "$git_dir" "${matched[@]}"
}
