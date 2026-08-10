#!/usr/bin/env bash
# commands/undeploy.sh - Undeploy current node's configuration, restore original files
# Usage: undeploy.sh [--force] [--dry-run]
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

cfg_parse_common_args "$@"

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"

cfg_nodes_init "$backup_root"

# ── Read current node ──────────────────────────────────────────────────

current_code=$(cfg_head_get) || {
	printf 'ERROR: no current node (HEAD not set)\n' >&2
	exit 1
}

node_type=$(cfg_node_get "$current_code" "type") || {
	printf 'ERROR: node %s not found in index\n' "$current_code" >&2
	exit 1
}

deploy_status=$(cfg_deploy_status_get)

if [ "$deploy_status" = "uninstalled" ] && [ "$CFG_FORCE" != "true" ]; then
	printf 'Node %s (%s) is already undeployed.\n' "$current_code" "$node_type"
	printf 'Use --force to retry.\n'
	exit 0
fi

# ── Fresh nodes ────────────────────────────────────────────────────────

if [ "$node_type" = "fresh" ]; then
	printf 'Node %s is fresh (root). Restoring original files...\n' "$current_code"

	if [ "$CFG_DRY_RUN" = "true" ]; then
		printf '[dry-run] No changes made.\n'
		exit 0
	fi

	read -r restored failed <<< "$(cfg_restore_node_backup "$current_code" "$backup_root")"
	cfg_deploy_status_set "uninstalled"

	printf '\n=== Undeploy Complete ===\n'
	printf 'Node: %s (fresh)\n' "$current_code"
	printf 'Files restored: %d\n' "$restored"
	printf 'Status: uninstalled\n'
	exit 0
fi

# ── Determine files to remove ─────────────────────────────────────────

printf 'Undeploying node %s (%s)...\n\n' "$current_code" "$node_type"

node_files_dir="$backup_root/nodes/$current_code/files"
files_to_remove=()

if [ -d "$node_files_dir" ]; then
	while IFS= read -r path; do
		[ -z "$path" ] && continue
		files_to_remove+=("$path")
	done < <(find "$node_files_dir" -type f -printf '%P\n' 2>/dev/null)
fi

if [ -f "$HOME/.cfg-checkout-state" ]; then
	while IFS=: read -r path _hash; do
		[ -z "$path" ] && continue
		local_found=false
		for existing in "${files_to_remove[@]+"${files_to_remove[@]}"}"; do
			if [ "$existing" = "$path" ]; then
				local_found=true
				break
			fi
		done
		if ! $local_found; then
			files_to_remove+=("$path")
		fi
	done < "$HOME/.cfg-checkout-state"
fi

# ── Pre-undeploy report ───────────────────────────────────────────────

printf 'Files to remove:  %d\n' "${#files_to_remove[@]}"

has_backup=false
if [ -d "$backup_root/nodes/$current_code/backup" ]; then
	backup_count=$(find "$backup_root/nodes/$current_code/backup" -type f 2>/dev/null | wc -l)
	printf 'Files to restore: %d\n' "$backup_count"
	[ "$backup_count" -gt 0 ] && has_backup=true
fi

if [ "$CFG_DRY_RUN" = "true" ]; then
	printf '\n[dry-run] No changes made.\n'
	exit 0
fi

# ── Remove deployed files ─────────────────────────────────────────────

removed=0
for path in "${files_to_remove[@]+"${files_to_remove[@]}"}"; do
	if cfg_is_installation_path "$path"; then
		continue
	fi
	target="$HOME/$path"
	if [ -e "$target" ] || [ -L "$target" ]; then
		rm -f -- "$target"
		((removed++)) || true
	fi
done

rm -f "$HOME/.cfg-checkout-state" 2>/dev/null || true

# ── Restore from backup ───────────────────────────────────────────────

restored=0
failed=0
if $has_backup; then
	read -r restored failed <<< "$(cfg_restore_node_backup "$current_code" "$backup_root")"
fi

# ── Update deploy status ──────────────────────────────────────────────

cfg_deploy_status_set "uninstalled"

# ── Summary ───────────────────────────────────────────────────────────

printf '\n=== Undeploy Complete ===\n'
printf 'Node: %s (%s)\n' "$current_code" "$node_type"
printf 'Files removed: %d\n' "$removed"
printf 'Files restored from backup: %d\n' "$restored"
printf 'Status: uninstalled\n'
