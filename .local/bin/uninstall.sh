#!/usr/bin/env bash

# uninstall.sh - Remove dotfiles repository and restore backed up configs
# Usage: uninstall.sh [--dry-run] [--latest] [--clean-backups]

set -euo pipefail

# Parse arguments
DRY_RUN=false
LATEST=false
CLEAN_BACKUPS=false
for arg in "$@"; do
	case $arg in
		--dry-run) DRY_RUN=true ;;
		--latest) LATEST=true ;;
		--clean-backups) CLEAN_BACKUPS=true ;;
	esac
done

git_dir=$HOME/.cfg
backup_root="$HOME/.config-backup"
state_file="$HOME/.cfg-checkout-state"

# Source shared validation library
DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
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
if [ "$LATEST" = true ]; then
	printf '  2. Restore backed up configs (latest version from backup chain)\n'
else
	printf '  2. Restore backed up configs (original version from backup chain)\n'
fi
printf '  3. Prompt for manual repository removal\n'

# Check if repository exists
if [ ! -d "$git_dir" ] && [ ! -L "$git_dir" ]; then
	printf '\nRepository not found at %s. Nothing to uninstall.\n' "$git_dir" >&2
	exit 1
fi

# Get list of managed files (from checkout state or git ls-tree)
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

# Scan backup chain and build file history index
# For each file, track which backup sessions contain it (in chronological order)
declare -A file_backup_sessions  # file -> newline-separated list of session dirs containing it

backup_session_count=0
if [ -d "$backup_root" ]; then
	while IFS= read -r session_dir; do
		[ -n "$session_dir" ] || continue
		((backup_session_count++)) || true
		manifest="$session_dir/MANIFEST.txt"
		if [ -f "$manifest" ]; then
			while IFS=$'\t' read -r rel_path md5 status; do
				# Skip comments and empty lines
				[[ "$rel_path" =~ ^#.*$ ]] && continue
				[[ -z "$rel_path" ]] && continue

				if [ -n "${file_backup_sessions[$rel_path]+x}" ]; then
					file_backup_sessions[$rel_path]+=$'\n'"$session_dir"
				else
					file_backup_sessions[$rel_path]="$session_dir"
				fi
			done < "$manifest"
		fi
	done < <(find "$backup_root" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -n | cut -f2-)
fi

printf '\nFound %d backup session(s) in %s.\n' "$backup_session_count" "$backup_root"

# Determine which files can be restored and from which session
declare -A file_restore_session  # file -> session dir to restore from
restorable_count=0
not_in_backup=()

for path in "${files_to_remove[@]}"; do
	if [ -n "${file_backup_sessions[$path]+x}" ]; then
		if [ "$LATEST" = true ]; then
			# Sessions are in chronological order; last = latest
			file_restore_session[$path]=$(printf '%s' "${file_backup_sessions[$path]}" | tail -1)
		else
			# Sessions are in chronological order; first = earliest
			file_restore_session[$path]=$(printf '%s' "${file_backup_sessions[$path]}" | head -1)
		fi
		((restorable_count++)) || true
	else
		not_in_backup+=("$path")
	fi
done

if ((restorable_count > 0)); then
	printf 'Files restorable from backup: %d\n' "$restorable_count"
fi
if ((${#not_in_backup[@]} > 0)); then
	printf 'Files not in any backup (will be deleted): %d\n' "${#not_in_backup[@]}"
fi

if [ "$CLEAN_BACKUPS" = true ]; then
	printf '\nWARNING: --clean-backups will delete ALL %d backup session(s).\n' "$backup_session_count"
fi

if [ "$DRY_RUN" = true ]; then
	printf '\n=== DRY RUN MODE - No changes will be made ===\n'
	printf '\nWould remove %d files:\n' "${#files_to_remove[@]}"
	for path in "${files_to_remove[@]}"; do
		if [ -e "$HOME/$path" ] || [ -L "$HOME/$path" ]; then
			printf '  - %s\n' "$path"
		fi
	done
	if ((restorable_count > 0)); then
		printf '\nWould restore %d files from backup:\n' "$restorable_count"
		for path in "${!file_restore_session[@]}"; do
			session_name=$(basename "${file_restore_session[$path]}")
			printf '  ~ %s (from %s)\n' "$path" "$session_name"
		done
	fi
	if ((${#not_in_backup[@]} > 0)); then
		printf '\nWould delete (no backup available):\n'
		for path in "${not_in_backup[@]}"; do
			printf '  ! %s\n' "$path"
		done
	fi
	if [ "$CLEAN_BACKUPS" = true ]; then
		printf '\nWould delete backup directory: %s\n' "$backup_root"
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

# Step 1: Remove all managed files
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

# Remove checkout state file
if [ -f "$state_file" ]; then
	rm -f -- "$state_file"
	printf 'Removed checkout state file.\n'
fi

# Step 2: Restore from backup chain
restored=0
failed=0
if ((restorable_count > 0)); then
	printf '\n=== Step 2: Restoring from backup chain ===\n'
	restored=0
	failed=0

	for path in "${!file_restore_session[@]}"; do
		session_dir="${file_restore_session[$path]}"
		backup_file="$session_dir/$path"
		target="$HOME/$path"

		if [ -e "$backup_file" ]; then
			mkdir -p "$(dirname "$target")"
			if cp -- "$backup_file" "$target"; then
				printf 'Restored: %s (from %s)\n' "$path" "$(basename "$session_dir")"
				((restored++)) || true
			else
				printf 'Failed: %s\n' "$path" >&2
				((failed++)) || true
			fi
		else
			printf 'Warning: backup file missing: %s\n' "$path" >&2
			((failed++)) || true
		fi
	done

	printf '\nRestoration summary:\n'
	printf '  Restored: %d\n' "$restored"
	printf '  Failed: %d\n' "$failed"
fi

# Step 3: Clean backups if requested
if [ "$CLEAN_BACKUPS" = true ] && [ -d "$backup_root" ]; then
	printf '\n=== Step 3: Cleaning backup directory ===\n'
	rm -rf -- "$backup_root"
	printf 'Deleted %s\n' "$backup_root"
fi

# Prompt for manual repository removal
printf '\n=== Manual Repository Removal ===\n'
printf 'The bare repository is located at: %s\n' "$git_dir"
printf '\nTo complete the uninstallation, you must manually remove it:\n'
printf '  rm -rf %s\n' "$git_dir"
printf '\nIMPORTANT: Verify that all your configurations are working correctly before removing the repository.\n'

printf '\n=== Uninstall Complete ===\n'
printf 'Files removed: %d\n' "$removed"
printf 'Files restored from backup: %d\n' "$restored"
if [ "$CLEAN_BACKUPS" = false ] && [ -d "$backup_root" ]; then
	printf '\nBackup directory preserved at: %s\n' "$backup_root"
	printf 'To remove all backups: rm -rf %s\n' "$backup_root"
fi
printf '\nRemember to manually remove the repository when ready:\n'
printf '  rm -rf %s\n' "$git_dir"
