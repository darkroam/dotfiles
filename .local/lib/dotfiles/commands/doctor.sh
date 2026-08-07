#!/usr/bin/env bash
# commands/doctor.sh - Full system integrity check
# Usage: doctor.sh
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
cfg_nodes_init "$backup_root"

issues=0

pass() { printf '\xe2\x9c\x85 %s\n' "$1"; }
fail() { printf '\xe2\x9d\x8c %s\n' "$1"; issues=$((issues + 1)); }

printf 'Checking system integrity...\n\n'

# 1-3. Repository checks
git_dir="${DOTCFG_GIT_DIR:-$HOME/.cfg}"
if [ ! -d "$git_dir" ]; then
	fail "$git_dir: missing (run installation to create)"
else
	cfg_validate "$git_dir" 2>/dev/null || true
	case "${CFG_STATE:-missing}" in
		valid)
			if [ "${CFG_IS_OURS:-false}" = "true" ]; then
				pass "$git_dir: exists, valid repository (ours)"
			else
				fail "$git_dir: valid repository but not this project's dotfiles"
			fi
			;;
		not_git) fail "$git_dir: exists but is not a git repository" ;;
		foreign_repo) fail "$git_dir: foreign repository (not this project)" ;;
		*) fail "$git_dir: invalid state (${CFG_STATE:-unknown})" ;;
	esac
fi

# 4. Backup root
if [ -d "$backup_root" ]; then
	pass "$backup_root/: exists"
else
	fail "$backup_root/: missing"
fi

# 5. Required state files
missing_files=()
for f in nodes/index.json HEAD DEPLOY_STATUS CURRENT_CONFIG_VERSION; do
	[ -f "$backup_root/$f" ] || missing_files+=("$f")
done
if [ ${#missing_files[@]} -eq 0 ]; then
	pass "$backup_root/: complete (index.json, HEAD, DEPLOY_STATUS, CURRENT_CONFIG_VERSION)"
else
	fail "$backup_root/: incomplete (missing: $(IFS=', '; echo "${missing_files[*]}"))"
fi

# 6. index.json parseable
if [ -f "$backup_root/nodes/index.json" ]; then
	if cfg_nodes_read_index 2>/dev/null; then
		pass "$backup_root/nodes/index.json: valid (${#_CFG_NODE_CODES[@]} nodes)"
	else
		fail "$backup_root/nodes/index.json: cannot be parsed"
	fi
else
	fail "$backup_root/nodes/index.json: missing"
fi

# 7. Fresh node
root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
if [ -n "$root_code" ]; then
	fcount=0
	fresh_manifest_read "$root_code" 2>/dev/null && fcount=$(fresh_backup_count)
	pass "fresh node: exists ($root_code, $fcount files)"
else
	fail "fresh node: missing"
fi

# 8. HEAD validity
head_code=$(cfg_head_get 2>/dev/null) || head_code=""
if [ -z "$head_code" ]; then
	fail "HEAD: missing"
elif cfg_node_exists "$head_code" 2>/dev/null; then
	pass "HEAD: points to $head_code"
else
	fail "HEAD: points to invalid node '$head_code'"
fi

# 9. Config versions
versions=$(cfg_config_version_list 2>/dev/null) || versions=""
if [ -n "$versions" ]; then
	vcount=$(printf '%s\n' "$versions" | wc -l | tr -d ' ')
	vlist=$(printf '%s\n' "$versions" | tr '\n' ',' | sed 's/,$//')
	pass "Categories versions: $vcount found ($vlist)"
	current_ver=$(cfg_config_version_get_current 2>/dev/null) || current_ver=""
	if [ -n "$current_ver" ]; then
		pass "Current config version: $current_ver"
	else
		fail "Current config version: not set"
	fi
else
	fail "Categories versions: none found"
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
