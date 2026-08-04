#!/usr/bin/env bash

# uninstall.sh - Remove dotfiles repository and restore backed up configs
# Usage: uninstall.sh [--dry-run]

set -euo pipefail

# Parse arguments
DRY_RUN=false
for arg in "$@"; do
	case $arg in
		--dry-run) DRY_RUN=true ;;
	esac
done

git_dir=$HOME/.cfg
backup_pattern="$HOME/.config-backup-*"
state_file="$HOME/.cfg-checkout-state"

# Source shared validation library
DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/share/dotfiles-lib}"
if [ -f "$DOTFILES_LIB_DIR/cfg-validate.sh" ]; then
	. "$DOTFILES_LIB_DIR/cfg-validate.sh"
	cfg_validate "$git_dir"
	case "$CFG_STATE" in
		valid)
			printf 'Verified: %s is the dotfiles repository.\n' "$git_dir"
			;;
		not_git)
			printf 'WARNING: %s exists but is not a valid git repository.\n' "$git_dir"
			;;
		foreign_repo)
			printf 'WARNING: %s is a git repository but not the dotfiles repository.\n' "$git_dir"
			;;
		missing)
			# Will be caught below
			;;
	esac
fi

printf '=== Dotfiles Uninstallation ===\n\n'
printf 'This will:\n'
printf '  1. Remove all files checked out from the repository\n'
printf '  2. Restore backed up configs from the latest backup\n'
printf '  3. Prompt for manual repository removal\n'

# Check if repository exists
if [ ! -d "$git_dir" ] && [ ! -L "$git_dir" ]; then
	printf '\nRepository not found at %s. Nothing to uninstall.\n' "$git_dir" >&2
	exit 1
fi

# Get list of files to remove (from checkout state or git ls-tree)
files_to_remove=()
if [ -f "$state_file" ]; then
	while IFS=: read -r path _hash; do
		files_to_remove+=("$path")
	done < "$state_file"
	printf '\nFound %d tracked files in checkout state.\n' "${#files_to_remove[@]}"
elif [ -d "$git_dir" ]; then
	mapfile -t files_to_remove < <(git --git-dir="$git_dir/" --work-tree="$HOME" ls-tree -r --name-only HEAD 2>/dev/null || true)
	printf '\nFound %d tracked files in repository.\n' "${#files_to_remove[@]}"
else
	printf '\nNo checkout state or repository found. Nothing to remove.\n'
fi

# Check for backup directories
mapfile -t backup_dirs < <(compgen -G "$backup_pattern" 2>/dev/null || true)
if ((${#backup_dirs[@]} > 0)); then
	printf '\nFound %d backup director(y/ies):\n' "${#backup_dirs[@]}"
	for bd in "${backup_dirs[@]}"; do
		printf '  - %s\n' "$bd"
	done
	# Select the latest backup (last in sorted order)
	latest_backup="${backup_dirs[-1]}"
	printf '\nWill restore from latest backup: %s\n' "$latest_backup"
else
	printf '\nNo backup directories found.\n'
	latest_backup=""
fi

if [ "$DRY_RUN" = true ]; then
	printf '\n=== DRY RUN MODE - No changes will be made ===\n'
	printf '\nWould remove %d files:\n' "${#files_to_remove[@]}"
	for path in "${files_to_remove[@]}"; do
		if [ -e "$HOME/$path" ] || [ -L "$HOME/$path" ]; then
			printf '  - %s\n' "$path"
		fi
	done
	if [ -n "$latest_backup" ] && [ -f "$latest_backup/MANIFEST.txt" ]; then
		printf '\nWould restore from MANIFEST:\n'
		grep -v '^#' "$latest_backup/MANIFEST.txt" | grep -v '^$' | head -10
		printf '  ... (see full MANIFEST for complete list)\n'
	fi
	printf '\nNote: Repository at %s will NOT be automatically removed.\n' "$git_dir"
	exit 0
fi

# Confirm removal
printf '\nProceed with uninstallation? [y/N] '
read -r confirm
if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
	printf 'Aborted.\n'
	exit 0
fi

# Step 1: Remove all tracked files
printf '\n=== Step 1: Removing repository files ===\n'
removed=0
for path in "${files_to_remove[@]}"; do
	target="$HOME/$path"
	if [ -e "$target" ] || [ -L "$target" ]; then
		rm -f -- "$target"
		((removed++)) || true
	fi
done
printf 'Removed %d files.\n' "$removed"

# Remove checkout state file (installer metadata)
if [ -f "$state_file" ]; then
	rm -f -- "$state_file"
	printf 'Removed checkout state file.\n'
fi

# Step 2: Restore from latest backup
if [ -n "$latest_backup" ] && [ -d "$latest_backup" ]; then
	printf '\n=== Step 2: Restoring from backup ===\n'
	manifest="$latest_backup/MANIFEST.txt"

	if [ -f "$manifest" ]; then
		printf 'Using manifest for restoration...\n'
		restored=0
		failed=0

		while IFS= read -r line; do
			# Skip comments and empty lines
			[[ "$line" =~ ^#.*$ ]] && continue
			[[ -z "$line" ]] && continue

			# Parse "source -> backup (status)" format
			if [[ "$line" =~ ^(.+)\ -\>\ (.+)\ \((modified|untracked)\)$ ]]; then
				original="${BASH_REMATCH[1]}"
				backup_file="${BASH_REMATCH[2]}"

				if [ -e "$backup_file" ]; then
					mkdir -p "$(dirname "$original")"
					if mv -- "$backup_file" "$original"; then
						printf 'Restored: %s\n' "$(basename "$original")"
						((restored++)) || true
					else
						printf 'Failed: %s\n' "$(basename "$original")" >&2
						((failed++)) || true
					fi
				fi
			fi
		done < "$manifest"

		printf '\nRestoration summary:\n'
		printf '  Restored: %d\n' "$restored"
		printf '  Failed: %d\n' "$failed"
	else
		# Fallback: restore all files without manifest
		printf 'No manifest found. Restoring all files...\n'
		restored=0
		while IFS= read -r -d '' backup_file; do
			relative_path="${backup_file#$latest_backup/}"
			[[ "$relative_path" == "MANIFEST.txt" ]] && continue

			target="$HOME/$relative_path"
			mkdir -p "$(dirname "$target")"
			if mv -- "$backup_file" "$target"; then
				printf 'Restored: %s\n' "$relative_path"
				((restored++)) || true
			fi
		done < <(find "$latest_backup" -type f -print0)
		printf 'Restored %d files.\n' "$restored"
	fi
fi

# Prompt for manual repository removal
printf '\n=== Manual Repository Removal ===\n'
printf 'The bare repository is located at: %s\n' "$git_dir"
printf '\nTo complete the uninstallation, you must manually remove it:\n'
printf '  rm -rf %s\n' "$git_dir"
printf '\nIMPORTANT: Verify that all your configurations are working correctly before removing the repository.\n'

printf '\n=== Uninstall Complete ===\n'
printf 'Files removed: %d\n' "$removed"
if ((${#backup_dirs[@]} > 0)); then
	printf '\nBackup directories preserved:\n'
	for bd in "${backup_dirs[@]}"; do
		printf '  - %s\n' "$bd"
	done
fi
printf '\nRemember to manually remove the repository when ready:\n'
printf '  rm -rf %s\n' "$git_dir"
