#!/usr/bin/env bash
# commands/switch.sh - Unified switch command for desktop/server transitions
# Usage: switch.sh --type=desktop|server [--dry-run] [--reinstall] [--force] [--auto-stash]
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

# ── Parse arguments ────────────────────────────────────────────────────

SWITCH_TYPE=""
remaining_args=()

for arg in "$@"; do
	case "$arg" in
		--type=*) SWITCH_TYPE="${arg#--type=}" ;;
		*)        remaining_args+=("$arg") ;;
	esac
done

if [ -z "$SWITCH_TYPE" ]; then
	printf 'ERROR: --type=desktop|server is required\n' >&2
	exit 1
fi

case "$SWITCH_TYPE" in
	desktop|server) ;;
	*)
		printf 'ERROR: unknown type "%s". Use desktop or server.\n' "$SWITCH_TYPE" >&2
		exit 1
		;;
esac

cfg_parse_common_args "${remaining_args[@]+"${remaining_args[@]}"}"

final_git_dir=$HOME/.cfg
backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
timestamp=$(date +%Y%m%dT%H%M%S)
backup_dir=""

trap cfg_cleanup_temp_dir EXIT

for command_name in git mkdir mv dirname chmod mktemp rm; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'switch.sh requires %s.\n' "$command_name" >&2
		exit 127
	fi
done

# ── Validate existing .cfg ──────────────────────────────────────────────
cfg_validate "$final_git_dir"
cfg_print_validation_result "$final_git_dir"

case "$CFG_STATE" in
	not_git)
		if [ "$CFG_FORCE" = true ]; then
			printf '\n--force: backing up and removing invalid %s\n' "$final_git_dir"
			invalid_backup="$backup_root/invalid-${timestamp}"
			mkdir -p -- "$invalid_backup"
			chmod 700 "$invalid_backup"
			if [ -d "$final_git_dir" ] && [ ! -L "$final_git_dir" ]; then
				mv -- "$final_git_dir" "$invalid_backup/.cfg"
			else
				rm -f -- "$final_git_dir"
			fi
			CFG_STATE="missing"
		else
			printf '\nError: %s exists but is not a valid git repository.\n' "$final_git_dir" >&2
			printf 'Back it up and remove it, then retry. Or use --force to auto-remove.\n' >&2
			exit 1
		fi
		;;
	foreign_repo)
		if [ "$CFG_FORCE" = true ]; then
			printf '\n--force: backing up and removing foreign repo at %s\n' "$final_git_dir"
			foreign_backup="$backup_root/foreign-${timestamp}"
			mkdir -p -- "$foreign_backup"
			chmod 700 "$foreign_backup"
			if [ -d "$final_git_dir" ] && [ ! -L "$final_git_dir" ]; then
				mv -- "$final_git_dir" "$foreign_backup/.cfg"
			else
				rm -f -- "$final_git_dir"
			fi
			CFG_STATE="missing"
		else
			printf '\nError: %s is a git repository but not the dotfiles repository.\n' "$final_git_dir" >&2
			[ -n "$CFG_REMOTE_URL" ] && printf '  Remote: %s\n' "$CFG_REMOTE_URL" >&2
			printf 'Use --force to back it up and replace it.\n' >&2
			exit 1
		fi
		;;
	valid)
		if [ "$CFG_FORCE" = true ]; then
			printf '\n--force: backing up existing valid repository before full clone.\n'
			valid_backup="$backup_root/valid-to-fresh-${timestamp}"
			mkdir -p -- "$valid_backup"
			chmod 700 "$valid_backup"
			if [ -d "$final_git_dir" ] && [ ! -L "$final_git_dir" ]; then
				mv -- "$final_git_dir" "$valid_backup/.cfg"
			else
				rm -f -- "$final_git_dir"
			fi
			CFG_STATE="missing"
		fi
		;;
	missing)
		;;
esac

# ── Detect current state ────────────────────────────────────────────────
current_state=$(cfg_detect_state "$final_git_dir")
target_state="$SWITCH_TYPE"

