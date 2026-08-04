#!/usr/bin/env bash

# install-server.sh - Install dotfiles in server mode (no X11/graphical tools)
# Usage: install-server.sh [--dry-run] [--reinstall] [--force]

set -euo pipefail

# Parse arguments
DRY_RUN=false
REINSTALL=false
FORCE=false
for arg in "$@"; do
	case $arg in
		--dry-run) DRY_RUN=true ;;
		--reinstall) REINSTALL=true ;;
		--force) FORCE=true ;;
	esac
done

repository=${DOTFILES_REPOSITORY:-git@github.com:darkroam/dotfiles.git}
final_git_dir=$HOME/.cfg
timestamp=$(date +%Y%m%dT%H%M%S)
backup_dir=""
temporary_git_dir=

cleanup() {
	if [ -n "$temporary_git_dir" ] && { [ -e "$temporary_git_dir" ] || [ -L "$temporary_git_dir" ]; }; then
		rm -rf -- "$temporary_git_dir"
	fi
}
trap cleanup EXIT

for command_name in git mkdir mv dirname chmod mktemp rm; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'install-server.sh requires %s.\n' "$command_name" >&2
		exit 127
	fi
done

# Source shared validation library
DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/share/dotfiles-lib}"
if [ -f "$DOTFILES_LIB_DIR/cfg-validate.sh" ]; then
	. "$DOTFILES_LIB_DIR/cfg-validate.sh"
else
	printf 'WARNING: Shared validation library not found at %s\n' "$DOTFILES_LIB_DIR/cfg-validate.sh" >&2
	printf 'Falling back to inline validation (deprecated).\n' >&2

	CFG_STATE=""
	CFG_IS_OURS=""
	CFG_NEEDS_PULL=""
	CFG_REMOTE_URL=""

	cfg_validate() {
		local target="${1:-$HOME/.cfg}"
		CFG_STATE="missing"
		CFG_IS_OURS="false"
		CFG_NEEDS_PULL="false"
		CFG_REMOTE_URL=""

		if [ ! -e "$target" ] && [ ! -L "$target" ]; then
			return 0
		fi

		local resolved="$target"
		if [ -L "$target" ]; then
			resolved=$(readlink -f "$target" 2>/dev/null) || { CFG_STATE="not_git"; return 0; }
			[ -d "$resolved" ] || { CFG_STATE="not_git"; return 0; }
		fi

		if ! git --git-dir="$target/" rev-parse --git-dir >/dev/null 2>&1; then
			CFG_STATE="not_git"; return 0
		fi

		local is_bare
		is_bare=$(git --git-dir="$target/" rev-parse --is-bare-repository 2>/dev/null)
		if [ "$is_bare" != "true" ]; then
			CFG_STATE="not_git"; return 0
		fi

		if ! git --git-dir="$target/" rev-parse --verify HEAD >/dev/null 2>&1; then
			CFG_STATE="not_git"; return 0
		fi

		CFG_REMOTE_URL=$(git --git-dir="$target/" config --get remote.origin.url 2>/dev/null || true)

		local has_signature=false
		if git --git-dir="$target/" ls-tree -r --name-only HEAD 2>/dev/null | \
		   grep -qx ".local/bin/install.sh"; then
			has_signature=true
		fi

		local expected_url="${DOTFILES_REPOSITORY:-git@github.com:darkroam/dotfiles.git}"
		if [ -n "$CFG_REMOTE_URL" ]; then
			local normalized_remote normalized_expected
			normalized_remote=$(printf '%s' "$CFG_REMOTE_URL" | sed 's/\.git$//;s|git@github.com:|https://github.com/|')
			normalized_expected=$(printf '%s' "$expected_url" | sed 's/\.git$//;s|git@github.com:|https://github.com/|')
			if [ "$normalized_remote" = "$normalized_expected" ]; then
				CFG_IS_OURS="true"
			elif [ "$has_signature" = "true" ]; then
				CFG_IS_OURS="true"
			else
				CFG_STATE="foreign_repo"; return 0
			fi
		elif [ "$has_signature" = "true" ]; then
			CFG_IS_OURS="true"
		else
			CFG_STATE="foreign_repo"; return 0
		fi

		CFG_STATE="valid"
	}

	cfg_detect_state() {
		local git_dir="${1:-$HOME/.cfg}"
		if [ ! -d "$git_dir" ] && [ ! -L "$git_dir" ]; then
			echo "fresh"; return
		fi
		local desktop_indicators=(.xinitrc .xprofile .config/x11)
		for indicator in "${desktop_indicators[@]}"; do
			if [ -e "$HOME/$indicator" ] || [ -L "$HOME/$indicator" ]; then
				echo "desktop"; return
			fi
		done
		echo "server"
	}

	cfg_should_backup_file() {
		local git_dir="$1"
		local relative_path="$2"
		local full_path="$HOME/$relative_path"
		[ -e "$full_path" ] || [ -L "$full_path" ] || return 1
		if git --git-dir="$git_dir/" --work-tree="$HOME" ls-tree -r --name-only HEAD 2>/dev/null | grep -qx "$relative_path"; then
			local repo_hash local_hash
			repo_hash=$(git --git-dir="$git_dir/" --work-tree="$HOME" show HEAD:"$relative_path" 2>/dev/null | md5sum | cut -d' ' -f1)
			local_hash=$(md5sum < "$full_path" 2>/dev/null | cut -d' ' -f1)
			[ "$repo_hash" = "$local_hash" ] && return 1 || return 0
		else
			return 0
		fi
	}

	cfg_print_validation_result() {
		local git_dir="${1:-$HOME/.cfg}"
		case "$CFG_STATE" in
			missing)    printf 'No existing installation found at %s\n' "$git_dir" ;;
			not_git)    printf 'ERROR: %s exists but is not a valid git repository\n' "$git_dir" ;;
			foreign_repo)
				printf 'ERROR: %s is a git repository but not the dotfiles repository\n' "$git_dir"
				[ -n "$CFG_REMOTE_URL" ] && printf '  Remote URL: %s\n' "$CFG_REMOTE_URL"
				;;
			valid)
				printf 'Valid dotfiles repository found at %s\n' "$git_dir"
				[ -n "$CFG_REMOTE_URL" ] && printf '  Remote: %s\n' "$CFG_REMOTE_URL" || printf '  Remote: (not configured)\n'
				;;
		esac
	}
