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

cfg_get_tracked_files_for_state() {
	local git_dir="$1" state="$2"
	local version="${3:-}"

	state=$(cfg_category_canonical_name "$state")
	if [ -n "$version" ]; then
		cfg_categories_load "$version" || return 1
	else
		cfg_categories_load || return 1
	fi

	local category_files
	category_files=$(cfg_category_get_files "$state" "$git_dir") || return 1

	local config_fn
	config_fn() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

	local tracked
	tracked=$(config_fn ls-tree -r --name-only HEAD 2>/dev/null)

	local matched=()
	while IFS= read -r tpath; do
		[ -z "$tpath" ] && continue
		if cfg_is_installation_path "$tpath"; then
			matched+=("$tpath")
			continue
		fi
		while IFS= read -r cpath; do
			[ -z "$cpath" ] && continue
			if [ "$tpath" = "$cpath" ] || [[ "$tpath" == "$cpath"/* ]]; then
				matched+=("$tpath")
				break
			fi
		done <<< "$category_files"
	done <<< "$tracked"

	if [ ${#matched[@]} -gt 0 ]; then
		printf '%s\n' "${matched[@]}"
	fi
}

cfg_get_files_for_state() {
	local git_dir="$1" state="$2"
	local version="${3:-}"
	local matched=()

	mapfile -t matched < <(cfg_get_tracked_files_for_state "$git_dir" "$state" "$version")

	cfg_analyze_files "$git_dir" "${matched[@]}"
}

# cfg_record_checkout_state_for_category <git_dir> <category> [version] [state_file]
cfg_record_checkout_state_for_category() {
	local git_dir="$1" state="$2"
	local version="${3:-}"
	local state_file="${4:-$HOME/.cfg-checkout-state}"
	local paths=()

	mapfile -t paths < <(cfg_get_tracked_files_for_state "$git_dir" "$state" "$version")
	> "$state_file"
	local path hash
	for path in "${paths[@]}"; do
		[ -e "$HOME/$path" ] || [ -L "$HOME/$path" ] || continue
		hash=$(git --git-dir="$git_dir/" --work-tree="$HOME" show "HEAD:$path" 2>/dev/null | md5sum | cut -d' ' -f1)
		printf '%s:%s\n' "$path" "$hash" >> "$state_file"
	done
}

# cfg_get_files_to_remove <git_dir> <current> <target> [version]
# Prints tracked paths deployed by current but not by target, excluding the
# installation infrastructure that is invariant across categories.
cfg_get_files_to_remove() {
	local git_dir="$1" current="$2" target="$3"
	local version="${4:-}"
	local current_files target_files path

	current=$(cfg_category_canonical_name "$current")
	target=$(cfg_category_canonical_name "$target")
	current_files=$(cfg_get_tracked_files_for_state "$git_dir" "$current" "$version")
	target_files=$(cfg_get_tracked_files_for_state "$git_dir" "$target" "$version")

	while IFS= read -r path; do
		[ -n "$path" ] || continue
		cfg_is_installation_path "$path" && continue
		if ! printf '%s\n' "$target_files" | grep -qFx -- "$path"; then
			printf '%s\n' "$path"
		fi
	done <<< "$current_files"
}
