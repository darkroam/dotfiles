#!/usr/bin/env bash
# commands/untrack.sh - Remove a file from the fresh node backup
# Usage: untrack.sh <path> [--dry-run] [--force]
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

DRY_RUN=false
FORCE=false
target=""

for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=true ;;
		--force) FORCE=true ;;
		-*) printf 'Error: unknown option: %s\n' "$arg" >&2; exit 1 ;;
		*) target="$arg" ;;
	esac
done

if [ -z "$target" ]; then
	printf 'Error: path is required.\n' >&2
	exit 1
fi
target="${target#./}"

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
cfg_nodes_init "$backup_root"

root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
if [ -z "$root_code" ]; then
	printf 'Error: fresh root node not found. Run "dotcfg doctor" to check the system.\n' >&2
	exit 1
fi

fresh_manifest_read "$root_code" || true
if ! fresh_manifest_has "$target"; then
	printf 'Error: File is not in fresh node backup: %s\n' "$target" >&2
	printf "  Use 'dotcfg fresh-status' to see all tracked files.\n" >&2
	exit 1
fi

repo_tracked=false
if [ -d "$HOME/.cfg" ] && git --git-dir="$HOME/.cfg/" --work-tree="$HOME" ls-tree -r --name-only HEAD 2>/dev/null | grep -qx "$target"; then
	repo_tracked=true
fi

if $DRY_RUN; then
	printf '[dry-run] Would remove nodes/%s/backup/%s\n' "$root_code" "$target"
	printf '[dry-run] Would remove manifest entry\n'
	exit 0
fi

if ! $FORCE; then
	printf 'Remove file from fresh node backup?\n'
	printf '  nodes/%s/backup/%s\n' "$root_code" "$target"
	printf '  This file will no longer be restored on uninstall.\n'
	printf 'Continue? (y/N): '
	read -r answer || answer=""
	case "$answer" in
		y|Y|yes|YES) ;;
		*) printf 'Cancelled.\n'; exit 0 ;;
	esac
fi

printf 'Untracking file: %s\n' "$target"
if ! fresh_remove_from_backup "$target"; then
	printf 'Error: failed to remove %s from fresh backup\n' "$target" >&2
	exit 1
fi
printf '  -> Removed from fresh node backup: nodes/%s/backup/%s\n' "$root_code" "$target"
printf '  -> Removed from fresh manifest.txt\n'
printf '  -> This file will no longer be restored on uninstall\n'

if $repo_tracked; then
	printf '\nWarning: File still exists in .cfg repository.\n' >&2
	printf '  To remove from repository:\n'
	printf '    git --git-dir=~/.cfg --work-tree=$HOME rm %s\n' "$target"
	printf '    git --git-dir=~/.cfg --work-tree=$HOME commit -m "Remove %s"\n' "$target"
fi
