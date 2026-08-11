#!/usr/bin/env bash
# commands/check-exclude.sh - Check whether a path matches exclusion rules
# Usage: check-exclude.sh <path>
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

target="${1:-}"
if [ -z "$target" ]; then
	printf 'Error: path is required.\n' >&2
	exit 1
fi

# Normalize: strip $HOME prefix if given as absolute path
case "$target" in
	"$HOME"/*) target="${target#"$HOME"/}" ;;
	"$HOME") target="" ;;
esac
target="${target#./}"

format_rule() {
	local rule="$1"
	rule="${rule%\*}"
	printf '%s/%s' '~' "$rule"
}

if [ -z "$target" ]; then
	printf 'Error: please provide a path relative to $HOME\n' >&2
	exit 1
fi

if reason=$(fresh_exclude_reason "$target"); then
	case "$reason" in
		hardcoded:*)
			printf 'Path is excluded by hardcoded rule: %s\n' "$(format_rule "${reason#hardcoded: }")"
			;;
		exclude.conf:*)
			printf 'Path is excluded by exclude.conf: %s\n' "$(format_rule "${reason#exclude.conf: }")"
			;;
		*)
			printf 'Path is excluded: %s\n' "$reason"
			;;
	esac
	exit 0
else
	printf 'Path is NOT excluded.\n'
	exit 1
fi
