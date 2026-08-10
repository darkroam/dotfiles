#!/usr/bin/env bash
# commands/repair.sh - Attempt to repair detected system issues
# Repair items correspond to the 9 doctor checks.
# Usage: repair.sh [--force]
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
git_dir="${DOTCFG_GIT_DIR:-$HOME/.cfg}"

# Snapshot state before cfg_nodes_init (which creates directories)
backup_root_existed=true
[ -d "$backup_root" ] || backup_root_existed=false
fresh_dir_existed=true
[ -d "$backup_root/nodes/fresh_root" ] || fresh_dir_existed=false

cfg_nodes_init "$backup_root"

confirm() {
	# confirm <description>; returns 0 if approved
	if $FORCE; then
		return 0
	fi
	printf '  %s (y/N): ' "$1"
	read -r answer || answer=""
	case "$answer" in
		y|Y|yes|YES) return 0 ;;
		*) return 1 ;;
	esac
}

printf 'Checking system integrity...\n\n'

repairs_done=0
problems=0

# ── 1-3. Repository ────────────────────────────────────────────────────
cfg_validate "$git_dir" 2>/dev/null || true
case "${CFG_STATE:-missing}" in
	valid)
		if [ "${CFG_IS_OURS:-false}" != "true" ]; then
			printf '\xe2\x9d\x8c %s: not this project\x27s repository\n' "$git_dir"
			printf '   Manual action required: remove it and rerun installation:\n'
			printf '     rm -rf %s\n' "$git_dir"
			problems=$((problems + 1))
		fi
		;;
	missing)
		printf '\xe2\x9d\x8c %s: missing\n' "$git_dir"
		problems=$((problems + 1))
		remote_url="${DOTCFG_REMOTE_URL:-git@github.com:darkroam/dotfiles.git}"
		if confirm "Enter bootstrap install mode (clone $remote_url)?"; then
			if git clone --bare --quiet "$remote_url" "$git_dir"; then
				printf '   Repository cloned to %s\n' "$git_dir"
				repairs_done=$((repairs_done + 1))
			else
				printf '   ERROR: failed to clone repository. Check network/SSH access.\n' >&2
			fi
		fi
		;;
	not_git)
		printf '\xe2\x9d\x8c %s: not a valid git repository\n' "$git_dir"
		printf '   Running git fsck for diagnostics...\n'
		git --git-dir="$git_dir" fsck --no-dangling 2>&1 | head -5 || true
		printf '   Manual action required: inspect or remove %s and rerun installation.\n' "$git_dir"
		problems=$((problems + 1))
		;;
	foreign_repo)
		printf '\xe2\x9d\x8c %s: foreign repository (not this project)\n' "$git_dir"
		printf '   Manual action required: remove it and rerun installation:\n'
		printf '     rm -rf %s\n' "$git_dir"
		problems=$((problems + 1))
		;;
	*)
		printf '\xe2\x9d\x8c %s: invalid state (%s)\n' "$git_dir" "${CFG_STATE:-unknown}"
		problems=$((problems + 1))
		;;
esac

# ── 4. Backup root ─────────────────────────────────────────────────────
if ! $backup_root_existed; then
	printf '\xe2\x9d\x8c %s/: missing\n' "$backup_root"
	problems=$((problems + 1))
	if confirm "Create $backup_root, initialize index.json and create fresh node?"; then
		mkdir -p "$backup_root/nodes"
		chmod 700 "$backup_root" 2>/dev/null || true
		if [ ! -f "$backup_root/nodes/index.json" ]; then
			printf '{\n  "nodes": []\n}\n' > "$backup_root/nodes/index.json"
		fi
		fresh_create_root_backup "$git_dir" || printf 'WARNING: fresh backup failed\n' >&2
		root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
		if [ -n "$root_code" ]; then
			cfg_head_set "$root_code"
			cfg_deploy_status_set "deployed"
			printf 'bootstrap\n' > "$backup_root/CURRENT_CONFIG_VERSION"
		fi
		repairs_done=$((repairs_done + 1))
	fi
