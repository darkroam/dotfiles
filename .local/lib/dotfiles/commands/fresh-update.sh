#!/usr/bin/env bash
# commands/fresh-update.sh - Rebuild the fresh node backup from current system state
# Usage: fresh-update.sh [--dry-run] [--force] [--no-backup]
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

DRY_RUN=false
FORCE=false
NO_BACKUP=false
for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=true ;;
		--force) FORCE=true ;;
		--no-backup) NO_BACKUP=true ;;
		*) printf 'Error: unknown option: %s\n' "$arg" >&2; exit 1 ;;
	esac
done

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
cfg_nodes_init "$backup_root"

root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
if [ -z "$root_code" ]; then
	printf 'Error: fresh root node not found. Run "dotcfg doctor" to check the system.\n' >&2
	exit 1
fi

files=()
while IFS= read -r f; do
	[ -n "$f" ] && files+=("$f")
done < <(fresh_scan_home)

if $DRY_RUN; then
	printf '[dry-run] Would rebuild fresh node backup with %d files:\n' "${#files[@]}"
	for f in "${files[@]}"; do
		printf '  %s\n' "$f"
	done
	if ! $NO_BACKUP; then
		printf '[dry-run] Old backup would be saved to nodes/%s.bak/\n' "$root_code"
	fi
	exit 0
fi

printf 'This will OVERWRITE the fresh node backup (%d files scanned).\n' "${#files[@]}"
printf 'The current "original state" definition will be replaced.\n'
if ! $FORCE; then
	printf 'Continue? (y/N): '
	read -r answer || answer=""
	case "$answer" in
		y|Y|yes|YES) ;;
		*) printf 'Cancelled.\n'; exit 0 ;;
	esac
fi

node_dir="$CFG_NODES_DIR/$root_code"

if ! $NO_BACKUP; then
	bak_dir="$CFG_NODES_DIR/${root_code}.bak"
	rm -rf -- "$bak_dir"
	cp -a -- "$node_dir" "$bak_dir"
	printf 'Old fresh node saved to: %s\n' "$bak_dir"
fi

rm -rf -- "$node_dir/backup"
mkdir -p "$node_dir/backup"
chmod 700 "$node_dir/backup" 2>/dev/null || true

fresh_manifest_write_header "$root_code"

count=0
for f in "${files[@]}"; do
	if fresh_copy_to_backup "$f" "tracked_at_install" ""; then
		count=$((count + 1))
	fi
done

printf 'Fresh node backup rebuilt: %d files.\n' "$count"
if ! $NO_BACKUP; then
	printf 'Previous backup kept at nodes/%s.bak/ (remove manually when verified).\n' "$root_code"
fi
