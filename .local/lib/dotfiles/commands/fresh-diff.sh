#!/usr/bin/env bash
# commands/fresh-diff.sh - Compare current system files with fresh backup
# Usage: fresh-diff.sh [path] [--summary]
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

SUMMARY=false
target=""
for arg in "$@"; do
	case "$arg" in
		--summary) SUMMARY=true ;;
		--*) printf 'Error: unknown option: %s\n' "$arg" >&2; exit 1 ;;
		*) target="${arg#./}" ;;
	esac
done

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
cfg_nodes_init "$backup_root"

root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
if [ -z "$root_code" ]; then
	printf 'Error: fresh root node not found. Run "dotcfg doctor" to check the system.\n' >&2
	exit 1
fi

if ! fresh_manifest_read "$root_code"; then
	printf 'Error: fresh node has no manifest.\n' >&2
	exit 1
fi

# Single-file mode: show unified diff
if [ -n "$target" ]; then
	backup_file="$CFG_NODES_DIR/$root_code/backup/$target"
	if ! fresh_manifest_has "$target"; then
		printf 'Error: %s is not in fresh node backup.\n' "$target" >&2
		exit 1
	fi
	current_file="$HOME/$target"
	if [ ! -f "$current_file" ] && [ ! -L "$current_file" ]; then
		printf '%s: missing in current system (exists in fresh backup)\n' "$target"
		exit 0
	fi
	if [ -L "$backup_file" ] || [ -L "$current_file" ]; then
		fresh_link="regular file"
		current_link="regular file"
		[ -L "$backup_file" ] && fresh_link=$(readlink -- "$backup_file")
		[ -L "$current_file" ] && current_link=$(readlink -- "$current_file")
		if [ -L "$backup_file" ] && [ -L "$current_file" ] && [ "$fresh_link" = "$current_link" ]; then
			printf '%s: identical symbolic link (%s)\n' "$target" "$current_link"
		else
			printf '%s: symbolic link differs\n' "$target"
			printf '  fresh:   %s\n' "$fresh_link"
			printf '  current: %s\n' "$current_link"
		fi
		exit 0
	fi
	if diff -u --label "fresh:$target" --label "current:$target" "$backup_file" "$current_file"; then
		printf '%s: identical\n' "$target"
	fi
	exit 0
fi

printf 'Comparing fresh backup with current system files...\n\n'

modified=()
missing=()
for ((i = 0; i < ${#_FRESH_MANIFEST_PATHS[@]}; i++)); do
	path="${_FRESH_MANIFEST_PATHS[$i]}"
	fresh_md5="${_FRESH_MANIFEST_MD5S[$i]}"
	if [ ! -f "$HOME/$path" ] && [ ! -L "$HOME/$path" ]; then
		missing+=("$path")
		continue
	fi
	current_md5=$(cfg_path_md5 "$HOME/$path" 2>/dev/null) || current_md5=""
	if [ "$current_md5" != "$fresh_md5" ]; then
		modified+=("$path")
	fi
done

# New files: exist in the mixed-mode selection but not in fresh.
new_files=()
fresh_collect_backup_files "${DOTCFG_GIT_DIR:-$HOME/.cfg}"
for path in "${_FRESH_BACKUP_FILES[@]}"; do
	[ -n "$path" ] || continue
	fresh_manifest_has "$path" && continue
	new_files+=("$path")
	[ ${#new_files[@]} -ge 50 ] && break
done

printf 'Modified files (%d):\n' "${#modified[@]}"
if ! $SUMMARY; then
	for path in "${modified[@]}"; do
		fresh_md5=""
		for ((i = 0; i < ${#_FRESH_MANIFEST_PATHS[@]}; i++)); do
			if [ "${_FRESH_MANIFEST_PATHS[$i]}" = "$path" ]; then
				fresh_md5="${_FRESH_MANIFEST_MD5S[$i]}"
				break
			fi
		done
		current_md5=$(cfg_path_md5 "$HOME/$path" 2>/dev/null) || current_md5=""
		printf '  %s: MD5 mismatch (fresh: %s... vs current: %s...)\n' \
			"$path" "${fresh_md5:0:7}" "${current_md5:0:7}"
	done
fi

printf '\nNew files (%d) - exist in system but not in fresh:\n' "${#new_files[@]}"
if ! $SUMMARY; then
	for path in "${new_files[@]}"; do
		size=$(cfg_path_size "$HOME/$path" 2>/dev/null) || size=0
		printf '  %s (%s)\n' "$path" "$(fresh_format_size "${size:-0}")"
	done
fi

printf '\nMissing files (%d) - exist in fresh but not in system:\n' "${#missing[@]}"
if ! $SUMMARY; then
	for path in "${missing[@]}"; do
		printf '  %s\n' "$path"
	done
fi

if [ ${#modified[@]} -eq 0 ] && [ ${#new_files[@]} -eq 0 ] && [ ${#missing[@]} -eq 0 ]; then
	printf '\nSystem matches fresh backup.\n'
fi