fi

# ── 5. index.json ──────────────────────────────────────────────────────
_repair_rebuild_index() {
	# Best-effort rebuild of index.json from node directories + manifests
	local dirs=()
	local d
	for d in "$CFG_NODES_DIR"/*/; do
		[ -d "$d" ] || continue
		dirs+=("${d%/}")
	done
	[ ${#dirs[@]} -eq 0 ] && return 1

	_CFG_NODE_CODES=()
	_CFG_NODE_TYPES=()
	_CFG_NODE_TIMESTAMPS=()
	_CFG_NODE_PARENTS=()
	_CFG_NODE_CHILDREN=()
	_CFG_NODE_CONFIG_VERSIONS=()
	_CFG_NODE_STATUSES=()

	local code type ts root_found=""
	local i
	# First pass: find the fresh root directory if present
	for d in "${dirs[@]}"; do
		code="${d##*/}"
		if [ "$code" = "$FRESH_ROOT_CODE" ]; then
			root_found="$code"
			break
		fi
		if [ -f "$d/manifest.txt" ] && grep -q '# Type:.*fresh' "$d/manifest.txt" 2>/dev/null; then
			[ -z "$root_found" ] && root_found="$code"
		fi
	done

	# Second pass: build entries
	for d in "${dirs[@]}"; do
		code="${d##*/}"
		type="full"
		if [ "$code" = "$root_found" ]; then
			type="fresh"
		elif [ -f "$d/manifest.txt" ] && grep -q '# Type:.*fresh' "$d/manifest.txt" 2>/dev/null; then
			type="fresh"
		fi
		ts=$(date -u '+%Y-%m-%dT%H:%M:%S')
		_CFG_NODE_CODES+=("$code")
		_CFG_NODE_TYPES+=("$type")
		_CFG_NODE_TIMESTAMPS+=("$ts")
		if [ "$type" = "fresh" ] && [ "$code" = "$root_found" ]; then
			_CFG_NODE_PARENTS+=("null")
		else
			_CFG_NODE_PARENTS+=("${root_found:-null}")
		fi
		_CFG_NODE_CHILDREN+=("")
		_CFG_NODE_CONFIG_VERSIONS+=("")
		_CFG_NODE_STATUSES+=("active")
	done

	cfg_nodes_write_index
	return 0
}

index_ok=true
if [ ! -f "$backup_root/nodes/index.json" ]; then
	printf '\xe2\x9d\x8c %s/nodes/index.json: missing\n' "$backup_root"
	index_ok=false
	problems=$((problems + 1))
	if confirm "Rebuild index.json from node directories?"; then
		if _repair_rebuild_index; then
			printf '   index.json rebuilt from node directories\n'
			repairs_done=$((repairs_done + 1))
		else
			printf '   No node directories found. Creating empty index.json.\n'
			printf '{\n  "nodes": []\n}\n' > "$backup_root/nodes/index.json"
			repairs_done=$((repairs_done + 1))
		fi
	fi
