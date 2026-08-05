#!/usr/bin/env bash
# utils/repo.sh - Repository setup (clone or reuse) for dotfiles commands
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_REPO_LOADED:-}" ]; then
	return 0
fi
_CFG_REPO_LOADED=1

CFG_GIT_DIR=""
CFG_USE_EXISTING=false
CFG_TEMP_DIR=""

cfg_cleanup_temp_dir() {
	if [ -n "$CFG_TEMP_DIR" ] && { [ -e "$CFG_TEMP_DIR" ] || [ -L "$CFG_TEMP_DIR" ]; }; then
		rm -rf -- "$CFG_TEMP_DIR"
	fi
}

cfg_setup_repository() {
	local current_state="$1"
	local force="${2:-false}"
	local repository="${3:-${DOTFILES_REPOSITORY:-git@github.com:darkroam/dotfiles.git}}"
	local final_git_dir="${4:-$HOME/.cfg}"

	CFG_GIT_DIR=""
	CFG_USE_EXISTING=false
	CFG_TEMP_DIR=""

	if [ "$current_state" = "fresh" ] || [ "$force" = true ]; then
		printf 'Cloning repository...\n'
		CFG_TEMP_DIR=$(mktemp -d "$HOME/.cfg.installing.XXXXXX")
		git clone --bare "$repository" "$CFG_TEMP_DIR"
		CFG_GIT_DIR="$CFG_TEMP_DIR"

		printf 'Validating cloned repository...\n'
		cfg_validate "$CFG_GIT_DIR"
		if [ "$CFG_STATE" != "valid" ]; then
			printf 'ERROR: Cloned repository failed validation (state: %s)\n' "$CFG_STATE" >&2
			printf 'This could indicate:\n' >&2
			printf '  - Repository URL is incorrect\n' >&2
			printf '  - Repository is corrupted\n' >&2
			printf '  - Network issue during clone\n' >&2
			return 1
		fi
		if [ "$CFG_IS_OURS" != "true" ]; then
			printf 'ERROR: Cloned repository is not the dotfiles repository\n' >&2
			printf 'Remote URL: %s\n' "$CFG_REMOTE_URL" >&2
			return 1
		fi
		printf 'Repository validation passed.\n'
	else
		CFG_USE_EXISTING=true
		CFG_GIT_DIR="$final_git_dir"

		printf '\nFetching updates from remote...\n'
		if ! git --git-dir="$CFG_GIT_DIR/" --work-tree="$HOME" fetch origin 2>/dev/null; then
			printf 'WARNING: Could not fetch updates (network or SSH issue).\n'
			printf 'Continuing with local repository state.\n'
		fi
	fi
}

cfg_activate_repository() {
	local final_git_dir="${1:-$HOME/.cfg}"

	if [ "$CFG_USE_EXISTING" = false ] && [ -n "$CFG_TEMP_DIR" ]; then
		if ! mv -- "$CFG_TEMP_DIR" "$final_git_dir"; then
			printf 'Failed to activate %s.\n' "$final_git_dir" >&2
			return 1
		fi
		CFG_TEMP_DIR=""
		CFG_GIT_DIR="$final_git_dir"
	fi
}
