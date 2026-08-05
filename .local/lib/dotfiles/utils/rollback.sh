#!/usr/bin/env bash
# utils/rollback.sh - Rollback from backup for dotfiles commands
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_ROLLBACK_LOADED:-}" ]; then
	return 0
fi
_CFG_ROLLBACK_LOADED=1

cfg_rollback_from_backup() {
	local backup_dir="$1"
	shift
	local files=("$@")

	if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
		return 0
	fi

	printf '\nRolling back: restoring files from backup...\n' >&2
	local path
	for path in "${files[@]}"; do
		local backup_path="$backup_dir/$path"
		local target_path="$HOME/$path"
		if [ -e "$backup_path" ]; then
			{ [ -e "$target_path" ] || [ -L "$target_path" ]; } && rm -f -- "$target_path"
			mkdir -p -- "$(dirname "$target_path")"
			mv -- "$backup_path" "$target_path" 2>/dev/null || \
				printf 'Warning: could not restore %s\n' "$path" >&2
		fi
	done
}
