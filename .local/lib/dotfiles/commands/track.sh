#!/usr/bin/env bash
# commands/track.sh - Add a file to the fresh node backup
# Usage: track.sh <path> [--dry-run] [--force] [--no-add]
# shellcheck disable=SC2034  # FORCE is retained for the documented interface.
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

DRY_RUN=false
FORCE=false
NO_ADD=false
target=""

for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=true ;;
		--force) FORCE=true ;;
		--no-add) NO_ADD=true ;;
		-*) printf 'Error: unknown option: %s\n' "$arg" >&2; exit 1 ;;
		*) target="$arg" ;;
	esac
done

if [ -z "$target" ]; then
	printf 'Usage: dotcfg track <path> [--dry-run] [--force] [--no-add]\n' >&2
	exit 1
fi
target="${target#./}"

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
cfg_nodes_init "$backup_root"

source_path="$HOME/$target"
if [ ! -f "$source_path" ] && [ ! -L "$source_path" ]; then
	printf 'Error: File not found: %s\n' "$target" >&2
	exit 1
fi

root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
if [ -z "$root_code" ]; then
	printf 'Error: fresh root node not found. Run "dotcfg doctor" to check the system.\n' >&2
	exit 1
fi

fresh_manifest_read "$root_code" || true
if fresh_manifest_has "$target"; then
	printf 'Error: File is already in fresh node backup: %s\n' "$target" >&2
	printf "  Use 'dotcfg fresh-status' to see all tracked files.\n" >&2
	printf "  Use 'dotcfg fresh-update' to refresh all backups.\n" >&2
	exit 1
fi

repo_tracked=false
if [ -d "$HOME/.cfg" ] && git --git-dir="$HOME/.cfg/" --work-tree="$HOME" ls-tree -r --name-only HEAD 2>/dev/null | grep -qx "$target"; then
	repo_tracked=true
fi

if $repo_tracked; then
	printf 'Warning: File is already tracked in .cfg repository.\n' >&2
	printf "  To track it in fresh, use 'dotcfg fresh-update' instead.\n" >&2
	printf "  Or 'dotcfg untrack' to remove from fresh.\n" >&2
fi

if fresh_exclude_is_excluded "$target"; then
	reason=$(fresh_exclude_reason "$target") || reason="unknown"
	printf 'Warning: Path matches an exclusion rule (%s).\n' "$reason" >&2
	printf 'Tracking it anyway as requested.\n' >&2
fi

if $DRY_RUN; then
	printf '[dry-run] Would back up %s to nodes/%s/backup/%s\n' "$target" "$root_code" "$target"
	printf '[dry-run] Would add manifest entry (status: tracked_by_user)\n'
	exit 0
fi

printf 'Tracking file: %s\n' "$target"
if ! fresh_copy_to_backup "$target" "tracked_by_user"; then
	printf 'Error: failed to back up %s\n' "$target" >&2
	exit 1
fi
printf '  -> Current file backed up to fresh node: nodes/%s/backup/%s\n' "$root_code" "$target"
printf '  -> Added to fresh manifest.txt (status: tracked_by_user)\n'
printf '  -> File is now protected by fresh node\n'

printf '\nNext steps:\n'
printf '  1. If needed, modify %s\n' "$target"
printf '  2. Add to .cfg repository:\n'
printf '     git --git-dir=~/.cfg --work-tree=$HOME add %s\n' "$target"
printf '     git --git-dir=~/.cfg --work-tree=$HOME commit -m "Add %s"\n' "$target"
printf '\nTo verify: dotcfg fresh-status\n'

if ! $NO_ADD && [ -d "$HOME/.cfg" ]; then
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" add "$target" 2>/dev/null || true
fi
