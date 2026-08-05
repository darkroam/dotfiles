#!/usr/bin/env bash
# utils/checkout.sh - Checkout files and record state for dotfiles commands
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_CHECKOUT_LOADED:-}" ]; then
	return 0
fi
_CFG_CHECKOUT_LOADED=1

cfg_checkout_files() {
	local git_dir="$1"
	shift
	local files=("$@")

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
