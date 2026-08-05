#!/usr/bin/env bash

# switch-desktop.sh - Switch to desktop mode (from fresh or server)
# Usage: switch-desktop.sh [--dry-run] [--reinstall] [--force] [--auto-stash]

set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

cfg_parse_common_args "$@"

final_git_dir=$HOME/.cfg
timestamp=$(date +%Y%m%dT%H%M%S)
backup_dir=""

trap cfg_cleanup_temp_dir EXIT

for command_name in git mkdir mv dirname chmod mktemp rm; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'switch-desktop.sh requires %s.\n' "$command_name" >&2
		exit 127
	fi
done

# ── Validate existing .cfg ──────────────────────────────────────────────
cfg_validate "$final_git_dir"
cfg_print_validation_result "$final_git_dir"

case "$CFG_STATE" in
	not_git)
		if [ "$CFG_FORCE" = true ]; then
			printf '\n--force: backing up and removing invalid %s\n' "$final_git_dir"
			invalid_backup="$HOME/.config-backup/invalid-${timestamp}"
			mkdir -p -- "$invalid_backup"
			chmod 700 "$invalid_backup"
			if [ -d "$final_git_dir" ] && [ ! -L "$final_git_dir" ]; then
				mv -- "$final_git_dir" "$invalid_backup/.cfg"
			else
				rm -f -- "$final_git_dir"
			fi
			CFG_STATE="missing"
		else
			printf '\nError: %s exists but is not a valid git repository.\n' "$final_git_dir" >&2
			printf 'Back it up and remove it, then retry. Or use --force to auto-remove.\n' >&2
			exit 1
		fi
		;;
	foreign_repo)
		if [ "$CFG_FORCE" = true ]; then
			printf '\n--force: backing up and removing foreign repo at %s\n' "$final_git_dir"
			foreign_backup="$HOME/.config-backup/foreign-${timestamp}"
			mkdir -p -- "$foreign_backup"
			chmod 700 "$foreign_backup"
			if [ -d "$final_git_dir" ] && [ ! -L "$final_git_dir" ]; then
				mv -- "$final_git_dir" "$foreign_backup/.cfg"
			else
				rm -f -- "$final_git_dir"
			fi
			CFG_STATE="missing"
		else
			printf '\nError: %s is a git repository but not the dotfiles repository.\n' "$final_git_dir" >&2
			[ -n "$CFG_REMOTE_URL" ] && printf '  Remote: %s\n' "$CFG_REMOTE_URL" >&2
			printf 'Use --force to back it up and replace it.\n' >&2
			exit 1
		fi
		;;
	valid)
		if [ "$CFG_FORCE" = true ]; then
			printf '\n--force: backing up existing valid repository before full clone.\n'
			valid_backup="$HOME/.config-backup/valid-to-fresh-${timestamp}"
			mkdir -p -- "$valid_backup"
			chmod 700 "$valid_backup"
			if [ -d "$final_git_dir" ] && [ ! -L "$final_git_dir" ]; then
				mv -- "$final_git_dir" "$valid_backup/.cfg"
			else
				rm -f -- "$final_git_dir"
			fi
			CFG_STATE="missing"
		fi
		;;
	missing)
		;;
esac

# ── Detect current state ────────────────────────────────────────────────
current_state=$(cfg_detect_state "$final_git_dir")
target_state="desktop"

# State-based decision making
if [ "$CFG_STATE" = "valid" ]; then
	case "$current_state" in
		desktop)
			if [ "$CFG_REINSTALL" = false ]; then
				printf 'Already in desktop mode.\n'
				printf 'Options:\n'
				printf '  1. Reinstall (overwrite current configuration)\n'
				printf '  2. Cancel and exit\n'
				printf '\nWhat would you like to do? [1/2] '
				read -r choice
				case "$choice" in
					1|y|Y|yes) CFG_REINSTALL=true ;;
					*) printf 'Aborted.\n'; exit 0 ;;
				esac
			fi
			printf 'Reinstalling desktop mode...\n'
			;;
		server)
			if [ "$CFG_REINSTALL" = false ]; then
				printf 'Currently in server mode.\n'
				printf 'Options:\n'
				printf '  1. Switch to desktop mode\n'
				printf '  2. Cancel and exit\n'
				printf '\nWhat would you like to do? [1/2] '
				read -r choice
				case "$choice" in
					1|y|Y|yes) CFG_REINSTALL=true ;;
					*) printf 'Aborted.\n'; exit 0 ;;
				esac
			fi
			printf 'Switching to desktop mode...\n'
			;;
		fresh)
			printf 'Existing repository found. Proceeding with install...\n'
			;;
	esac
else
	printf 'No existing installation found. Proceeding with fresh install...\n'
fi

