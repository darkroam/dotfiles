#!/usr/bin/env bash
# commands/autoclean.sh - Permanently delete nodes marked for removal
# Usage: autoclean.sh [--dry-run]
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

cfg_parse_common_args "$@"

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
cfg_nodes_init "$backup_root"

dry_run="${CFG_DRY_RUN:-false}"

head_code=$(cfg_head_get 2>/dev/null) || true
if [ -n "$head_code" ]; then
	head_status=$(cfg_node_get "$head_code" "status" 2>/dev/null) || head_status="active"
	if [ "$head_status" = "marked_for_removal" ]; then
		printf 'Error: HEAD node %s is marked for removal.\n' "$head_code" >&2
		printf 'Switch to another node first with "dotcfg switch <CODE>".\n' >&2
		exit 1
	fi
fi

marked=()
while IFS= read -r code; do
	[ -z "$code" ] && continue
	marked+=("$code")
done < <(cfg_nodes_list_marked)

if [ ${#marked[@]} -eq 0 ]; then
	printf 'No nodes marked for removal.\n'
	exit 0
fi

cfg_nodes_read_index

declare -A to_delete_set=()
declare -A _autoclean_refused=()
declare -A reconnect_plan=()

_autoclean_find_idx() {
	local code="$1"
	local i
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		if [ "${_CFG_NODE_CODES[$i]}" = "$code" ]; then
			printf '%d' "$i"
			return 0
		fi
	done
	return 1
}

_autoclean_evaluate() {
	local code="$1"
	[ -n "${to_delete_set[$code]+x}" ] && return 0
	[ -n "${_autoclean_refused[$code]+x}" ] && return 1

	local idx
	idx=$(_autoclean_find_idx "$code") || return 1
	local node_status="${_CFG_NODE_STATUSES[$idx]:-active}"
	local children_str="${_CFG_NODE_CHILDREN[$idx]}"
	local parent_str="${_CFG_NODE_PARENTS[$idx]}"

	if [ "$node_status" = "marked_for_removal" ]; then
		if [ -n "$children_str" ]; then
			IFS=',' read -ra carr <<< "$children_str"
			for ch in "${carr[@]}"; do
				ch="${ch// /}"
				[ -z "$ch" ] && continue
				_autoclean_evaluate "$ch" || {
					_autoclean_refused[$code]=1
					return 1
				}
			done
		fi
		to_delete_set[$code]=1
		return 0
	fi

	# Active node: process marked children, count remaining active
	local -a active_after=()
	if [ -n "$children_str" ]; then
		IFS=',' read -ra carr <<< "$children_str"
		for ch in "${carr[@]}"; do
			ch="${ch// /}"
			[ -z "$ch" ] && continue
			local ch_idx ch_status
			ch_idx=$(_autoclean_find_idx "$ch") || continue
			ch_status="${_CFG_NODE_STATUSES[$ch_idx]:-active}"
			if [ "$ch_status" = "marked_for_removal" ]; then
				_autoclean_evaluate "$ch" || true
			else
				active_after+=("$ch")
			fi
		done
	fi

	local cnt=${#active_after[@]}
	if (( cnt == 0 )); then
		to_delete_set[$code]=1
		return 0
	elif (( cnt == 1 )); then
		reconnect_plan[${active_after[0]}]="${parent_str:-null}"
		to_delete_set[$code]=1
		return 0
	else
		_autoclean_refused[$code]=1
		return 1
	fi
}

for code in "${marked[@]}"; do
	_autoclean_evaluate "$code" || true
done

to_delete=("${!to_delete_set[@]}")

if [ ${#to_delete[@]} -eq 0 ]; then
	printf 'No nodes can be safely deleted.\n'
	exit 0
fi

# Apply reconnections (in-memory only, batch write later)
for child_code in "${!reconnect_plan[@]}"; do
	cfg_node_set_parent "$child_code" "${reconnect_plan[$child_code]}"
done

printf 'The following nodes will be deleted:\n'
for code in "${to_delete[@]}"; do
	local_idx=$(_autoclean_find_idx "$code") || continue
	local_type="${_CFG_NODE_TYPES[$local_idx]}"
	local_ts="${_CFG_NODE_TIMESTAMPS[$local_idx]}"
	local_ver="${_CFG_NODE_CONFIG_VERSIONS[$local_idx]:-}"
	local_status="${_CFG_NODE_STATUSES[$local_idx]:-active}"
	local_children="${_CFG_NODE_CHILDREN[$local_idx]}"
	desc="leaf node"
	[ -n "$local_children" ] && desc="intermediate node"
	printf '  %s  (%s, v%s, %s)  - %s, %s\n' \
		"$code" "$local_type" "${local_ver:--}" "$local_ts" "$desc" "$local_status"
done

if [ ${#reconnect_plan[@]} -gt 0 ]; then
	printf '\nReconnections:\n'
	for child in "${!reconnect_plan[@]}"; do
		printf '  %s -> parent %s\n' "$child" "${reconnect_plan[$child]}"
	done
fi

if [ "${#to_delete[@]}" -eq 1 ]; then
	printf '\nTotal: %d node will be deleted.\n' "${#to_delete[@]}"
else
	printf '\nTotal: %d nodes will be deleted.\n' "${#to_delete[@]}"
fi

if [ "$dry_run" = "true" ]; then
	printf "\nUse 'dotcfg autoclean' without --dry-run to execute.\n"
	exit 0
fi

printf '\nProceed with deletion? [y/N] '
read -r confirm
if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
	printf 'Aborted.\n'
	exit 0
fi

# Batch mode: single index write at end
_CFG_NODES_BATCH_MODE=true

deleted=0
for code in "${to_delete[@]}"; do
	node_dir="$backup_root/nodes/$code"

	if [ -d "$node_dir/files" ]; then
		while IFS= read -r path; do
			[ -z "$path" ] && continue
			local_target="$HOME/$path"
			if [ -e "$local_target" ] || [ -L "$local_target" ]; then
				rm -f -- "$local_target"
			fi
		done < <(find "$node_dir/files" -type f -printf '%P\n' 2>/dev/null)
	fi

	if [ -d "$node_dir" ]; then
		rm -rf -- "$node_dir"
	fi
	cfg_nodes_delete "$code"
	((deleted++)) || true
done

_CFG_NODES_BATCH_MODE=false
cfg_nodes_write_index

printf '\nDeleted %d node(s).\n' "$deleted"
