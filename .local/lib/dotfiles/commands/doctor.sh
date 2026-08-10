#!/usr/bin/env bash
# commands/doctor.sh - Full system integrity check (9 documented checks)
# Usage: doctor.sh
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
git_dir="${DOTCFG_GIT_DIR:-$HOME/.cfg}"

# Snapshot state before cfg_nodes_init (which creates directories)
backup_root_existed=false
[ -d "$backup_root" ] && backup_root_existed=true
index_existed=false
[ -f "$backup_root/nodes/index.json" ] && index_existed=true
fresh_dir_existed=false
[ -d "$backup_root/nodes/fresh_root" ] && fresh_dir_existed=true

cfg_nodes_init "$backup_root"

issues=0

pass() { printf '\xe2\x9c\x85 %s\n' "$1"; }
fail() { printf '\xe2\x9d\x8c %s\n' "$1"; issues=$((issues + 1)); }

printf 'Checking system integrity...\n\n'

# 1. Repository existence
if [ -d "$git_dir" ]; then
	pass "1. Repository exists: $git_dir"
else
	fail "1. Repository exists: $git_dir missing (run installation to create)"
fi

# 2. Repository validity
if [ -d "$git_dir" ]; then
	if git --git-dir="$git_dir" rev-parse --git-dir >/dev/null 2>&1; then
		pass "2. Repository valid: $git_dir is a git repository"
	else
		fail "2. Repository valid: $git_dir is not a valid git repository"
	fi
else
	fail "2. Repository valid: skipped (repository missing)"
fi

# 3. Repository ownership
if [ -d "$git_dir" ]; then
	cfg_validate "$git_dir" 2>/dev/null || true
	case "${CFG_STATE:-missing}" in
		valid)
			if [ "${CFG_IS_OURS:-false}" = "true" ]; then
				pass "3. Repository ownership: belongs to this project"
			else
				fail "3. Repository ownership: valid repository but not this project's dotfiles"
			fi
			;;
		*) fail "3. Repository ownership: cannot determine (${CFG_STATE:-unknown})" ;;
	esac
else
	fail "3. Repository ownership: skipped (repository missing)"
fi

# 4. Backup directory existence
if $backup_root_existed; then
	pass "4. Backup directory exists: $backup_root"
else
	fail "4. Backup directory exists: $backup_root missing"
fi

# 5. index.json validity
if $index_existed; then
	if cfg_nodes_read_index 2>/dev/null; then
		pass "5. index.json valid: ${#_CFG_NODE_CODES[@]} nodes"
	else
		fail "5. index.json valid: cannot be parsed"
	fi
else
	fail "5. index.json valid: $backup_root/nodes/index.json missing"
fi

# 6. Fresh node existence
if $fresh_dir_existed; then
	pass "6. Fresh node exists: $backup_root/nodes/fresh_root"
else
	fail "6. Fresh node exists: $backup_root/nodes/fresh_root missing"
fi

# 7. HEAD validity
head_code=$(cfg_head_get 2>/dev/null) || head_code=""
if [ -z "$head_code" ]; then
	fail "7. HEAD valid: missing"
elif cfg_node_exists "$head_code" 2>/dev/null; then
	pass "7. HEAD valid: points to $head_code"
else
	fail "7. HEAD valid: HEAD points to invalid node '$head_code'"
fi

# 8. DEPLOY_STATUS validity
if [ -f "$backup_root/DEPLOY_STATUS" ]; then
	deploy_status=$(head -n1 "$backup_root/DEPLOY_STATUS" 2>/dev/null | tr -d '[:space:]')
	case "$deploy_status" in
		deployed|uninstalled) pass "8. DEPLOY_STATUS valid: $deploy_status" ;;
		*) fail "8. DEPLOY_STATUS valid: unexpected value '${deploy_status:-empty}'" ;;
	esac
else
	fail "8. DEPLOY_STATUS valid: missing"
fi

# 9. Config version existence
versions=$(cfg_config_version_list 2>/dev/null) || versions=""
if [ -n "$versions" ]; then
	vcount=$(printf '%s\n' "$versions" | wc -l | tr -d ' ')
	vlist=$(printf '%s\n' "$versions" | tr '\n' ',' | sed 's/,$//')
	pass "9. Config versions exist: $vcount found ($vlist)"
elif [ -f "$DOTFILES_LIB_DIR/categories.conf" ]; then
	pass "9. Config categories available: using unversioned categories.conf"
else
	pass "9. Config categories available: using built-in defaults (macos, min, full)"
fi

printf '\n'
if [ "$issues" -eq 0 ]; then
	printf 'System is healthy.\n\nIssues found: 0\nRecommendations: none\n'
	exit 0
else
	printf 'Issues found: %d\n' "$issues"
	printf 'Recommendations: run "dotcfg repair" to attempt automatic fixes\n'
	exit 1
fi