if [ "$CFG_STATE" = "valid" ]; then
	case "$current_state" in
		desktop)
			if [ "$target_state" = "desktop" ] && [ "$CFG_REINSTALL" = false ]; then
				printf 'Already in desktop mode.\n'
				printf 'Options:\n'
				printf '  1. Reinstall (overwrite current configuration)\n'
				printf '  2. Cancel and exit\n'
				printf '\nWhat would you like to do? [1/2] '
				read -r choice
				case "$choice" in
					1|y|Y|yes) CFG_REINSTALL=true ;;
					*) printf 'Aborted.\n'; exit 0 ;;
				esac
			fi
			;;
		server)
			if [ "$target_state" = "server" ] && [ "$CFG_REINSTALL" = false ]; then
				printf 'Already in server mode.\n'
				printf 'Options:\n'
				printf '  1. Reinstall (overwrite current configuration)\n'
				printf '  2. Cancel and exit\n'
				printf '\nWhat would you like to do? [1/2] '
				read -r choice
				case "$choice" in
					1|y|Y|yes) CFG_REINSTALL=true ;;
					*) printf 'Aborted.\n'; exit 0 ;;
				esac
			fi
			;;
		fresh)
			printf 'Existing repository found. Proceeding with install...\n'
			;;
	esac
else
	printf 'No existing installation found. Proceeding with fresh install...\n'
fi

# ── Clone or reuse repository ───────────────────────────────────────────
if [ "$CFG_STATE" = "valid" ] && [ "$CFG_FORCE" = false ]; then
	CFG_USE_EXISTING=true
	CFG_GIT_DIR="$final_git_dir"
	printf '\nFetching updates from remote...\n'
	if ! git --git-dir="$CFG_GIT_DIR/" --work-tree="$HOME" fetch origin 2>/dev/null; then
		printf 'WARNING: Could not fetch updates (network or SSH issue).\n'
		printf 'Continuing with local repository state.\n'
	fi
else
	cfg_setup_repository "$current_state" "$CFG_FORCE" \
		"${DOTFILES_REPOSITORY:-git@github.com:darkroam/dotfiles.git}" "$final_git_dir"
fi

git_dir="$CFG_GIT_DIR"
config() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

config rev-parse --verify HEAD >/dev/null

# ── Analyze files ───────────────────────────────────────────────────────
printf '\nAnalyzing configurations...\n'

cfg_get_files_for_state "$git_dir" "$target_state"

to_install=("${CFG_TO_INSTALL[@]}")
to_backup=("${CFG_TO_BACKUP[@]}")
to_skip=("${CFG_TO_SKIP[@]}")

# ── Initialize node system ─────────────────────────────────────────────

cfg_nodes_init "$backup_root"

parent_code=""
if [ -f "$CFG_HEAD_FILE" ]; then
	parent_code=$(cfg_head_get 2>/dev/null) || true
fi

current_version=$(cfg_config_version_get_current 2>/dev/null) || current_version=""

if [ -z "$current_version" ]; then
	current_version=$(cfg_config_version_latest 2>/dev/null) || current_version=""
	[ -n "$current_version" ] && cfg_config_version_set "$current_version"
elif ! cfg_config_version_read "$current_version" >/dev/null 2>&1; then
	fallback_version=$(cfg_config_version_latest 2>/dev/null) || fallback_version=""
	if [ -n "$fallback_version" ]; then
		printf 'WARNING: Config version %s not found, falling back to %s\n' \
			"$current_version" "$fallback_version" >&2
		current_version="$fallback_version"
		cfg_config_version_set "$current_version"
	fi
fi

if [ -z "$parent_code" ]; then
	root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
	if [ -z "$root_code" ]; then
		root_code=$(cfg_node_create "fresh" "null" "$current_version" "${FRESH_ROOT_CODE:-fresh_root}") || exit 1
	fi
	parent_code="$root_code"
	if [ "$CFG_DRY_RUN" != true ]; then
		printf '\nCreating fresh root node backup (mixed mode)...\n'
		fresh_create_root_backup "$git_dir" || printf 'WARNING: fresh root backup failed, continuing\n' >&2
	fi
