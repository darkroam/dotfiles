#!/usr/bin/env bash

# restore-server.sh - Switch from desktop mode to server mode
# Usage: restore-server.sh [--dry-run]
# Note: This does NOT modify the repository; it only affects the working tree.

set -euo pipefail

# Parse arguments
DRY_RUN=false
for arg in "$@"; do
	case $arg in
		--dry-run) DRY_RUN=true ;;
	esac
done

git_dir=$HOME/.cfg
timestamp=$(date +%Y%m%dT%H%M%S)
backup_dir=""

# Source shared validation library
DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
if [ -f "$DOTFILES_LIB_DIR/cfg-validate.sh" ]; then
	. "$DOTFILES_LIB_DIR/cfg-validate.sh"
else
	printf 'WARNING: Shared validation library not found at %s\n' "$DOTFILES_LIB_DIR/cfg-validate.sh" >&2

	CFG_STATE=""
	CFG_IS_OURS=""
	CFG_REMOTE_URL=""

	cfg_validate() {
		local target="${1:-$HOME/.cfg}"
		CFG_STATE="missing"
		CFG_IS_OURS="false"
		CFG_REMOTE_URL=""
		[ ! -e "$target" ] && [ ! -L "$target" ] && return 0
		local resolved="$target"
		if [ -L "$target" ]; then
			resolved=$(readlink -f "$target" 2>/dev/null) || { CFG_STATE="not_git"; return 0; }
			[ -d "$resolved" ] || { CFG_STATE="not_git"; return 0; }
		fi
		git --git-dir="$target/" rev-parse --git-dir >/dev/null 2>&1 || { CFG_STATE="not_git"; return 0; }
		local is_bare
		is_bare=$(git --git-dir="$target/" rev-parse --is-bare-repository 2>/dev/null)
		[ "$is_bare" = "true" ] || { CFG_STATE="not_git"; return 0; }
		git --git-dir="$target/" rev-parse --verify HEAD >/dev/null 2>&1 || { CFG_STATE="not_git"; return 0; }
		CFG_REMOTE_URL=$(git --git-dir="$target/" config --get remote.origin.url 2>/dev/null || true)
		local has_signature=false
		if git --git-dir="$target/" ls-tree -r --name-only HEAD 2>/dev/null | grep -qx ".local/bin/install.sh"; then
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
fi

# ── Validate existing .cfg ──────────────────────────────────────────────
cfg_validate "$git_dir"

case "$CFG_STATE" in
	missing)
		printf 'Bare repository not found at %s. Run install.sh first.\n' "$git_dir" >&2
		exit 1
		;;
	not_git)
		printf 'Error: %s exists but is not a valid git repository.\n' "$git_dir" >&2
		exit 1
		;;
	foreign_repo)
		printf 'Error: %s is a git repository but not the dotfiles repository.\n' "$git_dir" >&2
		[ -n "$CFG_REMOTE_URL" ] && printf '  Remote: %s\n' "$CFG_REMOTE_URL" >&2
		exit 1
		;;
	valid)
		printf 'Valid dotfiles repository found.\n'
		;;
esac

config() {
	git --git-dir="$git_dir/" --work-tree="$HOME" "$@"
}

# Detect current state
detect_state() {
	local desktop_indicators=(.xinitrc .xprofile .config/x11)
	for indicator in "${desktop_indicators[@]}"; do
		if [ -e "$HOME/$indicator" ] || [ -L "$HOME/$indicator" ]; then
			echo "desktop"
			return
		fi
	done
	echo "server"
}

current_state=$(detect_state)
target_state="server"

# Desktop-only symlinks to remove
desktop_symlinks=(
	".xinitrc"
	".xprofile"
	".asoundrc"
	".gtkrc-2.0"
	".tmux.conf"
	".gitconfig"
	".gitignore"
)

# Desktop config directories (symlinks)
desktop_dirs=(
	".config/x11"
	".config/alsa"
	".config/mpd"
	".config/nsxiv"
	".config/zathura"
)

