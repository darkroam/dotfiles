#!/usr/bin/env bash
# utils/fresh.sh - Fresh root node management (full $HOME backup anchor)
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_FRESH_LOADED:-}" ]; then
	return 0
fi
_CFG_FRESH_LOADED=1

FRESH_ROOT_CODE="fresh_root"
FRESH_BOOTSTRAP_VERSION="bootstrap"

# Fresh manifest arrays (populated by fresh_manifest_read)
_FRESH_MANIFEST_PATHS=()
_FRESH_MANIFEST_MD5S=()
_FRESH_MANIFEST_SIZES=()
_FRESH_MANIFEST_STATUSES=()
_FRESH_MANIFEST_TIMES=()

# fresh_get_root_code
# Prints the root node CODE. Prefers the fixed fresh_root code; falls back
# to cfg_nodes_get_root for installations created with random codes.
fresh_get_root_code() {
	if cfg_node_exists "$FRESH_ROOT_CODE" 2>/dev/null; then
		printf '%s' "$FRESH_ROOT_CODE"
		return 0
	fi
	local root
	root=$(cfg_nodes_get_root 2>/dev/null) || return 1
	[ -n "$root" ] || return 1
	printf '%s' "$root"
}

# fresh_manifest_file [root_code]
fresh_manifest_file() {
	local code="${1:-$(fresh_get_root_code)}"
	printf '%s' "$CFG_NODES_DIR/$code/manifest.txt"
}