# ── Clone or reuse repository ───────────────────────────────────────────
if [ "$CFG_STATE" = "valid" ] && [ "$CFG_FORCE" = false ]; then
	CFG_USE_EXISTING=true
	CFG_GIT_DIR="$final_git_dir"
	printf '\nFetching updates from remote...\n'
	if ! git --git-dir="$CFG_GIT_DIR/" --work-tree="$HOME" fetch origin 2>/dev/null; then
		printf 'WARNING: Could not fetch updates (network or SSH issue).\n'
		printf 'Continuing with local repository state.\n'
	fi
else
	cfg_setup_repository "$current_state" "$CFG_FORCE" \
		"${DOTFILES_REPOSITORY:-git@github.com:darkroam/dotfiles.git}" "$final_git_dir"
fi

git_dir="$CFG_GIT_DIR"
config() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

config rev-parse --verify HEAD >/dev/null

# ── Analyze files ───────────────────────────────────────────────────────
printf '\nAnalyzing configurations...\n'
cfg_analyze_all_tracked "$git_dir"

to_install=("${CFG_TO_INSTALL[@]}")
to_backup=("${CFG_TO_BACKUP[@]}")
to_skip=("${CFG_TO_SKIP[@]}")

# Determine backup directory
if ((${#to_backup[@]} > 0)); then
	backup_dir="$HOME/.config-backup/${current_state}-to-${target_state}-${timestamp}"
fi

# ── Print pre-installation report ───────────────────────────────────────
printf '\n=== Pre-installation Report ===\n\n'
printf 'Current state: %s\n' "$current_state"
printf 'Target state: desktop (full)\n'
if [ "$CFG_USE_EXISTING" = true ]; then
	printf 'Repository: reusing existing (skipped clone)\n'
fi
if [ -n "$backup_dir" ]; then
	printf 'Backup directory: %s\n' "$backup_dir"
fi

printf '\nFiles to install (new): %d\n' "${#to_install[@]}"
for path in "${to_install[@]}"; do
	printf '  + %s\n' "$path"
done

printf '\nFiles to backup (modified/untracked): %d\n' "${#to_backup[@]}"
for path in "${to_backup[@]}"; do
	printf '  ~ %s\n' "$path"
done

printf '\nFiles to skip (identical to repo): %d\n' "${#to_skip[@]}"
for path in "${to_skip[@]}"; do
	printf '  = %s\n' "$path"
done

if [ "$CFG_DRY_RUN" = true ]; then
	printf '\n=== DRY RUN MODE - No changes will be made ===\n'
	exit 0
fi

printf '\nProceed with installation? [y/N] '
read -r confirm
if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
	printf 'Aborted.\n'
	exit 0
fi

# ── Handle backups ──────────────────────────────────────────────────────
if ((${#to_backup[@]})); then
	if [ "$CFG_AUTO_STASH" = true ]; then
		printf '\n--auto-stash: removing %d conflicting files without backup...\n' "${#to_backup[@]}"
		for path in "${to_backup[@]}"; do
			rm -f -- "$HOME/$path"
			printf 'Removed: %s\n' "$path"
		done
	else
		cfg_create_backup_dir "$current_state" "$target_state" "$timestamp"
		cfg_backup_files "$git_dir" "${to_backup[@]}"
		backup_dir="$CFG_BACKUP_DIR"
	fi
fi

# ── Checkout all configurations ─────────────────────────────────────────
printf '\nInstalling configurations...\n'
result=$(cfg_checkout_files "$git_dir" "${to_install[@]}" "${to_backup[@]}")
installed=${result% *}
skipped_checkout=${result#* }
total=$((${#to_install[@]} + ${#to_backup[@]}))

if (( skipped_checkout > 0 && total > 0 && skipped_checkout * 2 > total )); then
	printf '\nERROR: %d/%d files failed to checkout. Rolling back...\n' "$skipped_checkout" "$total" >&2
	if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
		cfg_rollback_from_backup "$backup_dir" "${to_backup[@]}"
	fi
	exit 1
fi

# ── Activate repository ─────────────────────────────────────────────────
cfg_activate_repository "$final_git_dir"
git_dir="$CFG_GIT_DIR"

# Configure to hide untracked files
git --git-dir="$git_dir/" --work-tree="$HOME" config status.showUntrackedFiles no

# Record checkout state
cfg_record_checkout_state "$git_dir"

printf '\n=== Installation Complete ===\n'
printf 'Installed: %d files\n' "$installed"
if ((skipped_checkout > 0)); then
	printf 'Skipped (checkout failed): %d files\n' "$skipped_checkout"
fi
printf 'Skipped (identical): %d files\n' "${#to_skip[@]}"
if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
	printf 'Backed up: %d files to %s\n' "${#to_backup[@]}" "$backup_dir"
fi
if [ "$CFG_USE_EXISTING" = true ]; then
	printf '\nDesktop configuration updated from existing repository.\n'
else
	printf '\nFull desktop configuration has been installed.\n'
fi
printf 'You may need to:\n'
printf '  - Restart your shell or run: source ~/.profile\n'
printf '  - Install dependencies: see .local/share/docs/project/dependencies.md\n'
printf '  - Build suckless tools: see README.md\n'