fi

new_node_code=$(cfg_node_create "$target_state" "$parent_code" "$current_version")

# ── Print pre-installation report ───────────────────────────────────────

if ((${#to_backup[@]} > 0)); then
	backup_dir="$backup_root/nodes/$new_node_code/backup"
fi

printf '\n=== Pre-installation Report ===\n\n'
printf 'Current state: %s\n' "$current_state"
printf 'Target state: %s\n' "$target_state"
printf 'Node code: %s\n' "$new_node_code"
if [ "$CFG_USE_EXISTING" = true ]; then
	printf 'Repository: reusing existing (skipped clone)\n'
fi

printf '\nFiles to install (new): %d\n' "${#to_install[@]}"
for path in "${to_install[@]}"; do
	printf '  + %s\n' "$path"
done

printf '\nFiles to backup (modified/untracked): %d\n' "${#to_backup[@]}"
for path in "${to_backup[@]}"; do
	printf '  ~ %s\n' "$path"
done

printf '\nFiles to skip (identical to repo): %d\n' "${#to_skip[@]}"
for path in "${to_skip[@]}"; do
	printf '  = %s\n' "$path"
done

if [ "$CFG_DRY_RUN" = true ]; then
	printf '\n=== DRY RUN MODE - No changes will be made ===\n'
	cfg_nodes_read_index
	local_i=-1
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		if [ "${_CFG_NODE_CODES[$i]}" = "$new_node_code" ]; then
			local_i=$i
			break
		fi
	done
	if [ "$local_i" -ge 0 ]; then
		unset '_CFG_NODE_CODES[$local_i]' '_CFG_NODE_TYPES[$local_i]' \
			'_CFG_NODE_TIMESTAMPS[$local_i]' '_CFG_NODE_PARENTS[$local_i]' \
			'_CFG_NODE_CHILDREN[$local_i]' '_CFG_NODE_CONFIG_VERSIONS[$local_i]' \
			'_CFG_NODE_STATUSES[$local_i]'
		_CFG_NODE_CODES=("${_CFG_NODE_CODES[@]}")
		_CFG_NODE_TYPES=("${_CFG_NODE_TYPES[@]}")
		_CFG_NODE_TIMESTAMPS=("${_CFG_NODE_TIMESTAMPS[@]}")
		_CFG_NODE_PARENTS=("${_CFG_NODE_PARENTS[@]}")
		_CFG_NODE_CHILDREN=("${_CFG_NODE_CHILDREN[@]}")
		_CFG_NODE_CONFIG_VERSIONS=("${_CFG_NODE_CONFIG_VERSIONS[@]}")
		_CFG_NODE_STATUSES=("${_CFG_NODE_STATUSES[@]}")
		cfg_nodes_write_index
		rm -rf "$backup_root/nodes/$new_node_code"
	fi
	exit 0
fi

printf '\nProceed with installation? [y/N] '
read -r confirm
if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
	printf 'Aborted.\n'
	exit 0
fi

# ── Handle backups ──────────────────────────────────────────────────────
if ((${#to_backup[@]})); then
	if [ "$target_state" = "desktop" ] && [ "$CFG_AUTO_STASH" = true ]; then
		printf '\n--auto-stash: backing up %d conflicting files without prompting...\n' "${#to_backup[@]}"
	fi
	cfg_create_node_backup_dir "$new_node_code" "$backup_root"
	cfg_backup_files_to_node "$git_dir" "$new_node_code" "$backup_root" "${to_backup[@]}"
	backup_dir="$backup_root/nodes/$new_node_code/backup"
fi

# ── Remove desktop-specific files (server only, from desktop) ────────────
if [ "$target_state" = "server" ] && [ "$current_state" = "desktop" ]; then
	printf '\nRemoving desktop-specific files...\n'
	while IFS= read -r path; do
		[ -z "$path" ] && continue
		full_path="$HOME/$path"
		if [ -L "$full_path" ]; then
			rm -f -- "$full_path"
			printf 'Removed symlink: %s\n' "$path"
		elif [ -f "$full_path" ]; then
			rm -f -- "$full_path"
			printf 'Removed file: %s\n' "$path"
		elif [ -d "$full_path" ]; then
			rm -rf -- "$full_path"
			printf 'Removed directory: %s\n' "$path"
		fi
	done < <(cfg_category_diff "server" "desktop")
fi

# ── Checkout configurations ─────────────────────────────────────────────
printf '\nInstalling configurations...\n'

checkout_list=("${to_install[@]}" "${to_backup[@]}")
if [ ${#checkout_list[@]} -gt 0 ]; then
	result=$(cfg_checkout_files "$git_dir" "${checkout_list[@]}")
	installed=${result% *}
	skipped_checkout=${result#* }
	total=${#checkout_list[@]}

	if cfg_should_rollback "$skipped_checkout" "$total"; then
		cfg_print_rollback_reason "$skipped_checkout" "$total"
		if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
			mapfile -t backup_paths < <(find "$backup_dir" -type f -printf '%P\n' 2>/dev/null)
			if ((${#backup_paths[@]} > 0)); then
				cfg_rollback_from_backup "$backup_dir" "${backup_paths[@]}"
			fi
		fi
		exit 1
	fi
else
	installed=0
	skipped_checkout=0
fi

# ── Activate repository ─────────────────────────────────────────────────
cfg_activate_repository "$final_git_dir"
git_dir="$CFG_GIT_DIR"

git --git-dir="$git_dir/" --work-tree="$HOME" config status.showUntrackedFiles no

cfg_record_checkout_state "$git_dir"

# For server mode, rewrite state file to only include server files
if [ "$target_state" = "server" ]; then
	server_file_list=$(cfg_category_get_files "server")
	state_file="$HOME/.cfg-checkout-state"
	server_state_file="${state_file}.tmp"
	> "$server_state_file"
	while IFS=: read -r path hash; do
		[ -z "$path" ] && continue
		if printf '%s\n' "$server_file_list" | grep -qFx "$path"; then
			echo "$path:$hash" >> "$server_state_file"
		fi
	done < "$state_file"
	mv -- "$server_state_file" "$state_file"
fi

# ── Record deployed files in node ──────────────────────────────────────

node_files_dir="$backup_root/nodes/$new_node_code/files"
mkdir -p "$node_files_dir"

if [ "$target_state" = "server" ]; then
	server_file_list="${server_file_list:-$(cfg_category_get_files "server")}"
fi

mapfile -t all_tracked < <(config ls-tree -r --name-only HEAD 2>/dev/null)
for path in "${all_tracked[@]}"; do
	if [ "$target_state" = "server" ]; then
		if ! printf '%s\n' "$server_file_list" | grep -qFx "$path"; then
			continue
		fi
	fi
	if [ -e "$HOME/$path" ] || [ -L "$HOME/$path" ]; then
		mkdir -p "$node_files_dir/$(dirname "$path")"
		cp -a "$HOME/$path" "$node_files_dir/$path" 2>/dev/null || true
	fi
done

# ── Update HEAD and deploy status ──────────────────────────────────────

cfg_head_set "$new_node_code"
cfg_deploy_status_set "deployed"

# ── Summary ───────────────────────────────────────────────────────────

printf '\n=== %s Installation Complete ===\n' "$(printf '%s' "$target_state" | tr '[:lower:]' '[:upper:]' | head -c 1)$(printf '%s' "$target_state" | tail -c +2)"
printf 'Node: %s\n' "$new_node_code"
printf 'Installed: %d files\n' "$installed"
if ((skipped_checkout > 0)); then
	printf 'Skipped (checkout failed): %d files\n' "$skipped_checkout"
fi
printf 'Skipped (identical): %d files\n' "${#to_skip[@]}"
if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
	printf 'Backed up: %d files to node %s\n' "${#to_backup[@]}" "$new_node_code"
fi
if [ "$CFG_USE_EXISTING" = true ]; then
	printf '\n%s configuration updated from existing repository.\n' "$target_state"
else
	printf '\nFull %s configuration has been installed.\n' "$target_state"
fi