fi

# ── Validate existing .cfg ──────────────────────────────────────────────
cfg_validate "$final_git_dir"
cfg_print_validation_result "$final_git_dir"

case "$CFG_STATE" in
	not_git)
		if [ "$FORCE" = true ]; then
			printf '\n--force: backing up and removing invalid %s\n' "$final_git_dir"
			invalid_backup="$HOME/.config-backup-invalid-${timestamp}"
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
		if [ "$FORCE" = true ]; then
			printf '\n--force: backing up and removing foreign repo at %s\n' "$final_git_dir"
			foreign_backup="$HOME/.config-backup-foreign-${timestamp}"
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
		if [ "$FORCE" = true ]; then
			printf '\n--force: discarding existing valid repository, doing full clone.\n'
			rm -rf -- "$final_git_dir"
			CFG_STATE="missing"
		fi
		;;
	missing)
	# Fresh install, proceed normally
	;;
esac

# ── Detect current installation state ───────────────────────────────────
current_state=$(cfg_detect_state "$final_git_dir")

# Intelligent state-based decision making
if [ "$CFG_STATE" = "valid" ]; then
	case "$current_state" in
		server)
			if [ "$REINSTALL" = false ]; then
				printf 'Already in server mode.\n'
				printf 'Options:\n'
				printf '  1. Reinstall (overwrite current configuration)\n'
				printf '  2. Cancel and exit\n'
				printf '\nWhat would you like to do? [1/2] '
				read -r choice
				case "$choice" in
					1|y|Y|yes)
						REINSTALL=true
						;;
					*)
						printf 'Aborted.\n'
						exit 0
						;;
				esac
			fi
			printf 'Reinstalling server mode...\n'
			;;
		desktop)
			if [ "$REINSTALL" = false ]; then
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
					2|y|Y|yes)
						REINSTALL=true
						;;
					*)
						printf 'Aborted.\n'
						exit 0
						;;
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
use_existing=false
if [ "$CFG_STATE" = "valid" ] && [ "$FORCE" = false ]; then
	use_existing=true
	git_dir=$final_git_dir
	config() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

	printf '\nFetching updates from remote...\n'
	if ! config fetch origin 2>/dev/null; then
		printf 'WARNING: Could not fetch updates (network or SSH issue).\n'
		printf 'Continuing with local repository state.\n'
	fi
