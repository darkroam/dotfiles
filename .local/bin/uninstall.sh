#!/usr/bin/env bash

# uninstall.sh - Remove dotfiles repository and optionally restore backed up configs
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

# Source shared validation library for informative messages
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
printf '  1. Remove root-level symlinks created by the installer\n'
printf '  2. Optionally restore backed up configs\n'
printf '  3. Manually remove the repository (you will be prompted)\n'

# Check for backup directories
mapfile -t backup_dirs < <(compgen -G "$backup_pattern" 2>/dev/null || true)
if ((${#backup_dirs[@]} > 0)); then
	printf '\nFound backup directories:\n'
	for bd in "${backup_dirs[@]}"; do
		printf '  - %s\n' "$bd"
	done
fi
printf '\nYour original config files (if backed up) can be restored.\n\n'

# Confirm removal
printf 'Proceed with uninstallation? [y/N] '
read -r confirm
if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
	printf 'Aborted.\n'
	exit 0
fi

# Check if repository exists
if [ ! -d "$git_dir" ] && [ ! -L "$git_dir" ]; then
	printf 'Repository not found at %s. Nothing to uninstall.\n' "$git_dir" >&2
	exit 1
fi

if [ "$DRY_RUN" = true ]; then
	printf '\n=== DRY RUN MODE - No changes will be made ===\n'

	# List symlinks that would be removed
	symlinks=(
		"$HOME/.profile"
		"$HOME/.zprofile"
		"$HOME/.bashrc"
		"$HOME/.zshrc"
		"$HOME/.xinitrc"
		"$HOME/.xprofile"
		"$HOME/.asoundrc"
		"$HOME/.gtkrc-2.0"
		"$HOME/.tmux.conf"
		"$HOME/.gitconfig"
		"$HOME/.gitignore"
	)

	printf 'Would remove symlinks:\n'
	for link in "${symlinks[@]}"; do
		if [ -L "$link" ]; then
			printf '  - %s\n' "$(basename "$link")"
		fi
	done

	printf '\nNote: Repository at %s will NOT be automatically removed.\n' "$git_dir"
	printf 'You must manually remove it after confirming everything works.\n'

	exit 0
fi

# Offer to restore backups
if ((${#backup_dirs[@]} > 0)); then
	printf '\nFound %d backup director(y/ies):\n' "${#backup_dirs[@]}"
	for i in "${!backup_dirs[@]}"; do
		printf '  [%d] %s\n' "$((i+1))" "${backup_dirs[$i]}"
	done
	printf '\nRestore backed up configurations? [y/N] '
	read -r restore
	if [[ "$restore" == [yY] || "$restore" == [yY][eE][sS] ]]; then
		# Let user choose which backup to restore
		if ((${#backup_dirs[@]} > 1)); then
			printf 'Enter backup number to restore (1-%d): ' "${#backup_dirs[@]}"
			read -r choice
			if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#backup_dirs[@]})); then
				selected_backup="${backup_dirs[$((choice-1))]}"
			else
				printf 'Invalid selection. Skipping restoration.\n'
				selected_backup=""
			fi
		else
			selected_backup="${backup_dirs[0]}"
		fi

		if [ -n "$selected_backup" ] && [ -d "$selected_backup" ]; then
			printf 'Restoring from: %s\n' "$selected_backup"

			# Check for manifest
			manifest="$selected_backup/MANIFEST.txt"
			if [ -f "$manifest" ]; then
				printf 'Using manifest for restoration...\n'
				restored=0
				skipped=0
				failed=0

				while IFS= read -r line; do
					# Skip comments and empty lines
					[[ "$line" =~ ^#.*$ ]] && continue
					[[ -z "$line" ]] && continue

					# Parse "source -> backup (status)" format
					if [[ "$line" =~ ^(.+)\ -\>\ (.+)\ \((modified|untracked)\)$ ]]; then
						original="${BASH_REMATCH[1]}"
						backup_file="${BASH_REMATCH[2]}"

						if [ -e "$original" ] || [ -L "$original" ]; then
							printf 'Skipped (exists): %s\n' "$(basename "$original")"
							((skipped++)) || true
							continue
						fi

						mkdir -p "$(dirname "$original")"
						if mv -- "$backup_file" "$original"; then
							printf 'Restored: %s\n' "$(basename "$original")"
							((restored++)) || true
						else
							printf 'Failed: %s\n' "$(basename "$original")" >&2
							((failed++)) || true
						fi
					fi
				done < "$manifest"

				printf '\nRestoration summary:\n'
				printf '  Restored: %d\n' "$restored"
				printf '  Skipped (exists): %d\n' "$skipped"
				printf '  Failed: %d\n' "$failed"
			else
				# Fallback: restore all files without manifest
				printf 'No manifest found. Restoring all files...\n'
				restored=0
				while IFS= read -r -d '' backup_file; do
					relative_path="${backup_file#$selected_backup/}"
					[[ "$relative_path" == "MANIFEST.txt" ]] && continue

					target="$HOME/$relative_path"
					if [ -e "$target" ] || [ -L "$target" ]; then
						printf 'Skipped (exists): %s\n' "$relative_path"
						continue
					fi

					mkdir -p "$(dirname "$target")"
					if mv -- "$backup_file" "$target"; then
						printf 'Restored: %s\n' "$relative_path"
						((restored++)) || true
					fi
				done < <(find "$selected_backup" -type f -print0)
				printf 'Restored %d files.\n' "$restored"
			fi
		fi
	else
		printf 'Skipping backup restoration.\n'
	fi
else
	printf 'No backup directories found.\n'
fi

# Remove root-level symlinks
printf '\nRemoving installation symlinks...\n'
symlinks=(
	"$HOME/.profile"
	"$HOME/.zprofile"
	"$HOME/.bashrc"
	"$HOME/.zshrc"
	"$HOME/.xinitrc"
	"$HOME/.xprofile"
	"$HOME/.asoundrc"
	"$HOME/.gtkrc-2.0"
	"$HOME/.tmux.conf"
	"$HOME/.gitconfig"
	"$HOME/.gitignore"
)

removed=0
for link in "${symlinks[@]}"; do
	if [ -L "$link" ]; then
		rm -f -- "$link"
		printf 'Removed: %s\n' "$(basename "$link")"
		((removed++)) || true
	fi
done
printf 'Removed %d symlinks.\n' "$removed"

# Prompt for manual repository removal
printf '\n=== Manual Repository Removal ===\n'
printf 'The bare repository is located at: %s\n' "$git_dir"
printf '\nTo complete the uninstallation, you must manually remove it:\n'
printf '  rm -rf %s\n' "$git_dir"
printf '\nIMPORTANT: Verify that all your configurations are working correctly before removing the repository.\n'
printf 'If you need to restore configs later, backup directories have been preserved (see below).\n'

printf '\n=== Uninstall Complete ===\n'
printf 'Symlinks removed: %d\n' "$removed"
if ((${#backup_dirs[@]} > 0)); then
	printf '\nBackup directories preserved:\n'
	for bd in "${backup_dirs[@]}"; do
		printf '  - %s\n' "$bd"
	done
	printf '\nTo restore from a backup, use: ~/.local/bin/restore-backup.sh <backup-directory>\n'
	printf 'Or manually copy files back from the backup directory.\n'
fi
printf '\nRemember to manually remove the repository when ready:\n'
printf '  rm -rf %s\n' "$git_dir"
