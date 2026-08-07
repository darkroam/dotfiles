#!/usr/bin/env bash
# commands/repair.sh - Attempt to repair detected system issues
# Usage: repair.sh [--force]
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
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

# ── Repository ─────────────────────────────────────────────────────────
git_dir="${DOTCFG_GIT_DIR:-$HOME/.cfg}"
if [ ! -d "$git_dir" ]; then
	printf '\xe2\x9d\x8c %s: missing\n' "$git_dir"
	printf '   Cannot repair automatically. Reinstall with:\n'
	printf '     curl -fsSL https://github.com/darkroam/dotfiles/raw/master/.local/bin/dotcfg | bash\n'
	problems=$((problems + 1))
else
	cfg_validate "$git_dir" 2>/dev/null || true
	case "${CFG_STATE:-missing}" in
		valid) ;;
		not_git|foreign_repo)
			printf '\xe2\x9d\x8c %s: %s\n' "$git_dir" "${CFG_STATE}"
			printf '   Repair: running git fsck for diagnostics...\n'
			git --git-dir="$git_dir" fsck --no-dangling 2>&1 | head -5 || true
			problems=$((problems + 1))
			;;
		*)
			printf '\xe2\x9d\x8c %s: invalid state\n' "$git_dir"
			problems=$((problems + 1))
			;;
	esac
fi

# ── Backup root ────────────────────────────────────────────────────────
if [ ! -d "$backup_root" ]; then
	printf '\xe2\x9d\x8c %s/: missing\n' "$backup_root"
	problems=$((problems + 1))
	if confirm "Create $backup_root and initialize fresh node?"; then
		mkdir -p "$backup_root/nodes"
		chmod 700 "$backup_root" 2>/dev/null || true
		fresh_create_root_backup || printf 'WARNING: fresh backup failed\n' >&2
		root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
		if [ -n "$root_code" ]; then
			cfg_head_set "$root_code"
			cfg_deploy_status_set "deployed"
			printf 'bootstrap\n' > "$backup_root/CURRENT_CONFIG_VERSION"
		fi
		repairs_done=$((repairs_done + 1))
	fi
fi

# ── Missing state files ────────────────────────────────────────────────
if [ ! -f "$backup_root/DEPLOY_STATUS" ]; then
	printf '\xe2\x9d\x8c %s/DEPLOY_STATUS: missing\n' "$backup_root"
	problems=$((problems + 1))
	if confirm "Create DEPLOY_STATUS file with 'deployed'?"; then
		cfg_deploy_status_set "deployed"
		repairs_done=$((repairs_done + 1))
	fi
fi

if [ ! -f "$backup_root/CURRENT_CONFIG_VERSION" ]; then
	printf '\xe2\x9d\x8c %s/CURRENT_CONFIG_VERSION: missing\n' "$backup_root"
	problems=$((problems + 1))
	if confirm "Create CURRENT_CONFIG_VERSION (latest available)?"; then
		latest=$(cfg_config_version_latest 2>/dev/null) || latest=""
		printf '%s\n' "${latest:-bootstrap}" > "$backup_root/CURRENT_CONFIG_VERSION"
		repairs_done=$((repairs_done + 1))
	fi
fi

# ── index.json ─────────────────────────────────────────────────────────
index_ok=true
if [ ! -f "$backup_root/nodes/index.json" ]; then
	printf '\xe2\x9d\x8c %s/nodes/index.json: missing\n' "$backup_root"
	index_ok=false
	problems=$((problems + 1))
	if confirm "Create empty index.json?"; then
		mkdir -p "$backup_root/nodes"
		printf '{\n  "nodes": []\n}\n' > "$backup_root/nodes/index.json"
		repairs_done=$((repairs_done + 1))
	fi
elif ! cfg_nodes_read_index 2>/dev/null; then
	printf '\xe2\x9d\x8c %s/nodes/index.json: cannot be parsed\n' "$backup_root"
	printf '   Automatic rebuild is not safe. Consider "dotcfg migrate" or manual repair.\n'
	index_ok=false
	problems=$((problems + 1))
fi

# ── Fresh node ─────────────────────────────────────────────────────────
root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
if [ -z "$root_code" ]; then
	printf '\xe2\x9d\x8c fresh node: missing\n'
	problems=$((problems + 1))
	if confirm "Create fresh root node with full backup?"; then
		fresh_create_root_backup || printf 'WARNING: fresh backup failed\n' >&2
		repairs_done=$((repairs_done + 1))
	fi
	root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
fi

# ── HEAD ───────────────────────────────────────────────────────────────
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

printf '\n'
if [ "$problems" -eq 0 ]; then
	printf 'System is healthy. No repairs needed.\n'
	exit 0
fi

printf 'Issues found: %d, repairs applied: %d\n' "$problems" "$repairs_done"
if [ "$repairs_done" -gt 0 ]; then
	printf 'System repaired.\n'
fi