else
	printf 'Cloning repository for server installation...\n'
	temporary_git_dir=$(mktemp -d "$HOME/.cfg.installing.XXXXXX")
	git clone --bare "$repository" "$temporary_git_dir"
	git_dir=$temporary_git_dir
	config() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }
fi

config rev-parse --verify HEAD >/dev/null

# Server-mode file whitelist
server_files=(
	# Shell configuration
	".config/shell/profile"
	".config/shell/aliasrc"
	".config/shell/zshrc"
	".config/shell/tmux.conf.local"
	".bashrc"
	".zshrc"
	".profile"

	# Tmux configuration
	".config/tmux/tmux.conf"
	".config/tmux/tmux.conf.local"
	".tmux.conf"

	# Git configuration
	".config/git/gitconfig"
	".config/git/ignore"
	".gitconfig"
	".gitignore"

	# LF file manager
	".config/lf/lfrc"
	".config/lf/scope"
	".config/lf/cleaner"
	".config/lf/icons"
	".config/lf/shortcutrc"

	# Documentation
	".local/share/docs/README.md"
	".local/share/docs/user/desktop-guide-zh.md"
)

# Analyze files and categorize them
to_install=()
to_backup=()
to_skip=()

printf '\nAnalyzing configurations...\n'
for path in "${server_files[@]}"; do
	if ! config ls-tree -r --name-only HEAD | grep -qx "$path"; then
		continue  # File not in repo, skip
	fi

	full_path="$HOME/$path"

	if [ ! -e "$full_path" ] && [ ! -L "$full_path" ]; then
		to_install+=("$path")
	elif cfg_should_backup_file "$git_dir" "$path"; then
		to_backup+=("$path")
	else
		to_skip+=("$path")
	fi
done

