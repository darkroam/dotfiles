#!/usr/bin/env bash
# utils/checkout.sh - Checkout files and record state for dotfiles commands
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_CHECKOUT_LOADED:-}" ]; then
	return 0
fi
_CFG_CHECKOUT_LOADED=1

# cfg_validate_path_safety <path>
# Validates that a path (after resolving all symlinks) is within $HOME
# Returns 0 if safe, 1 if unsafe
# Prints warning to stderr if unsafe
cfg_validate_path_safety() {
	local path="$1"
	local full_path

	# Handle relative paths (relative to $HOME)
	if [[ "$path" != /* ]]; then
		full_path="$HOME/$path"
	else
		full_path="$path"
	fi

	# If the path exists (as file, dir, or symlink), resolve it
	if [ -e "$full_path" ] || [ -L "$full_path" ]; then
		local resolved
		resolved=$(readlink -f "$full_path" 2>/dev/null) || {
			printf 'WARNING: Cannot resolve path: %s\n' "$path" >&2
			return 1
		}

		# Check if resolved path starts with $HOME/
		# Use ${HOME%/}/ to handle both /home/user and /home/user/ cases
		local home_prefix="${HOME%/}/"
		if [[ "$resolved" != "$HOME" && "$resolved" != "$home_prefix"* ]]; then
			printf 'SECURITY ERROR: Path escapes $HOME boundary\n' >&2
			printf '  Original: %s\n' "$path" >&2
			printf '  Resolved: %s\n' "$resolved" >&2
			printf '  Expected: must start with %s\n' "$HOME" >&2
			return 1
		fi
	fi

	return 0
}

# cfg_validate_paths_batch <path...>
# Validates multiple paths, returns 0 if all safe, 1 if any unsafe
cfg_validate_paths_batch() {
	local paths=("$@")
	local unsafe_count=0

	for path in "${paths[@]}"; do
		if ! cfg_validate_path_safety "$path"; then
			((unsafe_count++)) || true
		fi
	done

	if (( unsafe_count > 0 )); then
		printf '\nABORT: %d path(s) failed safety check\n' "$unsafe_count" >&2
		return 1
	fi

	return 0
}

cfg_checkout_files() {
	local git_dir="$1"
	shift
	local files=("$@")

	# Validate all paths are within $HOME before checkout
	if ! cfg_validate_paths_batch "${files[@]}"; then
		printf '0 %d' "${#files[@]}"
		return 1
	fi

	local config_fn
	config_fn() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

	local installed=0
	local failed=0
	local total=${#files[@]}
	local current=0

	local path
	for path in "${files[@]}"; do
		if config_fn checkout HEAD -- "$path" 2>/dev/null; then
			((installed++)) || true
		else
			((failed++)) || true
		fi
		((current++)) || true
		if (( current % 10 == 0 )) || (( current == total )); then
			printf 'Progress: %d/%d\n' "$current" "$total" >&2
		fi
	done

	printf '%d %d' "$installed" "$failed"
}

cfg_checkout_all_tracked() {
	local git_dir="$1"

	local config_fn
	config_fn() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

	mapfile -t all_files < <(config_fn ls-tree -r --name-only HEAD)
	cfg_checkout_files "$git_dir" "${all_files[@]}"
}

cfg_record_checkout_state() {
	local git_dir="$1"
	local state_file="${2:-$HOME/.cfg-checkout-state}"

	local config_fn
	config_fn() { git --git-dir="$git_dir/" --work-tree="$HOME" "$@"; }

	> "$state_file"
	local path
	while IFS= read -r path; do
		local hash
		hash=$(config_fn show HEAD:"$path" | md5sum | cut -d' ' -f1)
		echo "$path:$hash" >> "$state_file"
	done < <(config_fn ls-tree -r --name-only HEAD)
}
