#!/usr/bin/env bash
# utils/rollback.sh - Rollback from backup for dotfiles commands
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_ROLLBACK_LOADED:-}" ]; then
	return 0
fi
_CFG_ROLLBACK_LOADED=1

# cfg_should_rollback <failed_count> <total_count>
# Returns 0 if rollback should be triggered, 1 otherwise
# Trigger conditions: failed > 5 OR failure_rate > 10%
cfg_should_rollback() {
	local failed="$1"
	local total="$2"

	if (( failed == 0 || total == 0 )); then
		return 1
	fi

	# Condition 1: More than 5 files failed
	if (( failed > 5 )); then
		return 0
	fi

	# Condition 2: Failure rate > 10%
	# Use integer arithmetic: failed * 10 > total means rate > 10%
	if (( failed * 10 > total )); then
		return 0
	fi

	return 1
}

# cfg_print_rollback_reason <failed_count> <total_count>
# Prints why rollback is being triggered
cfg_print_rollback_reason() {
	local failed="$1"
	local total="$2"
	local rate=$(( failed * 100 / total ))

	printf '\nROLLBACK TRIGGERED: %d/%d files failed (%d%%)\n' "$failed" "$total" "$rate" >&2
	if (( failed > 5 )); then
		printf '  Reason: More than 5 files failed\n' >&2
	fi
	if (( failed * 10 > total )); then
		printf '  Reason: Failure rate exceeds 10%%\n' >&2
	fi
}

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
