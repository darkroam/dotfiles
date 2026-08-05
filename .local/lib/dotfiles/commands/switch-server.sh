#!/usr/bin/env bash

# switch-server.sh - Switch to server mode (from fresh or desktop)
# Usage: switch-server.sh [--dry-run] [--reinstall] [--force]

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
		printf 'switch-server.sh requires %s.\n' "$command_name" >&2
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
			printf '\n--force: discarding existing valid repository, doing full clone.\n'
			rm -rf -- "$final_git_dir"
			CFG_STATE="missing"
		fi
		;;
	missing)
		;;
esac

# ── Detect current state ────────────────────────────────────────────────
current_state=$(cfg_detect_state "$final_git_dir")
target_state="server"

# State-based decision making
if [ "$CFG_STATE" = "valid" ]; then
	case "$current_state" in
		server)
			if [ "$CFG_REINSTALL" = false ]; then
				printf 'Already in server mode.\n'
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
			printf 'Reinstalling server mode...\n'
			;;
		desktop)
			if [ "$CFG_REINSTALL" = false ]; then
				printf 'Currently in desktop mode.\n'
				printf 'Options:\n'
				printf '  1. Switch to server mode (recommended: use restore-server.sh)\n'
				printf '  2. Reinstall as server (overwrite desktop configuration)\n'
				printf '  3. Cancel and exit\n'
				printf '\nWhat would you like to do? [1/2/3] '
				read -r choice
				case "$choice" in
					1)
						printf '\nPlease run: ~/.local/bin/restore-server.sh\n'
						exit 0
						;;
					2|y|Y|yes) CFG_REINSTALL=true ;;
					*) printf 'Aborted.\n'; exit 0 ;;
				esac
			fi
			printf 'Installing server mode (overwriting desktop)...\n'
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

# ── Analyze server files ────────────────────────────────────────────────
printf '\nAnalyzing configurations...\n'
cfg_analyze_server_files "$git_dir"

to_install=("${CFG_TO_INSTALL[@]}")
to_backup=("${CFG_TO_BACKUP[@]}")
to_skip=("${CFG_TO_SKIP[@]}")

# Track which server files exist as desktop indicators and will be removed
desktop_server_files=()
if [ "$current_state" = "desktop" ]; then
	for path in "${CFG_SERVER_FILES[@]}"; do
		for link in "${CFG_DESKTOP_ONLY_SYMLINKS[@]}"; do
			if [ "$path" = "$link" ]; then
				full_path="$HOME/$path"
				if [ -e "$full_path" ] || [ -L "$full_path" ]; then
					desktop_server_files+=("$path")
				fi
			fi
		done
	done
fi

# Determine backup directory
if ((${#to_backup[@]} > 0)); then
	backup_dir="$HOME/.config-backup/${current_state}-to-${target_state}-${timestamp}"
fi

# ── Print pre-installation report ───────────────────────────────────────
printf '\n=== Pre-installation Report ===\n\n'
printf 'Current state: %s\n' "$current_state"
printf 'Target state: server\n'
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
	cfg_create_backup_dir "$current_state" "$target_state" "$timestamp"
	cfg_backup_files "$git_dir" "${to_backup[@]}"
	backup_dir="$CFG_BACKUP_DIR"
fi

# ── Remove desktop indicators (if switching from desktop) ───────────────
if [ "$current_state" = "desktop" ]; then
	printf '\nRemoving desktop-specific files...\n'
	for link in "${CFG_DESKTOP_ONLY_SYMLINKS[@]}"; do
		full_path="$HOME/$link"
		if [ -L "$full_path" ]; then
			rm -f -- "$full_path"
			printf 'Removed symlink: %s\n' "$link"
		elif [ -f "$full_path" ]; then
			rm -f -- "$full_path"
			printf 'Removed file: %s\n' "$link"
		fi
	done

	for dir in "${CFG_DESKTOP_ONLY_DIRS[@]}"; do
		full_path="$HOME/$dir"
		if [ -L "$full_path" ]; then
			rm -f -- "$full_path"
			printf 'Removed symlink dir: %s\n' "$dir"
		elif [ -d "$full_path" ]; then
			rm -rf -- "$full_path"
			printf 'Removed directory: %s\n' "$dir"
		fi
	done
fi

# Add server files that were removed as desktop indicators to install list
for path in "${desktop_server_files[@]}"; do
	# Check if it's not already in to_install or to_backup
	found=false
	for install_path in "${to_install[@]}"; do
		[ "$path" = "$install_path" ] && found=true && break
	done
	for backup_path in "${to_backup[@]}"; do
		[ "$path" = "$backup_path" ] && found=true && break
	done
	if [ "$found" = false ]; then
		to_install+=("$path")
	fi
done

# ── Checkout server configurations ──────────────────────────────────────
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

# Record checkout state (only server files)
state_file="$HOME/.cfg-checkout-state"
> "$state_file"
for path in "${to_install[@]}" "${to_backup[@]}" "${to_skip[@]}"; do
	hash=$(config show HEAD:"$path" | md5sum | cut -d' ' -f1)
	echo "$path:$hash" >> "$state_file"
done

printf '\n=== Server Installation Complete ===\n'
printf 'Installed: %d files\n' "$installed"
if ((skipped_checkout > 0)); then
	printf 'Skipped (checkout failed): %d files\n' "$skipped_checkout"
fi
printf 'Skipped (identical): %d files\n' "${#to_skip[@]}"
if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
	printf 'Backed up: %d files to %s\n' "${#to_backup[@]}" "$backup_dir"
fi
if [ "$CFG_USE_EXISTING" = true ]; then
	printf '\nServer configuration updated from existing repository.\n'
else
	printf '\nNote: This is a server-only installation without X11, audio, or graphical tools.\n'
fi
printf 'To restore full desktop configuration, run: ~/.local/bin/restore-desktop.sh\n'
