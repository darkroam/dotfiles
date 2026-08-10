#!/usr/bin/env bash

# uninstall.sh - Remove dotfiles repository and restore backed up configs
# Usage: uninstall.sh [--dry-run] [--latest] [--clean-backups]

set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

cfg_parse_common_args "$@"

git_dir=$HOME/.cfg
backup_root="$HOME/.config-backup"
state_file="$HOME/.cfg-checkout-state"

is_installation_file() {
	local path="$1"
	case "$path" in
		.local/bin/dotcfg|\
		.local/lib/dotfiles/*)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

# ── Validate repository ─────────────────────────────────────────────────
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
		;;
esac

printf '=== Dotfiles Uninstallation ===\n\n'
printf 'This will:\n'
printf '  1. Remove user configuration files (preserves installation infrastructure)\n'
if [ "$CFG_LATEST" = true ]; then
	printf '  2. Restore backed up configs (latest version from backup chain)\n'
else
	printf '  2. Restore backed up configs (original version from backup chain)\n'
fi
printf '  3. Print manual cleanup instructions for complete removal\n'
printf '\nInstallation files (scripts, libraries, docs) will be preserved.\n'

# Check if repository exists
if [ ! -d "$git_dir" ] && [ ! -L "$git_dir" ]; then
	printf '\nRepository not found at %s. Nothing to uninstall.\n' "$git_dir" >&2
	exit 1
fi

# Get list of managed files
all_tracked_files=()
if [ -f "$state_file" ]; then
	while IFS=: read -r path _hash; do
		all_tracked_files+=("$path")
	done < "$state_file"
	printf '\nFound %d tracked files in checkout state.\n' "${#all_tracked_files[@]}"
elif [ -d "$git_dir" ]; then
	mapfile -t all_tracked_files < <(git --git-dir="$git_dir/" --work-tree="$HOME" ls-tree -r --name-only HEAD 2>/dev/null || true)
	printf '\nFound %d tracked files in repository.\n' "${#all_tracked_files[@]}"
else
	printf '\nNo checkout state or repository found. Nothing to remove.\n'
fi

# Filter out installation files
files_to_remove=()
installation_files_preserved=()
for path in "${all_tracked_files[@]}"; do
	if is_installation_file "$path"; then
		installation_files_preserved+=("$path")
	else
		files_to_remove+=("$path")
	fi
done

if ((${#installation_files_preserved[@]} > 0)); then
	printf 'Preserving %d installation infrastructure file(s).\n' "${#installation_files_preserved[@]}"
fi

# ── Fresh root node detection ───────────────────────────────────────────
cfg_nodes_init "$backup_root"
fresh_root_code=""
fresh_root_backup=""
if [ -d "$backup_root/nodes" ]; then
	fresh_root_code=$(fresh_get_root_code 2>/dev/null) || fresh_root_code=""
	if [ -n "$fresh_root_code" ] && [ -d "$backup_root/nodes/$fresh_root_code/backup" ]; then
		fresh_root_backup="$backup_root/nodes/$fresh_root_code/backup"
	fi
fi

declare -A fresh_in_manifest=()
declare -A fresh_md5_map=()
if [ -n "$fresh_root_backup" ]; then
	if fresh_manifest_read "$fresh_root_code" 2>/dev/null; then
		for ((i = 0; i < ${#_FRESH_MANIFEST_PATHS[@]}; i++)); do
			fresh_in_manifest["${_FRESH_MANIFEST_PATHS[$i]}"]=1
			fresh_md5_map["${_FRESH_MANIFEST_PATHS[$i]}"]="${_FRESH_MANIFEST_MD5S[$i]}"
		done
		printf 'Fresh root backup found: %s (%d files)\n' "$fresh_root_code" "${#_FRESH_MANIFEST_PATHS[@]}"
	fi
fi

# ── Scan backup chain ───────────────────────────────────────────────────
declare -A file_backup_sessions

backup_session_count=0
if [ -d "$backup_root" ]; then
	list_all_sessions() {
		local session_dir basename timestamp
		for session_dir in "$backup_root"/*/; do
			[ -d "$session_dir" ] || continue
			basename=$(basename "$session_dir")
			case "$basename" in
				nodes|sessions) continue ;;
			esac
			if [[ "$basename" =~ -([0-9]{8}T[0-9]{6})$ ]]; then
				timestamp="${BASH_REMATCH[1]}"
				printf '%s\t%s\n' "$timestamp" "$session_dir"
			else
				local mtime
				mtime=$(stat -c '%Y' "$session_dir" 2>/dev/null || stat -f '%m' "$session_dir" 2>/dev/null)
				timestamp=$(date -d "@$mtime" '+%Y%m%dT%H%M%S' 2>/dev/null || date -r "$mtime" '+%Y%m%dT%H%M%S' 2>/dev/null)
				printf '%s\t%s\n' "$timestamp" "$session_dir"
			fi
		done

		if [ -d "$backup_root/nodes" ]; then
			for node_dir in "$backup_root/nodes"/*/; do
				[ -d "$node_dir" ] || continue
				[ -f "$node_dir/manifest.txt" ] || continue
				local ts=""
				ts=$(grep '^# Created:' "$node_dir/manifest.txt" 2>/dev/null | head -1 | sed 's/.*: //')
				if [ -z "$ts" ]; then
					ts=$(stat -c '%Y' "$node_dir" 2>/dev/null || stat -f '%m' "$node_dir" 2>/dev/null)
					ts=$(date -d "@$ts" '+%Y%m%dT%H%M%S' 2>/dev/null || echo "00000000T000000")
				else
					ts=$(date -d "$ts" '+%Y%m%dT%H%M%S' 2>/dev/null || echo "00000000T000000")
				fi
				printf '%s\t%s\n' "$ts" "$node_dir"
			done
		fi
	}

	while IFS= read -r session_dir; do
		[ -n "$session_dir" ] || continue
		((backup_session_count++)) || true
		manifest=""
		if [ -f "$session_dir/MANIFEST.txt" ]; then
			manifest="$session_dir/MANIFEST.txt"
		elif [ -f "$session_dir/manifest.txt" ]; then
			manifest="$session_dir/manifest.txt"
		fi
		if [ -n "$manifest" ]; then
			while IFS=$'\t' read -r rel_path md5 status; do
				[[ "$rel_path" =~ ^#.*$ ]] && continue
				[[ -z "$rel_path" ]] && continue

				if [ -n "${file_backup_sessions[$rel_path]+x}" ]; then
					file_backup_sessions[$rel_path]+=$'\n'"$session_dir"
				else
					file_backup_sessions[$rel_path]="$session_dir"
				fi
			done < "$manifest"
		fi
	done < <(list_all_sessions | sort -t$'\t' -k1,1 -k2,2 | cut -f2-)
fi

printf '\nFound %d backup session(s) in %s.\n' "$backup_session_count" "$backup_root"

# ── Determine restore targets ───────────────────────────────────────────
declare -A file_restore_session
restorable_count=0
not_in_backup=()

for path in "${files_to_remove[@]}"; do
	if [ "$CFG_LATEST" != true ] && [ -n "$fresh_root_backup" ] && [ -n "${fresh_in_manifest[$path]+x}" ] && \
	   { [ -f "$fresh_root_backup/$path" ] || [ -L "$fresh_root_backup/$path" ]; }; then
		file_restore_session[$path]="$backup_root/nodes/$fresh_root_code"
		((restorable_count++)) || true
	elif [ -n "${file_backup_sessions[$path]+x}" ]; then
		if [ "$CFG_LATEST" = true ]; then
			file_restore_session[$path]=$(printf '%s' "${file_backup_sessions[$path]}" | tail -1)
		else
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

# ── Fresh backup pre-check warnings ─────────────────────────────────────
deleted_no_fresh=()
restore_changed=()
for path in "${files_to_remove[@]}"; do
	if [ -z "${fresh_in_manifest[$path]+x}" ]; then
		if [ -z "${file_backup_sessions[$path]+x}" ] && { [ -e "$HOME/$path" ] || [ -L "$HOME/$path" ]; }; then
			deleted_no_fresh+=("$path")
		fi
	elif [ -e "$HOME/$path" ] || [ -L "$HOME/$path" ]; then
		cur_md5=$(cfg_path_md5 "$HOME/$path" 2>/dev/null) || cur_md5=""
		if [ -n "$cur_md5" ] && [ "$cur_md5" != "${fresh_md5_map[$path]}" ]; then
			restore_changed+=("$path")
		fi
	fi
done

if [ -n "$fresh_root_backup" ]; then
	if ((${#deleted_no_fresh[@]} > 0)); then
		printf '\nWARNING: the following files will be DELETED and are NOT in the fresh backup:\n'
		for path in "${deleted_no_fresh[@]}"; do
			printf '  ! %s\n' "$path"
		done
		printf 'Run "dotcfg track <file>" first if you want to preserve them.\n'
	fi
	if ((${#restore_changed[@]} > 0)); then
		printf '\nThe following files differ from the fresh backup and will be RESTORED to their pre-install state:\n'
		for path in "${restore_changed[@]}"; do
			printf '  ~ %s\n' "$path"
		done
	fi
fi

if [ "$CFG_DRY_RUN" = true ]; then
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
	printf '\nInstallation infrastructure files would be preserved:\n'
	for path in "${installation_files_preserved[@]}"; do
		printf '  = %s\n' "$path"
	done
	printf '\nNote: Repository and backups will NOT be automatically removed.\n'

	# Show backup directory size in dry-run mode
	if [ -d "$backup_root" ]; then
		backup_size=$(du -sh "$backup_root" 2>/dev/null | cut -f1)
		printf '\nBackup directory size: %s (%s)\n' "$backup_size" "$backup_root"
		printf 'To clean up: rm -rf %s\n' "$backup_root"
	fi
	exit 0
fi

# Confirm removal
if [ "$CFG_FORCE" != true ]; then
	printf '\nProceed with uninstallation? [y/N] '
	read -r confirm
	if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
		printf 'Aborted.\n'
		exit 0
	fi
fi

# ── Step 1: Remove managed files ────────────────────────────────────────
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

if [ -f "$state_file" ]; then
	rm -f -- "$state_file"
	printf 'Removed checkout state file.\n'
fi

# ── Step 2: Restore from backup chain ───────────────────────────────────
restored=0
failed=0
if ((restorable_count > 0)); then
	printf '\n=== Step 2: Restoring from backup chain ===\n'
	restored=0
	failed=0

	for path in "${!file_restore_session[@]}"; do
		session_dir="${file_restore_session[$path]}"
		backup_file=""
		if [ -e "$session_dir/$path" ] || [ -L "$session_dir/$path" ]; then
			backup_file="$session_dir/$path"
		elif [ -e "$session_dir/backup/$path" ] || [ -L "$session_dir/backup/$path" ]; then
			backup_file="$session_dir/backup/$path"
		fi
		target="$HOME/$path"

		if [ -n "$backup_file" ]; then
			mkdir -p "$(dirname "$target")"
			if cp -a -- "$backup_file" "$target"; then
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

# ── Final summary ───────────────────────────────────────────────────────
printf '\n=== Uninstall Complete ===\n'
printf 'Files removed: %d\n' "$removed"
printf 'Files restored from backup: %d\n' "$restored"
printf 'Installation files preserved: %d\n' "${#installation_files_preserved[@]}"

printf '\n=== System State: Fresh ===\n'
printf 'Your system has been restored to a fresh state (as if dotfiles were never installed).\n'
printf 'Installation infrastructure has been preserved for potential re-installation.\n'

if [ -d "$backup_root" ] || [ -d "$git_dir" ]; then
	printf '\n=== Manual Cleanup (Optional) ===\n'
	printf 'To completely remove all traces of the dotfiles system, delete:\n'
	if [ -d "$backup_root" ]; then
		backup_size=$(du -sh "$backup_root" 2>/dev/null | cut -f1)
		printf '  1. Backup directory (%s): rm -rf %s\n' "$backup_size" "$backup_root"
	fi
	if [ -d "$git_dir" ] || [ -L "$git_dir" ]; then
		printf '  2. Repository: rm -rf %s\n' "$git_dir"
	fi
	if ((${#installation_files_preserved[@]} > 0)); then
		printf '  3. Installation scripts and libraries (see list above)\n'
	fi
	printf '\nWARNING: Only delete these if you are certain you will not need to re-install or recover.\n'
	printf 'Keeping them allows you to:\n'
	printf '  - Re-install dotfiles later\n'
	printf '  - View transition history\n'
	printf '  - Recover configurations if needed\n'
fi
