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
CFG_REMOTE_FETCH_REFSPEC='+refs/heads/*:refs/remotes/origin/*'

# cfg_configure_remote_tracking [git_dir] [fetch_missing]
# Keeps the bare work-tree repository's current branch comparable with origin.
cfg_configure_remote_tracking() {
	local git_dir="${1:-$HOME/.cfg}"
	local fetch_missing="${2:-false}"
	local branch=""

	git --git-dir="$git_dir/" config --get remote.origin.url >/dev/null 2>&1 || return 0
	if ! git --git-dir="$git_dir/" config --get-all remote.origin.fetch 2>/dev/null |
		grep -Fqx -- "$CFG_REMOTE_FETCH_REFSPEC"; then
		git --git-dir="$git_dir/" config --add remote.origin.fetch "$CFG_REMOTE_FETCH_REFSPEC" || return 1
	fi

	branch=$(git --git-dir="$git_dir/" symbolic-ref --short -q HEAD 2>/dev/null) || branch=""
	[ -n "$branch" ] || return 0
	git --git-dir="$git_dir/" config "branch.$branch.remote" origin || return 1
	git --git-dir="$git_dir/" config "branch.$branch.merge" "refs/heads/$branch" || return 1

	if [ "$fetch_missing" = true ] &&
		! git --git-dir="$git_dir/" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		git --git-dir="$git_dir/" fetch origin >/dev/null 2>&1 || return 1
	fi
}

# cfg_cleanup_temp_dir
# Removes the temporary clone directory created by repository setup.
cfg_cleanup_temp_dir() {
	if [ -n "$CFG_TEMP_DIR" ] && { [ -e "$CFG_TEMP_DIR" ] || [ -L "$CFG_TEMP_DIR" ]; }; then
		rm -rf -- "$CFG_TEMP_DIR"
	fi
}

# cfg_setup_repository <current_state> [force] [repository] [git_dir]
# Clones or selects the repository and validates its identity.
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
		git clone --bare --config "remote.origin.fetch=$CFG_REMOTE_FETCH_REFSPEC" \
			"$repository" "$CFG_TEMP_DIR"
		CFG_GIT_DIR="$CFG_TEMP_DIR"
		cfg_configure_remote_tracking "$CFG_GIT_DIR"

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
		cfg_configure_remote_tracking "$CFG_GIT_DIR" ||
			printf 'WARNING: Could not configure remote tracking.\n' >&2
		if ! git --git-dir="$CFG_GIT_DIR/" --work-tree="$HOME" fetch origin 2>/dev/null; then
			printf 'WARNING: Could not fetch updates (network or SSH issue).\n'
			printf 'Continuing with local repository state.\n'
		fi
	fi
}

# cfg_activate_repository [git_dir]
# Atomically moves a validated temporary clone into its final location.
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
