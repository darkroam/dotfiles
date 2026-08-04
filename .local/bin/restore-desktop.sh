#!/usr/bin/env bash

# restore-desktop.sh - Restore full desktop configuration from server mode
# Usage: restore-desktop.sh [--dry-run] [--auto-stash]

set -euo pipefail

# Parse arguments
DRY_RUN=false
AUTO_STASH=false
for arg in "$@"; do
	case $arg in
		--dry-run) DRY_RUN=true ;;
		--auto-stash) AUTO_STASH=true ;;
	esac
done

git_dir=$HOME/.cfg
timestamp=$(date +%Y%m%dT%H%M%S)
backup_dir=""

# Source shared validation library
DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/share/dotfiles-lib}"
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
		printf 'Bare repository not found at %s. Run install.sh or install-server.sh first.\n' "$git_dir" >&2
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
target_state="desktop"

# Analyze what will change
printf 'Analyzing current state...\n'

# Get list of all tracked files
mapfile -t tracked_files < <(config ls-tree -r --name-only HEAD)

to_add=()
to_backup_conflicts=()
to_skip=()

for path in "${tracked_files[@]}"; do
	full_path="$HOME/$path"

	if [ ! -e "$full_path" ] && [ ! -L "$full_path" ]; then
		to_add+=("$path")
	elif cfg_should_backup_file "$git_dir" "$path"; then
		to_backup_conflicts+=("$path")
	else
		to_skip+=("$path")
	fi
done

# Determine backup directory name
if ((${#to_backup_conflicts[@]} > 0)); then
	backup_dir="$HOME/.config-backup-${current_state}-to-${target_state}-${timestamp}"
fi

# Print analysis report
printf '\n=== Restoration Analysis ===\n\n'
printf 'Current state: %s\n' "$current_state"
printf 'Target state: %s\n' "$target_state"
if [ -n "$backup_dir" ]; then
	printf 'Backup directory: %s\n' "$backup_dir"
fi

printf '\nNew files to add: %d\n' "${#to_add[@]}"
printf 'Files to skip (identical to repo): %d\n' "${#to_skip[@]}"
printf 'Conflicting files (modified/untracked): %d\n' "${#to_backup_conflicts[@]}"

if ((${#to_backup_conflicts[@]} > 0)); then
	printf '\nConflicting files:\n'
	for path in "${to_backup_conflicts[@]}"; do
		status="untracked"
		if config ls-tree -r --name-only HEAD | grep -qx "$path"; then
			status="modified"
		fi
		printf '  ~ %s (%s)\n' "$path" "$status"
	done

	if [ "$AUTO_STASH" = false ]; then
		printf '\nThese files have local modifications and will be backed up before restoration.\n'
		printf 'To skip backup and overwrite directly, use --auto-stash flag.\n'
	fi
fi

if [ "$DRY_RUN" = true ]; then
	printf '\n=== DRY RUN MODE - No changes will be made ===\n'
	exit 0
fi

printf '\nWARNING: This will checkout ALL tracked configurations, including:\n'
printf '  - X11 session configs (xprofile, xinitrc)\n'
printf '  - Audio configs (ALSA, MPD)\n'
printf '  - Graphical tool configs (nsxiv, zathura)\n'
printf '  - Display management scripts\n'
printf '\nExisting files without local modifications will be overwritten.\n\n'

printf 'Proceed with full desktop restoration? [y/N] '
read -r confirm
if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
	printf 'Aborted.\n'
	exit 0
fi

# Backup conflicting files before checkout
if ((${#to_backup_conflicts[@]} > 0)); then
	if [ "$AUTO_STASH" = true ]; then
		printf '\n--auto-stash: removing %d conflicting files without backup...\n' "${#to_backup_conflicts[@]}"
		for path in "${to_backup_conflicts[@]}"; do
			rm -f -- "$HOME/$path"
			printf 'Removed: %s\n' "$path"
		done
	else
		if [ -L "$backup_dir" ] || { [ -e "$backup_dir" ] && [ ! -d "$backup_dir" ]; }; then
			printf 'Backup root must be a real directory: %s\n' "$backup_dir" >&2
			exit 1
		fi

		mkdir -p -- "$backup_dir"
		chmod 700 "$backup_dir"

		# Create manifest
		manifest="$backup_dir/MANIFEST.txt"
		printf '# Backup manifest created at %s\n' "$(date)" > "$manifest"
		printf '# State transition: %s -> %s\n' "$current_state" "$target_state" >> "$manifest"
		printf '# Format: original_path -> backup_path (status)\n\n' >> "$manifest"

		printf '\nBacking up %d files...\n' "${#to_backup_conflicts[@]}"
		for path in "${to_backup_conflicts[@]}"; do
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
fi

printf '\nRestoring full desktop configuration...\n'

# Rollback function for checkout failures
rollback_from_backup() {
	if [ -z "${backup_dir:-}" ] || [ ! -d "${backup_dir:-}" ]; then
		return
	fi
	printf '\nRolling back: restoring files from backup...\n' >&2
	for path in "${to_backup_conflicts[@]}"; do
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

# Checkout all tracked files
checkout_success=true
failed_files=()
total_checkout=$((${#to_add[@]} + ${#to_skip[@]}))
for path in "${to_add[@]}" "${to_skip[@]}"; do
	if ! config checkout HEAD -- "$path" 2>/dev/null; then
		failed_files+=("$path")
		checkout_success=false
	fi
done

if [ "$checkout_success" = true ]; then
	printf '\nAll configurations restored successfully.\n'
elif (( ${#failed_files[@]} * 2 > total_checkout && total_checkout > 0 )); then
	printf '\nERROR: %d/%d files failed to checkout. Rolling back...\n' "${#failed_files[@]}" "$total_checkout" >&2
	rollback_from_backup
	exit 1
else
	printf '\nWarning: %d files failed to checkout:\n' "${#failed_files[@]}"
	for path in "${failed_files[@]}"; do
		printf '  ! %s\n' "$path"
	done >&2
fi

# Ensure untracked files are hidden in git status
config config status.showUntrackedFiles no

# Record checkout state
state_file="$HOME/.cfg-checkout-state"
> "$state_file"
while IFS= read -r path; do
	hash=$(config show HEAD:"$path" | md5sum | cut -d' ' -f1)
	echo "$path:$hash" >> "$state_file"
done < <(config ls-tree -r --name-only HEAD)

printf '\n=== Desktop Restoration Complete ===\n'
printf 'New files added: %d\n' "${#to_add[@]}"
printf 'Files skipped (identical): %d\n' "${#to_skip[@]}"
if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
	printf 'Backed up: %d files to %s\n' "${#to_backup_conflicts[@]}" "$backup_dir"
fi
printf '\nAll tracked configurations are now active in %s.\n' "$HOME"
printf '\nYou may need to:\n'
printf '  - Restart your shell or run: source ~/.profile\n'
printf '  - Restart X11 session if switching from SSH-only use\n'
printf '  - Install desktop dependencies: see .local/share/docs/project/dependencies.md\n'
