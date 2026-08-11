#!/usr/bin/env bash
# utils/fresh.sh - Fresh root node management (mixed-mode backup anchor)
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_FRESH_LOADED:-}" ]; then
	return 0
fi
_CFG_FRESH_LOADED=1

# Persistent protocol identifiers. Existing node stores and recovery logic
# depend on these values; they are not user policy configuration.
FRESH_ROOT_CODE="fresh_root"
FRESH_BOOTSTRAP_VERSION="bootstrap"

# Fresh manifest arrays (populated by fresh_manifest_read)
_FRESH_MANIFEST_PATHS=()
_FRESH_MANIFEST_MD5S=()
_FRESH_MANIFEST_SIZES=()
_FRESH_MANIFEST_STATUSES=()
_FRESH_MANIFEST_TIMES=()

# Mixed-mode backup selection, populated by fresh_collect_backup_files.
_FRESH_CONFIG_FILES=()
_FRESH_OTHER_TRACKED_FILES=()
_FRESH_LOCAL_TRACKED_FILES=()
_FRESH_BACKUP_FILES=()
_FRESH_BACKED_CONFIG_COUNT=0
_FRESH_BACKED_OTHER_COUNT=0
_FRESH_BACKED_LOCAL_COUNT=0

# Legacy adoption selection, populated by fresh_collect_legacy_adoption_files.
_FRESH_ADOPT_PATHS=()
_FRESH_ADOPT_SOURCES=()
_FRESH_ADOPT_STATUSES=()
_FRESH_ADOPT_LEGACY_COUNT=0
_FRESH_ADOPT_CONFIG_COUNT=0

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

	local path md5 size status ts
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

# fresh_backup_size
# Prints the total byte size recorded in the loaded Fresh manifest.
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
	cp -a -- "$source" "$dest"

	local md5 size
	md5=$(cfg_path_md5 "$source")
	size=$(cfg_path_size "$source")

	if [ -n "$ts" ]; then
		printf '%s\t%s\t%s\t%s\t%s\n' "$relpath" "$md5" "$size" "$status" "$ts" >> "$manifest"
	else
		printf '%s\t%s\t%s\t%s\n' "$relpath" "$md5" "$size" "$status" >> "$manifest"
	fi
	return 0
}

