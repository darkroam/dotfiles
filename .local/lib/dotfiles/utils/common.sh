#!/usr/bin/env bash
# utils/common.sh - Top-level loader for all dotfiles utilities
# Source this file from command scripts.

if [ -n "${_CFG_COMMON_LOADED:-}" ]; then
	return 0
fi
_CFG_COMMON_LOADED=1

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"

if [ ! -f "$DOTFILES_LIB_DIR/cfg-validate.sh" ]; then
	printf 'ERROR: dotfiles library not found at %s/cfg-validate.sh\n' "$DOTFILES_LIB_DIR" >&2
	exit 1
fi

. "$DOTFILES_LIB_DIR/cfg-validate.sh"
. "$DOTFILES_LIB_DIR/utils/args.sh"
. "$DOTFILES_LIB_DIR/utils/backup.sh"
. "$DOTFILES_LIB_DIR/utils/rollback.sh"
. "$DOTFILES_LIB_DIR/utils/checkout.sh"
. "$DOTFILES_LIB_DIR/utils/repo.sh"
. "$DOTFILES_LIB_DIR/utils/categories.sh"
. "$DOTFILES_LIB_DIR/utils/files.sh"
. "$DOTFILES_LIB_DIR/utils/nodes.sh"
