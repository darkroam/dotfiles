#!/usr/bin/env bash
# utils/args.sh - Common argument parsing for dotfiles commands
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_ARGS_LOADED:-}" ]; then
	return 0
fi
_CFG_ARGS_LOADED=1

CFG_DRY_RUN=false
CFG_FORCE=false
CFG_REINSTALL=false
CFG_AUTO_STASH=false
CFG_LATEST=false
CFG_YES=false
CFG_REMAINING_ARGS=()

# cfg_parse_common_args [args...]
# Parses shared command flags into CFG_* globals and preserves unknown args in
# CFG_REMAINING_ARGS. Returns zero after all arguments are classified.
cfg_parse_common_args() {
	CFG_DRY_RUN=false
	CFG_FORCE=false
	CFG_REINSTALL=false
	CFG_AUTO_STASH=false
	CFG_LATEST=false
	CFG_YES=false
	CFG_REMAINING_ARGS=()

	local arg
	for arg in "$@"; do
		case "$arg" in
			--dry-run)   CFG_DRY_RUN=true ;;
			--force)     CFG_FORCE=true ;;
			--reinstall) CFG_REINSTALL=true ;;
			--auto-stash) CFG_AUTO_STASH=true ;;
			--latest)    CFG_LATEST=true ;;
			--yes|-y)    CFG_YES=true ;;
			*)           CFG_REMAINING_ARGS+=("$arg") ;;
		esac
	done
}