elif ! cfg_nodes_read_index 2>/dev/null || [ ${#_CFG_NODE_CODES[@]} -eq 0 ]; then
	printf '\xe2\x9d\x8c %s/nodes/index.json: invalid or empty\n' "$backup_root"
	index_ok=false
	problems=$((problems + 1))
	if confirm "Attempt to rebuild index.json from node manifests?"; then
		if _repair_rebuild_index; then
			printf '   index.json rebuilt from node directories\n'
			repairs_done=$((repairs_done + 1))
		else
			printf '   ERROR: rebuild failed. Consider "dotcfg migrate" or manual repair.\n' >&2
		fi
	fi
fi

# ── 6. Fresh node ──────────────────────────────────────────────────────
cfg_nodes_read_index 2>/dev/null || true
root_code=$(cfg_nodes_get_root 2>/dev/null) || root_code=""
if ! $fresh_dir_existed && [ ! -d "$backup_root/nodes/fresh_root" ]; then
	printf '\xe2\x9d\x8c fresh node: missing\n'
	problems=$((problems + 1))
	if [ -n "$root_code" ]; then
		if confirm "Rebuild fresh node directory from root node $root_code?"; then
			mkdir -p "$CFG_NODES_DIR/$root_code/backup" "$CFG_NODES_DIR/$root_code/files"
			chmod 700 "$CFG_NODES_DIR/$root_code/backup" 2>/dev/null || true
			if [ ! -f "$CFG_NODES_DIR/$root_code/manifest.txt" ]; then
				fresh_manifest_write_header "$root_code" 2>/dev/null || true
			fi
			repairs_done=$((repairs_done + 1))
		fi
	else
		if confirm "Create fresh root node with mixed-mode backup?"; then
			fresh_create_root_backup "$git_dir" || printf 'WARNING: fresh backup failed\n' >&2
			repairs_done=$((repairs_done + 1))
		fi
	fi
fi

# ── 7. HEAD ────────────────────────────────────────────────────────────
root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
head_code=$(cfg_head_get 2>/dev/null) || head_code=""
if [ -z "$head_code" ]; then
	printf '\xe2\x9d\x8c HEAD: missing\n'
	problems=$((problems + 1))
	if [ -n "$root_code" ] && confirm "Reset HEAD to $root_code?"; then
		cfg_head_set "$root_code"
		repairs_done=$((repairs_done + 1))
	fi
elif ! cfg_node_exists "$head_code" 2>/dev/null; then
	printf '\xe2\x9d\x8c HEAD: points to invalid node %s\n' "$head_code"
	problems=$((problems + 1))
	if [ -n "$root_code" ] && confirm "Reset HEAD to $root_code?"; then
		cfg_head_set "$root_code"
		repairs_done=$((repairs_done + 1))
	fi
fi

# ── 8. DEPLOY_STATUS ───────────────────────────────────────────────────
deploy_ok=false
if [ -f "$backup_root/DEPLOY_STATUS" ]; then
	deploy_val=$(head -n1 "$backup_root/DEPLOY_STATUS" 2>/dev/null | tr -d '[:space:]')
	case "$deploy_val" in
		deployed|uninstalled) deploy_ok=true ;;
	esac
fi
if ! $deploy_ok; then
	printf '\xe2\x9d\x8c %s/DEPLOY_STATUS: missing or invalid\n' "$backup_root"
	problems=$((problems + 1))
	if confirm "Create DEPLOY_STATUS file with 'deployed'?"; then
		cfg_deploy_status_set "deployed"
		repairs_done=$((repairs_done + 1))
	fi
fi

# ── 9. Config versions ─────────────────────────────────────────────────
versions=$(cfg_config_version_list 2>/dev/null) || versions=""
if [ -n "$versions" ] && [ ! -f "$backup_root/CURRENT_CONFIG_VERSION" ]; then
	printf '\xe2\x9d\x8c %s/CURRENT_CONFIG_VERSION: missing\n' "$backup_root"
	problems=$((problems + 1))
	if confirm "Create CURRENT_CONFIG_VERSION (latest available)?"; then
		latest=$(cfg_config_version_latest 2>/dev/null) || latest=""
		printf '%s\n' "${latest:-default}" > "$backup_root/CURRENT_CONFIG_VERSION"
		repairs_done=$((repairs_done + 1))
	fi
fi

printf '\n'
if [ "$problems" -eq 0 ]; then
	printf 'System is healthy. No repairs needed.\n'
	exit 0
fi

printf 'Issues found: %d, repairs applied: %d\n' "$problems" "$repairs_done"
if [ "$repairs_done" -gt 0 ]; then
	printf 'System repaired.\n'
fi
