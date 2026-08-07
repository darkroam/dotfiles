#!/usr/bin/env bash
# commands/remove.sh - Mark a node for removal
# Usage: remove.sh <CODE>
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

code="${1:-}"
if [ -z "$code" ]; then
	printf 'Usage: dotcfg remove <CODE>\n' >&2
	exit 1
fi

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
cfg_nodes_init "$backup_root"

if ! cfg_node_exists "$code"; then
	printf 'Error: node "%s" not found\n' "$code" >&2
	exit 1
fi

current_status=$(cfg_node_get "$code" "status")
if [ "$current_status" = "marked_for_removal" ]; then
	printf 'Node %s is already marked for removal.\n' "$code"
	exit 0
fi

node_type=$(cfg_node_get "$code" "type")
if [ "$node_type" = "fresh" ]; then
	printf 'Error: Cannot remove root node (fresh).\n' >&2
	exit 1
fi

head_code=$(cfg_head_get 2>/dev/null) || true
if [ "$head_code" = "$code" ]; then
	printf 'Error: Cannot remove current HEAD node. Please switch to another node first.\n' >&2
	exit 1
fi

children=$(cfg_node_get "$code" "children" 2>/dev/null) || true
if [ -n "$children" ]; then
	cfg_nodes_read_index
	active_children=()
	IFS=',' read -ra carr <<< "$children"
	for ch in "${carr[@]}"; do
		ch="${ch// /}"
		[ -z "$ch" ] && continue
		ch_status=$(cfg_node_get "$ch" "status" 2>/dev/null) || ch_status="active"
		if [ "$ch_status" = "active" ]; then
			active_children+=("$ch")
		fi
	done
	if [ ${#active_children[@]} -gt 0 ]; then
		printf 'Error: Cannot remove node with active children.\n' >&2
		printf '  Active children: %s\n' "$(IFS=', '; echo "${active_children[*]}")" >&2
		printf "  Remove children first or use 'dotcfg autoclean'.\n" >&2
		exit 1
	fi
fi

cfg_node_set_status "$code" "marked_for_removal"
printf 'Node %s marked for removal.\n' "$code"
printf 'Run "dotcfg autoclean" to permanently delete marked nodes.\n'
