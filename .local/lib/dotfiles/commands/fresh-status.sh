#!/usr/bin/env bash
# commands/fresh-status.sh - Show fresh node backup status
# Usage: fresh-status.sh
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
cfg_nodes_init "$backup_root"

root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
if [ -z "$root_code" ]; then
	printf 'Error: fresh root node not found. Run "dotcfg doctor" to check the system.\n' >&2
	exit 1
fi

created=$(cfg_node_get "$root_code" "timestamp" 2>/dev/null) || created="unknown"

if ! fresh_manifest_read "$root_code"; then
	printf 'Fresh node: %s\n' "$root_code"
	printf '  Created: %s\n' "$created"
	printf '  No manifest found.\n'
	exit 0
fi

count=$(fresh_backup_count)
total_bytes=$(fresh_backup_size)

at_install=0
by_user=0
i=0
for ((i = 0; i < ${#_FRESH_MANIFEST_STATUSES[@]}; i++)); do
	case "${_FRESH_MANIFEST_STATUSES[$i]}" in
		tracked_at_install) at_install=$((at_install + 1)) ;;
		tracked_by_user) by_user=$((by_user + 1)) ;;
	esac
done

printf '\nFresh node: %s\n' "$root_code"
printf '  Type: fresh (root node)\n'
printf '  Created: %s\n' "$created"
printf '  Backup count: %s files\n' "$count"
printf '  Backup size: %s\n' "$(fresh_format_size "$total_bytes")"

printf '\nTracked files (by type):\n'
printf '  - %d files from initial install (tracked_at_install)\n' "$at_install"
printf '  - %d files added by user (tracked_by_user)\n' "$by_user"

# Top 5 largest files
if [ "$count" -gt 0 ]; then
	printf '\nTop 5 largest files in backup:\n'
	rank=1
	while IFS=$'\t' read -r size path; do
		[ -z "$path" ] && continue
		[ "$rank" -gt 5 ] && break
		printf '  %d. %-40s (%s)\n' "$rank" "$path" "$(fresh_format_size "$size")"
		rank=$((rank + 1))
	done < <(
		for ((i = 0; i < ${#_FRESH_MANIFEST_PATHS[@]}; i++)); do
			printf '%s\t%s\n' "${_FRESH_MANIFEST_SIZES[$i]:-0}" "${_FRESH_MANIFEST_PATHS[$i]}"
		done | LC_ALL=C sort -t$'\t' -k1,1nr
	)
fi

# Most recent user additions (up to 5, by timestamp)
recent=()
for ((i = 0; i < ${#_FRESH_MANIFEST_PATHS[@]}; i++)); do
	[ "${_FRESH_MANIFEST_STATUSES[$i]}" = "tracked_by_user" ] || continue
	[ -n "${_FRESH_MANIFEST_TIMES[$i]:-}" ] || continue
	recent+=("$(printf '%s\t%s' "${_FRESH_MANIFEST_TIMES[$i]}" "${_FRESH_MANIFEST_PATHS[$i]}")")
done
if [ ${#recent[@]} -gt 0 ]; then
	printf '\nMost recent additions:\n'
	shown=0
	while IFS=$'\t' read -r ts path; do
		[ -z "$path" ] && continue
		[ "$shown" -ge 5 ] && break
		printf '  - %-40s (%s, tracked_by_user)\n' "$path" "$ts"
		shown=$((shown + 1))
	done < <(printf '%s\n' "${recent[@]}" | LC_ALL=C sort -r)
fi
printf '\n'
