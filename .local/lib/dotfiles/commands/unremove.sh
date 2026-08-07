#!/usr/bin/env bash
# commands/unremove.sh - Unmark a node from removal
# Usage: unremove.sh <CODE>
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

code="${1:-}"
if [ -z "$code" ]; then
	printf 'Usage: dotcfg unremove <CODE>\n' >&2
	exit 1
fi

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
cfg_nodes_init "$backup_root"

if ! cfg_node_exists "$code"; then
	printf 'Error: node "%s" not found\n' "$code" >&2
	exit 1
fi

current_status=$(cfg_node_get "$code" "status")
if [ "$current_status" != "marked_for_removal" ]; then
	printf 'Node %s is not marked for removal.\n' "$code"
	exit 0
fi

cfg_node_set_status "$code" "active"
printf 'Node %s restored to active.\n' "$code"