# fresh_manifest_read [root_code]
# Parses the fresh manifest into _FRESH_MANIFEST_* arrays.
fresh_manifest_read() {
	local code="${1:-$(fresh_get_root_code)}"
	local manifest="$CFG_NODES_DIR/$code/manifest.txt"

	_FRESH_MANIFEST_PATHS=()
	_FRESH_MANIFEST_MD5S=()
	_FRESH_MANIFEST_SIZES=()
	_FRESH_MANIFEST_STATUSES=()
	_FRESH_MANIFEST_TIMES=()

	[ -f "$manifest" ] || return 1

	local line path md5 size status ts
	while IFS=$'\t' read -r path md5 size status ts; do
		[[ "$path" == \#* ]] && continue
		[ -z "$path" ] && continue
		_FRESH_MANIFEST_PATHS+=("$path")
		_FRESH_MANIFEST_MD5S+=("$md5")
		_FRESH_MANIFEST_SIZES+=("$size")
		_FRESH_MANIFEST_STATUSES+=("$status")
		_FRESH_MANIFEST_TIMES+=("${ts:-}")
	done < "$manifest"
	return 0
}

# fresh_manifest_has <relpath>
fresh_manifest_has() {
	local target="$1"
	local i
	for ((i = 0; i < ${#_FRESH_MANIFEST_PATHS[@]}; i++)); do
		[ "${_FRESH_MANIFEST_PATHS[$i]}" = "$target" ] && return 0
	done
	return 1
}

# fresh_backup_count / fresh_backup_size
fresh_backup_count() {
	printf '%s' "${#_FRESH_MANIFEST_PATHS[@]}"
}

fresh_backup_size() {
	local total=0 s
	for s in "${_FRESH_MANIFEST_SIZES[@]}"; do
		[[ "$s" =~ ^[0-9]+$ ]] && total=$((total + s))
	done
	printf '%s' "$total"
}

# fresh_format_size <bytes>
fresh_format_size() {
	local bytes="$1"
	if (( bytes >= 1048576 )); then
		awk -v b="$bytes" 'BEGIN { printf "%.1f MB", b / 1048576 }'
	elif (( bytes >= 1024 )); then
		awk -v b="$bytes" 'BEGIN { printf "%.1f KB", b / 1024 }'
	else
		printf '%s B' "$bytes"
	fi
}

# fresh_manifest_write_header [root_code]
fresh_manifest_write_header() {
	local code="${1:-$FRESH_ROOT_CODE}"
	local manifest="$CFG_NODES_DIR/$code/manifest.txt"
	{
		printf '# Created: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%S')"
		printf '# Node: %s\n' "$code"
		printf '# Type: fresh (root node)\n'
		printf '#\n'
		printf '# Format: relative_path\\tmd5\\tsize_bytes\\tstatus[\\ttimestamp]\n'
	} > "$manifest"
}

# fresh_copy_to_backup <relpath> <status> [timestamp]
# Copies $HOME/<relpath> into the fresh backup dir (cp semantics, original
# file untouched) and appends a manifest entry.
fresh_copy_to_backup() {
	local relpath="$1"
	local status="${2:-tracked_by_user}"
	local ts="${3:-$(date -u '+%Y-%m-%dT%H:%M:%S')}"

	local root_code
	root_code=$(fresh_get_root_code) || return 1

	local source="$HOME/$relpath"
	local backup_dir="$CFG_NODES_DIR/$root_code/backup"
	local dest="$backup_dir/$relpath"
	local manifest="$CFG_NODES_DIR/$root_code/manifest.txt"

	[ -f "$source" ] || [ -L "$source" ] || return 1

	mkdir -p -- "$(dirname "$dest")"
	cp -p -- "$source" "$dest" 2>/dev/null || cp -- "$source" "$dest"

	local md5 size
	md5=$(md5sum < "$source" 2>/dev/null | cut -d' ' -f1)
	size=$(wc -c < "$source" 2>/dev/null | tr -d ' ')

	if [ -n "$ts" ]; then
		printf '%s\t%s\t%s\t%s\t%s\n' "$relpath" "$md5" "$size" "$status" "$ts" >> "$manifest"
	else
		printf '%s\t%s\t%s\t%s\n' "$relpath" "$md5" "$size" "$status" >> "$manifest"
	fi
	return 0
}

# fresh_remove_from_backup <relpath>
# Removes the backup file and rewrites the manifest without the entry.
fresh_remove_from_backup() {
	local relpath="$1"

	local root_code
	root_code=$(fresh_get_root_code) || return 1

	local backup_path="$CFG_NODES_DIR/$root_code/backup/$relpath"
	local manifest="$CFG_NODES_DIR/$root_code/manifest.txt"

	fresh_manifest_read "$root_code" || return 1
	fresh_manifest_has "$relpath" || return 1

	rm -f -- "$backup_path"

	local tmp="${manifest}.tmp"
	local i
	{
		printf '# Created: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%S')"
		printf '# Node: %s\n' "$root_code"
		printf '# Type: fresh (root node)\n'
		printf '#\n'
		printf '# Format: relative_path\\tmd5\\tsize_bytes\\tstatus[\\ttimestamp]\n'
		for ((i = 0; i < ${#_FRESH_MANIFEST_PATHS[@]}; i++)); do
			[ "${_FRESH_MANIFEST_PATHS[$i]}" = "$relpath" ] && continue
			printf '%s\t%s\t%s\t%s' \
				"${_FRESH_MANIFEST_PATHS[$i]}" "${_FRESH_MANIFEST_MD5S[$i]}" \
				"${_FRESH_MANIFEST_SIZES[$i]}" "${_FRESH_MANIFEST_STATUSES[$i]}"
			[ -n "${_FRESH_MANIFEST_TIMES[$i]}" ] && printf '\t%s' "${_FRESH_MANIFEST_TIMES[$i]}"
			printf '\n'
		done
	} > "$tmp"
	mv -- "$tmp" "$manifest"
	return 0
}

# fresh_create_root_backup [--dry-run]
# Full scan of $HOME (exclusion rules applied), copies files into the fresh
# root node backup and creates the node entry with config_version=bootstrap.
fresh_create_root_backup() {
	local dry_run=false
	[ "${1:-}" = "--dry-run" ] && dry_run=true

	if [ -z "${CFG_NODES_DIR:-}" ]; then
		cfg_nodes_init "${CFG_BACKUP_ROOT:-$HOME/.config-backup}" 2>/dev/null || true
	fi

	local files=()
	local f
	while IFS= read -r f; do
		[ -n "$f" ] && files+=("$f")
	done < <(fresh_scan_home)

	if $dry_run; then
		printf 'Would back up %d files to nodes/%s/backup/\n' "${#files[@]}" "$FRESH_ROOT_CODE"
		for f in "${files[@]}"; do
			printf '  %s\n' "$f"
		done
		return 0
	fi

	# Create the root node with the fixed code (reuse existing root if any)
	local code
	code=$(fresh_get_root_code 2>/dev/null) || code=""
	if [ -z "$code" ]; then
		code=$(cfg_node_create "fresh" "null" "$FRESH_BOOTSTRAP_VERSION" "$FRESH_ROOT_CODE") || return 1
	fi

	local backup_dir="$CFG_NODES_DIR/$code/backup"
	mkdir -p "$backup_dir"
	chmod 700 "$backup_dir" 2>/dev/null || true

	fresh_manifest_write_header "$code"

	local count=0
	for f in "${files[@]}"; do
		if fresh_copy_to_backup "$f" "tracked_at_install" ""; then
			count=$((count + 1))
		fi
	done

	printf 'Fresh node created: %s (%d files backed up)\n' "$code" "$count"
	return 0
}