# fresh_copy_source_to_backup <source> <relpath> <status> [timestamp]
# Copies a file from an explicit legacy source rather than from $HOME.
fresh_copy_source_to_backup() {
	local source="$1"
	local relpath="$2"
	local status="$3"
	local ts="${4:-$(date -u '+%Y-%m-%dT%H:%M:%S')}"

	local root_code
	root_code=$(fresh_get_root_code) || return 1
	local backup_dir="$CFG_NODES_DIR/$root_code/backup"
	local dest="$backup_dir/$relpath"
	local manifest="$CFG_NODES_DIR/$root_code/manifest.txt"

	[ -f "$source" ] || [ -L "$source" ] || return 1
	mkdir -p -- "$(dirname "$dest")"
	cp -a -- "$source" "$dest"

	local md5 size
	md5=$(cfg_path_md5 "$source")
	size=$(cfg_path_size "$source")
	printf '%s\t%s\t%s\t%s\t%s\n' "$relpath" "$md5" "$size" "$status" "$ts" >> "$manifest"
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

# fresh_collect_backup_files [git_dir]
# Builds the mixed-mode backup set: all eligible ~/.config files plus tracked
# files elsewhere. Tracked configuration files override exclusion rules, except
# for the installation infrastructure that must never enter fresh_root.
fresh_collect_backup_files() {
	local git_dir="${1:-${GIT_DIR:-${DOTCFG_GIT_DIR:-$HOME/.cfg}}}"
	local -A seen=() tracked=()
	local source rel
	local -a tracked_paths=() config_files=() other_files=() local_files=()

	_FRESH_CONFIG_FILES=()
	_FRESH_OTHER_TRACKED_FILES=()
	_FRESH_LOCAL_TRACKED_FILES=()
	_FRESH_BACKUP_FILES=()

	while IFS= read -r rel; do
		[ -n "$rel" ] || continue
		tracked["$rel"]=1
		tracked_paths+=("$rel")
	done < <(git --git-dir="$git_dir/" ls-tree -r --name-only HEAD 2>/dev/null)

	if [ -d "$HOME/.config" ]; then
		while IFS= read -r -d '' source; do
			rel="${source#"$HOME"/}"
			if fresh_exclude_is_excluded "$rel" && [ -z "${tracked[$rel]+x}" ]; then
				continue
			fi
			seen["$rel"]=1
			config_files+=("$rel")
		done < <(find "$HOME/.config" \( -type f -o -type l \) -print0 2>/dev/null)
	fi

	for rel in "${tracked_paths[@]}"; do
		case "$rel" in
			.local/bin/dotcfg|.local/lib/dotfiles/*) continue ;;
		esac
		source="$HOME/$rel"
		[ -f "$source" ] || [ -L "$source" ] || continue
		[ -n "${seen[$rel]+x}" ] && continue
		seen["$rel"]=1
		case "$rel" in
			.config/*) config_files+=("$rel") ;;
			.local/*) local_files+=("$rel") ;;
			*) other_files+=("$rel") ;;
		esac
	done

	if [ ${#config_files[@]} -gt 0 ]; then
		mapfile -t _FRESH_CONFIG_FILES < <(printf '%s\n' "${config_files[@]}" | LC_ALL=C sort -u)
	fi
	if [ ${#other_files[@]} -gt 0 ]; then
		mapfile -t _FRESH_OTHER_TRACKED_FILES < <(printf '%s\n' "${other_files[@]}" | LC_ALL=C sort -u)
	fi
	if [ ${#local_files[@]} -gt 0 ]; then
		mapfile -t _FRESH_LOCAL_TRACKED_FILES < <(printf '%s\n' "${local_files[@]}" | LC_ALL=C sort -u)
	fi
	_FRESH_BACKUP_FILES=(
		"${_FRESH_CONFIG_FILES[@]}"
		"${_FRESH_OTHER_TRACKED_FILES[@]}"
		"${_FRESH_LOCAL_TRACKED_FILES[@]}"
	)
}

# fresh_backup_collected_files [status] [timestamp]
# Copies the set prepared by fresh_collect_backup_files and records actual
# successful copy counts for the three mixed-mode groups.
fresh_backup_collected_files() {
	local status="${1:-tracked_at_install}"
	local timestamp="${2:-}"
	local f

	_FRESH_BACKED_CONFIG_COUNT=0
	_FRESH_BACKED_OTHER_COUNT=0
	_FRESH_BACKED_LOCAL_COUNT=0
	for f in "${_FRESH_CONFIG_FILES[@]}"; do
		if fresh_copy_to_backup "$f" "$status" "$timestamp"; then
			_FRESH_BACKED_CONFIG_COUNT=$((_FRESH_BACKED_CONFIG_COUNT + 1))
		fi
	done
	for f in "${_FRESH_OTHER_TRACKED_FILES[@]}"; do
		if fresh_copy_to_backup "$f" "$status" "$timestamp"; then
			_FRESH_BACKED_OTHER_COUNT=$((_FRESH_BACKED_OTHER_COUNT + 1))
		fi
	done
	for f in "${_FRESH_LOCAL_TRACKED_FILES[@]}"; do
		if fresh_copy_to_backup "$f" "$status" "$timestamp"; then
			_FRESH_BACKED_LOCAL_COUNT=$((_FRESH_BACKED_LOCAL_COUNT + 1))
		fi
	done
}

# fresh_print_backup_stats [root_code]
# Prints mixed-mode Fresh backup counts for each path group.
fresh_print_backup_stats() {
	local root_code="${1:-$FRESH_ROOT_CODE}"
	local total=$((_FRESH_BACKED_CONFIG_COUNT + _FRESH_BACKED_OTHER_COUNT + _FRESH_BACKED_LOCAL_COUNT))
	printf '  ~/.config/: %d files backed up (full)\n' "$_FRESH_BACKED_CONFIG_COUNT"
	printf '  Other tracked files: %d files backed up\n' "$_FRESH_BACKED_OTHER_COUNT"
	printf '  ~/.local/ tracked files: %d files backed up\n' "$_FRESH_BACKED_LOCAL_COUNT"
	printf '  Total: %d files backed up to %s\n' "$total" "$root_code"
}

# fresh_create_root_backup [--dry-run] [git_dir]
# Mixed scan of $HOME, copies files into the fresh root node backup and creates
# the node entry with config_version=bootstrap.
fresh_create_root_backup() {
	local dry_run=false
	local git_dir="${GIT_DIR:-${DOTCFG_GIT_DIR:-$HOME/.cfg}}"
	local arg
	for arg in "$@"; do
		case "$arg" in
			--dry-run) dry_run=true ;;
			*) git_dir="$arg" ;;
		esac
	done

	if [ -z "${CFG_NODES_DIR:-}" ]; then
		cfg_nodes_init "${CFG_BACKUP_ROOT:-$HOME/.config-backup}" 2>/dev/null || true
	fi

	fresh_collect_backup_files "$git_dir"

	if $dry_run; then
		printf 'Would back up %d files to nodes/%s/backup/ (mixed mode):\n' "${#_FRESH_BACKUP_FILES[@]}" "$FRESH_ROOT_CODE"
		local f
		for f in "${_FRESH_BACKUP_FILES[@]}"; do
			printf '  %s\n' "$f"
		done
		return 0
	fi

	# Create the root node with the fixed code (reuse existing root if any)
	local code
	code=$(fresh_get_root_code 2>/dev/null) || code=""
	if [ -z "$code" ]; then
		code=$(cfg_node_create "fresh" "null" "$FRESH_BOOTSTRAP_VERSION" "$FRESH_ROOT_CODE") || return 1
		cfg_nodes_invalidate
	fi

	local backup_dir="$CFG_NODES_DIR/$code/backup"
	mkdir -p "$backup_dir"
	chmod 700 "$backup_dir" 2>/dev/null || true

	fresh_manifest_write_header "$code"

	printf 'Creating fresh backup (mixed mode)...\n'
	fresh_backup_collected_files "tracked_at_install" ""
	fresh_print_backup_stats "$code"

	local count=$((_FRESH_BACKED_CONFIG_COUNT + _FRESH_BACKED_OTHER_COUNT + _FRESH_BACKED_LOCAL_COUNT))
	printf 'Fresh node created: %s (%d files backed up)\n' "$code" "$count"
	return 0
}

# fresh_collect_legacy_adoption_files <legacy_dir> [git_dir]
# Selects tracked pre-install files from a legacy backup plus current,
# unmanaged ~/.config files. Current tracked files are deliberately skipped.
fresh_collect_legacy_adoption_files() {
	local legacy_dir="$1"
	local git_dir="${2:-${GIT_DIR:-${DOTCFG_GIT_DIR:-$HOME/.cfg}}}"
	local source rel
	local -A seen=() tracked=()

	_FRESH_ADOPT_PATHS=()
	_FRESH_ADOPT_SOURCES=()
	_FRESH_ADOPT_STATUSES=()
	_FRESH_ADOPT_LEGACY_COUNT=0
	_FRESH_ADOPT_CONFIG_COUNT=0

	while IFS= read -r rel; do
		[ -n "$rel" ] && tracked["$rel"]=1
	done < <(git --git-dir="$git_dir/" ls-tree -r --name-only HEAD 2>/dev/null)

	while IFS= read -r -d '' source; do
		rel="${source#"$legacy_dir"/}"
		case "$rel" in
			nodes/*|sessions/*|HEAD|DEPLOY_STATUS|CURRENT_CONFIG_VERSION|index.json|*.tmp) continue ;;
		esac
		cfg_is_installation_path "$rel" && continue
		[ -n "${tracked[$rel]+x}" ] || continue
		seen["$rel"]=1
		_FRESH_ADOPT_PATHS+=("$rel")
		_FRESH_ADOPT_SOURCES+=("$source")
		_FRESH_ADOPT_STATUSES+=("legacy_backup")
		_FRESH_ADOPT_LEGACY_COUNT=$((_FRESH_ADOPT_LEGACY_COUNT + 1))
	done < <(find "$legacy_dir" \( -type f -o -type l \) -print0 2>/dev/null)

	if [ -d "$HOME/.config" ]; then
		while IFS= read -r -d '' source; do
			rel="${source#"$HOME"/}"
			[ -n "${seen[$rel]+x}" ] && continue
			[ -n "${tracked[$rel]+x}" ] && continue
			fresh_exclude_is_excluded "$rel" && continue
			seen["$rel"]=1
			_FRESH_ADOPT_PATHS+=("$rel")
			_FRESH_ADOPT_SOURCES+=("$source")
			_FRESH_ADOPT_STATUSES+=("untracked_config_at_adoption")
			_FRESH_ADOPT_CONFIG_COUNT=$((_FRESH_ADOPT_CONFIG_COUNT + 1))
		done < <(find "$HOME/.config" \( -type f -o -type l \) -print0 2>/dev/null)
	fi
}

# fresh_adopt_legacy <legacy_dir> [--dry-run] [--config-version VERSION]
# Reconstructs a Fresh root for systems installed before dotcfg existed.
fresh_adopt_legacy() {
	local legacy_dir=""
	local dry_run=false
	local config_version=""
	local git_dir="${DOTCFG_GIT_DIR:-$HOME/.cfg}"
	local backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
	local arg

	while [ $# -gt 0 ]; do
		arg="$1"
		case "$arg" in
			--dry-run) dry_run=true ;;
			--config-version)
				shift
				[ $# -gt 0 ] || { printf 'ERROR: --config-version requires a value.\n' >&2; return 2; }
				config_version="$1"
				;;
			--config-version=*) config_version="${arg#*=}" ;;
			-*) printf 'ERROR: unknown option: %s\n' "$arg" >&2; return 2 ;;
			*)
				[ -z "$legacy_dir" ] || { printf 'ERROR: only one legacy directory is allowed.\n' >&2; return 2; }
				legacy_dir="$arg"
				;;
		esac
		shift
	done

	[ -n "$legacy_dir" ] || legacy_dir="$backup_root"
	legacy_dir="${legacy_dir%/}"
	case "$legacy_dir" in
		\~/*) legacy_dir="$HOME/${legacy_dir#\~/}" ;;
	esac
	if [ "$legacy_dir" = "$HOME/.config-backup.bak" ]; then
		printf 'ERROR: emergency backup %s is intentionally excluded and cannot be adopted.\n' "$legacy_dir" >&2
		return 1
	fi
	[ -d "$legacy_dir" ] || { printf 'ERROR: legacy backup directory not found: %s\n' "$legacy_dir" >&2; return 1; }
	legacy_dir=$(cd -- "$legacy_dir" && pwd -P)
	git --git-dir="$git_dir/" rev-parse --verify HEAD >/dev/null 2>&1 || {
		printf 'ERROR: valid dotfiles repository not found at %s.\n' "$git_dir" >&2
		return 1
	}

	if [ -f "$backup_root/HEAD" ] || [ -f "$backup_root/nodes/index.json" ]; then
		printf 'ERROR: node metadata already exists in %s; refusing to replace it.\n' "$backup_root" >&2
		return 1
	fi

	if [ -z "$config_version" ]; then
		config_version=$(cfg_config_version_latest 2>/dev/null) || config_version=""
	fi
	if [ -n "$config_version" ] && ! cfg_config_version_read "$config_version" >/dev/null 2>&1; then
		printf 'ERROR: category version %s not found.\n' "$config_version" >&2
		return 1
	fi

	fresh_collect_legacy_adoption_files "$legacy_dir" "$git_dir"
	local total=${#_FRESH_ADOPT_PATHS[@]}
	local total_size=0 size i
	for ((i = 0; i < total; i++)); do
		size=$(cfg_path_size "${_FRESH_ADOPT_SOURCES[$i]}")
		[[ "$size" =~ ^[0-9]+$ ]] && total_size=$((total_size + size))
	done

	printf 'Legacy Fresh adoption plan:\n'
	printf '  Legacy tracked originals: %d files\n' "$_FRESH_ADOPT_LEGACY_COUNT"
	printf '  Current unmanaged ~/.config/: %d files\n' "$_FRESH_ADOPT_CONFIG_COUNT"
	printf '  Total: %d files (%s)\n' "$total" "$(fresh_format_size "$total_size")"
	printf '  Config version for new nodes: %s\n' "${config_version:-bootstrap}"
	for ((i = 0; i < total; i++)); do
		printf '  %-30s %s <- %s\n' "[${_FRESH_ADOPT_STATUSES[$i]}]" \
			"${_FRESH_ADOPT_PATHS[$i]}" "${_FRESH_ADOPT_SOURCES[$i]}"
	done

	if $dry_run; then
		printf 'DRY RUN: no files or node metadata were changed.\n'
		return 0
	fi
	[ "$total" -gt 0 ] || { printf 'ERROR: no eligible files found; Fresh root was not created.\n' >&2; return 1; }

	cfg_nodes_init "$backup_root"
	local code
	code=$(cfg_node_create "fresh" "null" "$FRESH_BOOTSTRAP_VERSION" "$FRESH_ROOT_CODE") || return 1
	cfg_nodes_invalidate
	mkdir -p "$CFG_NODES_DIR/$code/backup"
	chmod 700 "$CFG_NODES_DIR/$code/backup" 2>/dev/null || true
	fresh_manifest_write_header "$code"

	local failed=0
	for ((i = 0; i < total; i++)); do
		if ! fresh_copy_source_to_backup "${_FRESH_ADOPT_SOURCES[$i]}" \
			"${_FRESH_ADOPT_PATHS[$i]}" "${_FRESH_ADOPT_STATUSES[$i]}"; then
			printf 'ERROR: failed to adopt %s.\n' "${_FRESH_ADOPT_SOURCES[$i]}" >&2
			failed=$((failed + 1))
			break
		fi
	done
	if [ "$failed" -gt 0 ]; then
		cfg_nodes_delete "$code" 2>/dev/null || true
		rm -rf -- "${CFG_NODES_DIR:?}/$code"
		return 1
	fi

	cfg_head_set "$code"
	cfg_deploy_status_set "deployed"
	if [ -n "$config_version" ]; then
		cfg_config_version_set "$config_version"
	else
		printf '%s\n' "$FRESH_BOOTSTRAP_VERSION" > "$backup_root/CURRENT_CONFIG_VERSION"
	fi
	printf 'Fresh root created from legacy backup: %s (%d files).\n' "$code" "$total"
}