# Analyze desktop symlinks to remove
to_remove_symlinks=()
to_remove_dirs=()
to_remove_regular=()
already_removed_symlinks=()
already_removed_dirs=()

# Analyze files that need backup before removal
to_backup_files=()

printf 'Analyzing current state...\n'

for link in "${desktop_symlinks[@]}"; do
	full_path="$HOME/$link"
	if [ -L "$full_path" ]; then
		to_remove_symlinks+=("$link")
	elif [ -f "$full_path" ]; then
		if cfg_should_backup_file "$git_dir" "$link"; then
			to_backup_files+=("$link")
		else
			to_remove_regular+=("$link")
		fi
	else
		already_removed_symlinks+=("$link")
	fi
done

for dir in "${desktop_dirs[@]}"; do
	full_path="$HOME/$dir"
	if [ -L "$full_path" ] || [ -d "$full_path" ]; then
		to_remove_dirs+=("$dir")
	else
		already_removed_dirs+=("$dir")
	fi
done

# Determine backup directory name
if ((${#to_backup_files[@]} > 0)); then
	backup_dir="$HOME/.config-backup/${current_state}-to-${target_state}-${timestamp}"
fi

# Print analysis
printf '\n=== Server Mode Restoration Analysis ===\n\n'
printf 'Current state: %s\n' "$current_state"
printf 'Target state: %s\n' "$target_state"
if [ -n "$backup_dir" ]; then
	printf 'Backup directory: %s\n' "$backup_dir"
fi

printf '\nDesktop symlinks to remove: %d\n' "${#to_remove_symlinks[@]}"
for link in "${to_remove_symlinks[@]}"; do
	printf '  - %s\n' "$link"
done

printf '\nDesktop directory symlinks to remove: %d\n' "${#to_remove_dirs[@]}"
for dir in "${to_remove_dirs[@]}"; do
	printf '  - %s\n' "$dir"
done

printf '\nFiles to backup (modified/untracked): %d\n' "${#to_backup_files[@]}"
for file in "${to_backup_files[@]}"; do
	status="untracked"
	if config ls-tree -r --name-only HEAD | grep -qx "$file"; then
		status="modified"
	fi
	printf '  ~ %s (%s)\n' "$file" "$status"
done

printf '\nAlready removed (skipping): %d symlinks, %d dirs\n' \
	"${#already_removed_symlinks[@]}" "${#already_removed_dirs[@]}"

if [ "$DRY_RUN" = true ]; then
	printf '\n=== DRY RUN MODE - No changes will be made ===\n'
	exit 0
fi

# Backup conflicting files before removal
if ((${#to_backup_files[@]} > 0)); then
	if [ -L "$backup_dir" ] || { [ -e "$backup_dir" ] && [ ! -d "$backup_dir" ]; }; then
		printf 'Backup root must be a real directory: %s\n' "$backup_dir" >&2
		exit 1
	fi

	mkdir -p -- "$backup_dir"
	chmod 700 "$backup_dir"

	manifest="$backup_dir/MANIFEST.txt"
	printf '# Created: %s\n' "$(date)" > "$manifest"
	printf '# Transition: %s -> %s\n' "$current_state" "$target_state" >> "$manifest"
	printf '#\n# relative_path\tmd5\tstatus\n' >> "$manifest"

	printf '\nBacking up %d files...\n' "${#to_backup_files[@]}"
	for path in "${to_backup_files[@]}"; do
		source_path="$HOME/$path"
		backup_path="$backup_dir/$path"
		mkdir -p -- "$(dirname "$backup_path")"

		status="untracked"
		if config ls-tree -r --name-only HEAD | grep -qx "$path"; then
			status="modified"
		fi

		# Compute MD5 before moving
		md5=$(md5sum < "$source_path" 2>/dev/null | cut -d' ' -f1)

		mv -- "$source_path" "$backup_path"
		printf '%s\t%s\t%s\n' "$path" "$md5" "$status" >> "$manifest"
		printf 'Backed up: %s\n' "$path"
	done

	printf '\nBackup directory: %s\n' "$backup_dir"
	printf 'Manifest: %s\n' "$manifest"
fi

if ((${#to_remove_symlinks[@]} == 0)) && ((${#to_remove_dirs[@]} == 0)) && ((${#to_remove_regular[@]} == 0)); then
	printf '\nNo desktop symlinks found. Already in server mode or using direct files.\n'
	printf 'Proceeding to verify server configs...\n'
else
	printf '\nProceed with removing desktop symlinks? [y/N] '
	read -r confirm
	if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
		printf 'Aborted.\n'
		exit 0
	fi

	# Remove desktop symlinks
	printf '\nRemoving desktop symlinks...\n'
	for link in "${to_remove_symlinks[@]}"; do
		rm -f -- "$HOME/$link"
		printf 'Removed: %s\n' "$link"
	done

	# Remove desktop regular files (identical to repo, no backup needed)
	for link in "${to_remove_regular[@]}"; do
		rm -f -- "$HOME/$link"
		printf 'Removed: %s\n' "$link"
	done

	# Remove desktop directory symlinks and regular directories
	printf '\nRemoving desktop directory symlinks...\n'
	for dir in "${to_remove_dirs[@]}"; do
		if [ -L "$HOME/$dir" ]; then
			rm -f -- "$HOME/$dir"
		elif [ -d "$HOME/$dir" ]; then
			rm -rf -- "$HOME/$dir"
		fi
		printf 'Removed: %s\n' "$dir"
	done
fi

# Ensure server-relevant configs are checked out
printf '\nVerifying server configurations...\n'
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

verified=0
skipped_checkout=0
total_checkout=0
for path in "${server_files[@]}"; do
	if config ls-tree -r --name-only HEAD | grep -qx "$path"; then
		((total_checkout++)) || true
		if config checkout HEAD -- "$path" 2>/dev/null; then
			((verified++)) || true
		else
			((skipped_checkout++)) || true
		fi
	fi
done

# Rollback function for checkout failures
rollback_from_backup() {
	if [ -z "${backup_dir:-}" ] || [ ! -d "${backup_dir:-}" ]; then
		return
	fi
	printf '\nRolling back: restoring files from backup...\n' >&2
	for path in "${to_backup_files[@]}"; do
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

if (( skipped_checkout > 0 && total_checkout > 0 && skipped_checkout * 2 > total_checkout )); then
	printf '\nERROR: %d/%d files failed to checkout. Rolling back...\n' "$skipped_checkout" "$total_checkout" >&2
	rollback_from_backup
	exit 1
fi

printf 'Verified %d server config files.\n' "$verified"
if ((skipped_checkout > 0)); then
	printf 'Skipped (checkout failed): %d files\n' "$skipped_checkout"
fi

# Configure to hide untracked files
config config status.showUntrackedFiles no

# Record checkout state
state_file="$HOME/.cfg-checkout-state"
> "$state_file"
while IFS= read -r path; do
	hash=$(config show HEAD:"$path" | md5sum | cut -d' ' -f1)
	echo "$path:$hash" >> "$state_file"
done < <(config ls-tree -r --name-only HEAD)

removed_total=$((${#to_remove_symlinks[@]} + ${#to_remove_regular[@]} + ${#to_remove_dirs[@]}))

printf '\n=== Server Mode Restoration Complete ===\n'
printf 'Desktop symlinks removed: %d\n' "$removed_total"
printf 'Server configs verified: %d\n' "$verified"
if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
	printf 'Backed up: %d files to %s\n' "${#to_backup_files[@]}" "$backup_dir"
fi
printf '\nTo restore full desktop mode, run: ~/.local/bin/restore-desktop.sh\n'
