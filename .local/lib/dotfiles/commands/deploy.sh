#!/usr/bin/env bash
# commands/deploy.sh - Deploy current node's configuration to $HOME
# Usage: deploy.sh [--force] [--dry-run]
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

cfg_parse_common_args "$@"

git_dir="${DOTCFG_GIT_DIR:-$HOME/.cfg}"
backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"

cfg_nodes_init "$backup_root"

# ── Read current node ──────────────────────────────────────────────────

current_code=$(cfg_head_get) || {
	printf 'ERROR: no current node (HEAD not set)\n' >&2
	printf 'Run '\''dotcfg switch desktop'\'' or '\''dotcfg switch server'\'' first.\n' >&2
	exit 1
}

node_type=$(cfg_node_get "$current_code" "type") || {
	printf 'ERROR: node %s not found in index\n' "$current_code" >&2
	exit 1
}

deploy_status=$(cfg_deploy_status_get)

if [ "$deploy_status" = "deployed" ] && [ "$CFG_FORCE" != "true" ]; then
	printf 'Node %s (%s) is already deployed.\n' "$current_code" "$node_type"
	printf 'Use --force to redeploy.\n'
	exit 0
fi

# ── Fresh nodes have nothing to deploy ─────────────────────────────────

if [ "$node_type" = "fresh" ]; then
	printf 'Node %s is fresh (root). Nothing to deploy.\n' "$current_code"
	cfg_deploy_status_set "deployed"
	exit 0
fi

# ── Validate repository ───────────────────────────────────────────────

if [ ! -d "$git_dir" ]; then
	printf 'ERROR: repository not found at %s\n' "$git_dir" >&2
	exit 1
fi

config() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

# ── Determine file list ───────────────────────────────────────────────

printf 'Deploying node %s (%s)...\n\n' "$current_code" "$node_type"

node_version=$(cfg_node_get "$current_code" "config_version" 2>/dev/null) || node_version=""
if [ -n "$node_version" ] && [ "$node_version" != "unknown" ]; then
	if ! cfg_config_version_read "$node_version" >/dev/null 2>&1; then
		if [ "$CFG_FORCE" = "true" ]; then
			printf 'WARNING: Config version %s not found.\n' "$node_version" >&2
			printf '  --force: falling back to current version categories.\n' >&2
			fallback_ver=$(cfg_config_version_get_current 2>/dev/null) || fallback_ver=""
			[ -z "$fallback_ver" ] && fallback_ver=$(cfg_config_version_latest 2>/dev/null) || fallback_ver=""
			if [ -n "$fallback_ver" ]; then
				cfg_categories_load "$fallback_ver"
			else
				cfg_categories_load
			fi
		else
			printf 'ERROR: Cannot restore node %s.\n' "$current_code" >&2
			printf 'Config version %s not found.\n' "$node_version" >&2
			printf 'Please restore categories-%s.conf to $DOTFILES_LIB_DIR/ and try again.\n' "$node_version" >&2
			printf 'Or use --force to fall back to current version categories.\n' >&2
			exit 1
		fi
	else
		cfg_categories_load "$node_version"
	fi
else
	cfg_categories_load
fi

cfg_get_files_for_state "$git_dir" "$node_type"

to_checkout=("${CFG_TO_INSTALL[@]}" "${CFG_TO_SKIP[@]}")
to_backup=("${CFG_TO_BACKUP[@]}")

# Also include files already tracked that match the node type
mapfile -t all_tracked < <(config ls-tree -r --name-only HEAD 2>/dev/null)
if [ "$node_type" = "server" ]; then
	node_file_list=$(cfg_category_get_files "server")
	to_checkout=()
	for path in "${all_tracked[@]}"; do
		if printf '%s\n' "$node_file_list" | grep -qFx "$path"; then
			to_checkout+=("$path")
		fi
	done
else
	to_checkout=("${all_tracked[@]}")
fi

# ── Pre-deployment report ─────────────────────────────────────────────

printf 'Files to checkout: %d\n' "${#to_checkout[@]}"
printf 'Files to backup:   %d\n' "${#to_backup[@]}"

if [ "$CFG_DRY_RUN" = "true" ]; then
	printf '\n[dry-run] No changes made.\n'
	exit 0
fi

# ── Backup current files ──────────────────────────────────────────────

if ((${#to_backup[@]} > 0)); then
	cfg_create_node_backup_dir "$current_code" "$backup_root"
	cfg_backup_files_to_node "$git_dir" "$current_code" "$backup_root" "${to_backup[@]}"
fi

# ── Checkout files ────────────────────────────────────────────────────

if ((${#to_checkout[@]} > 0)); then
	read -r installed failed <<< "$(cfg_checkout_files "$git_dir" "${to_checkout[@]}")"

	if cfg_should_rollback "$failed" "${#to_checkout[@]}"; then
		cfg_print_rollback_reason "$failed" "${#to_checkout[@]}"
		if [ -d "$backup_root/nodes/$current_code/backup" ]; then
			mapfile -t backup_paths < <(find "$backup_root/nodes/$current_code/backup" -type f -printf '%P\n' 2>/dev/null)
			if ((${#backup_paths[@]} > 0)); then
				cfg_rollback_from_backup "$backup_root/nodes/$current_code/backup" "${backup_paths[@]}"
			fi
		fi
		exit 1
	fi
else
	installed=0
	failed=0
fi

# ── Record deployed files in node ─────────────────────────────────────

node_files_dir="$backup_root/nodes/$current_code/files"
mkdir -p "$node_files_dir"

for path in "${to_checkout[@]}"; do
	if [ -e "$HOME/$path" ] || [ -L "$HOME/$path" ]; then
		mkdir -p "$node_files_dir/$(dirname "$path")"
		cp -a "$HOME/$path" "$node_files_dir/$path" 2>/dev/null || true
	fi
done

# ── Record checkout state ─────────────────────────────────────────────

cfg_record_checkout_state "$git_dir"

# ── Update deploy status ──────────────────────────────────────────────

cfg_deploy_status_set "deployed"

# ── Summary ───────────────────────────────────────────────────────────

printf '\n=== Deploy Complete ===\n'
printf 'Node: %s (%s)\n' "$current_code" "$node_type"
printf 'Files deployed: %d\n' "$installed"
if ((${#to_backup[@]} > 0)); then
	printf 'Files backed up: %d\n' "${#to_backup[@]}"
fi
printf 'Status: deployed\n'