# Determine backup directory name based on state transition
if ((${#to_backup[@]} > 0)); then
	target_state="server"
	backup_dir="$HOME/.config-backup-${current_state}-to-${target_state}-${timestamp}"
fi

# Print pre-installation report
printf '\n=== Pre-installation Report ===\n\n'
printf 'Current state: %s\n' "$current_state"
printf 'Target state: server\n'
if [ "$use_existing" = true ]; then
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

if [ "$DRY_RUN" = true ]; then
	printf '\n=== DRY RUN MODE - No changes will be made ===\n'
	exit 0
fi

printf '\nProceed with installation? [y/N] '
read -r confirm
if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
	printf 'Aborted.\n'
	exit 0
fi

# Handle backups
if ((${#to_backup[@]})); then
	if [ -L "$backup_dir" ] || { [ -e "$backup_dir" ] && [ ! -d "$backup_dir" ]; }; then
		printf 'Backup root must be a real directory: %s\n' "$backup_dir" >&2
		exit 1
	fi

	mkdir -p -- "$backup_dir"
	chmod 700 "$backup_dir"

	# Create manifest
	manifest="$backup_dir/MANIFEST.txt"
	printf '# Backup manifest created at %s\n' "$(date)" > "$manifest"
	printf '# State transition: %s -> server\n' "$current_state" >> "$manifest"
	printf '# Format: original_path -> backup_path (status)\n\n' >> "$manifest"

	printf '\nBacking up %d files...\n' "${#to_backup[@]}"
	for path in "${to_backup[@]}"; do
		source_path="$HOME/$path"
		backup_path="$backup_dir/$path"
		mkdir -p -- "$(dirname "$backup_path")"

		# Determine file status for manifest
		status="untracked"
		if config ls-tree -r --name-only HEAD | grep -qx "$path"; then
			status="modified"
		fi

		mv -- "$source_path" "$backup_path"
		printf '%s -> %s (%s)\n' "$source_path" "$backup_path" "$status" >> "$manifest"
		printf 'Backed up: %s\n' "$path"
	done

	printf '\nBackup directory: %s\n' "$backup_dir"
	printf 'Manifest: %s\n' "$manifest"
fi

# Rollback function for checkout failures
rollback_from_backup() {
	if [ -z "${backup_dir:-}" ] || [ ! -d "${backup_dir:-}" ]; then
		return
	fi
	printf '\nRolling back: restoring files from backup...\n' >&2
	for path in "${to_backup[@]}"; do
		backup_path="$backup_dir/$path"
		target_path="$HOME/$path"
		if [ -e "$backup_path" ]; then
			{ [ -e "$target_path" ] || [ -L "$target_path" ]; } && rm -f -- "$target_path"
			mkdir -p -- "$(dirname "$target_path")"
			mv -- "$backup_path" "$target_path" 2>/dev/null || \
				printf 'Warning: could not restore %s\n' "$path" >&2
		fi
	done
}

# Checkout server-relevant configurations
printf '\nInstalling configurations...\n'
installed=0
skipped_checkout=0
total=$((${#to_install[@]} + ${#to_backup[@]}))
current=0

for path in "${to_install[@]}" "${to_backup[@]}"; do
	if config checkout HEAD -- "$path" 2>/dev/null; then
		((installed++)) || true
	else
		((skipped_checkout++)) || true
	fi
	((current++)) || true
	if (( current % 5 == 0 )) || (( current == total )); then
		printf 'Progress: %d/%d\n' "$current" "$total"
	fi
done

if (( skipped_checkout > 0 && total > 0 && skipped_checkout * 2 > total )); then
	printf '\nERROR: %d/%d files failed to checkout. Rolling back...\n' "$skipped_checkout" "$total" >&2
	rollback_from_backup
	exit 1
fi

# Activate the bare repository (only if we cloned a new one)
if [ "$use_existing" = false ]; then
	if ! mv -- "$temporary_git_dir" "$final_git_dir"; then
		printf 'Failed to activate %s.\n' "$final_git_dir" >&2
		exit 1
	fi
	temporary_git_dir=
	git_dir=$final_git_dir
fi

# Configure to hide untracked files
config config status.showUntrackedFiles no

# Record checkout state for future modification detection
state_file="$HOME/.cfg-checkout-state"
> "$state_file"
while IFS= read -r path; do
	hash=$(config show HEAD:"$path" | md5sum | cut -d' ' -f1)
	echo "$path:$hash" >> "$state_file"
done < <(config ls-tree -r --name-only HEAD)

printf '\n=== Server Installation Complete ===\n'
printf 'Installed: %d files\n' "$installed"
if ((skipped_checkout > 0)); then
	printf 'Skipped (checkout failed): %d files\n' "$skipped_checkout"
fi
printf 'Skipped (identical): %d files\n' "${#to_skip[@]}"
if [ -d "$backup_dir" ]; then
	printf 'Backed up: %d files to %s\n' "${#to_backup[@]}" "$backup_dir"
fi
if [ "$use_existing" = true ]; then
	printf '\nServer configuration updated from existing repository.\n'
else
	printf '\nNote: This is a server-only installation without X11, audio, or graphical tools.\n'
fi
printf 'To restore full desktop configuration, run: ~/.local/bin/restore-desktop.sh\n'
