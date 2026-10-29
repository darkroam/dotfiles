#!/usr/bin/env bash
# utils/backup.sh - Backup creation with manifest for dotfiles commands
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_BACKUP_LOADED:-}" ]; then
	return 0
fi
_CFG_BACKUP_LOADED=1

CFG_BACKUP_DIR=""

# cfg_create_backup_dir <from_state> <to_state> <timestamp> [backup_root]
# Creates a private transition backup directory and its manifest.
cfg_create_backup_dir() {
	local from_state="$1"
	local to_state="$2"
	local timestamp="$3"
	local backup_root="${4:-$HOME/.config-backup}"

	CFG_BACKUP_DIR="$backup_root/${from_state}-to-${to_state}-${timestamp}"

	if [ -L "$CFG_BACKUP_DIR" ] || { [ -e "$CFG_BACKUP_DIR" ] && [ ! -d "$CFG_BACKUP_DIR" ]; }; then
		printf 'Backup path must be a real directory: %s\n' "$CFG_BACKUP_DIR" >&2
		return 1
	fi

	mkdir -p -- "$CFG_BACKUP_DIR"
	chmod 700 "$CFG_BACKUP_DIR"

	local manifest="$CFG_BACKUP_DIR/MANIFEST.txt"
	printf '# Created: %s\n' "$(date)" > "$manifest"
	printf '# Transition: %s -> %s\n' "$from_state" "$to_state" >> "$manifest"
	printf '#\n# relative_path\tmd5\tstatus\n' >> "$manifest"
}

# cfg_backup_file <relative_path> <git_dir> [backup_dir]
# Moves one existing home file into the transition backup and records it.
cfg_backup_file() {
	local relative_path="$1"
	local git_dir="$2"
	local backup_dir="${3:-$CFG_BACKUP_DIR}"

	local source_path="$HOME/$relative_path"
	local backup_path="$backup_dir/$relative_path"

	[ -e "$source_path" ] || [ -L "$source_path" ] || return 1

	mkdir -p -- "$(dirname "$backup_path")"

	local status="untracked"
	if git --git-dir="$git_dir/" --work-tree="$HOME" ls-tree -r --name-only HEAD 2>/dev/null | grep -qx "$relative_path"; then
		status="modified"
	fi

	local md5
	md5=$(cfg_path_md5 "$source_path")

	mv -- "$source_path" "$backup_path"
	printf '%s\t%s\t%s\n' "$relative_path" "$md5" "$status" >> "$backup_dir/MANIFEST.txt"
}

# cfg_backup_files <git_dir> <relative_path...>
# Backs up a list of transition files using CFG_BACKUP_DIR.
cfg_backup_files() {
	local git_dir="$1"
	shift
	local files=("$@")
	local backup_dir="${CFG_BACKUP_DIR}"

	if [ ${#files[@]} -eq 0 ]; then
		return 0
	fi

	printf '\nBacking up %d files...\n' "${#files[@]}"
	local path
	for path in "${files[@]}"; do
		cfg_backup_file "$path" "$git_dir" "$backup_dir"
		printf 'Backed up: %s\n' "$path"
	done

	printf '\nBackup directory: %s\n' "$backup_dir"
	printf 'Manifest: %s/MANIFEST.txt\n' "$backup_dir"
}

# cfg_create_node_backup_dir <node_code> [backup_root]
# Initializes the backup area and manifest for a node.
cfg_create_node_backup_dir() {
	local node_code="$1"
	local backup_root="${2:-$HOME/.config-backup}"
	local node_dir="$backup_root/nodes/$node_code"

	CFG_BACKUP_DIR="$node_dir/backup"

	if [ ! -d "$node_dir" ]; then
		printf 'Node directory not found: %s\n' "$node_dir" >&2
		return 1
	fi

	mkdir -p -- "$CFG_BACKUP_DIR"

	local manifest="$node_dir/manifest.txt"
	printf '# Node: %s\n' "$node_code" > "$manifest"
	printf '# Created: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%S')" >> "$manifest"
	printf '#\n# relative_path\tmd5\tstatus\n' >> "$manifest"
}

# cfg_backup_file_to_node <relative_path> <git_dir> <node_code> [backup_root]
# Moves one home file into a node backup and records its status.
cfg_backup_file_to_node() {
	local relative_path="$1"
	local git_dir="$2"
	local node_code="$3"
	local backup_root="${4:-$HOME/.config-backup}"
	local backup_dir="$backup_root/nodes/$node_code/backup"
	local manifest="$backup_root/nodes/$node_code/manifest.txt"

	local source_path="$HOME/$relative_path"
	local backup_path="$backup_dir/$relative_path"

	[ -e "$source_path" ] || [ -L "$source_path" ] || return 1

	mkdir -p -- "$(dirname "$backup_path")"

	local status="untracked"
	if git --git-dir="$git_dir/" --work-tree="$HOME" ls-tree -r --name-only HEAD 2>/dev/null | grep -qx "$relative_path"; then
		status="modified"
	fi

	local md5
	md5=$(cfg_path_md5 "$source_path")

	mv -- "$source_path" "$backup_path"
	printf '%s\t%s\t%s\n' "$relative_path" "$md5" "$status" >> "$manifest"
}

# cfg_backup_files_to_node <git_dir> <node_code> [backup_root] <path...>
# Backs up all supplied files into a node backup.
cfg_backup_files_to_node() {
	local git_dir="$1"
	local node_code="$2"
	local backup_root="${3:-$HOME/.config-backup}"
	shift 3
	local files=("$@")
	local backup_dir="$backup_root/nodes/$node_code/backup"

	if [ ${#files[@]} -eq 0 ]; then
		return 0
	fi

	printf '\nBacking up %d files to node %s...\n' "${#files[@]}" "$node_code"
	local path
	for path in "${files[@]}"; do
		cfg_backup_file_to_node "$path" "$git_dir" "$node_code" "$backup_root"
		printf 'Backed up: %s\n' "$path"
	done
}
