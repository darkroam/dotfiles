#!/usr/bin/env bash
# commands/migrate.sh - Migrate old session-based backups to node system
# Usage: migrate.sh [--dry-run]
set -euo pipefail

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"
. "$DOTFILES_LIB_DIR/utils/common.sh"

cfg_parse_common_args "$@"

backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"

if ! cfg_nodes_needs_migration "$backup_root"; then
	if [ -f "$backup_root/nodes/index.json" ]; then
		printf 'Node system already initialized. No migration needed.\n'
	else
		printf 'No old backup sessions found. Nothing to migrate.\n'
	fi
	exit 0
fi

# ── Collect old session directories ────────────────────────────────────

sessions=()
session_types=()

for dir in "$backup_root"/*/; do
	[ -d "$dir" ] || continue
	basename="${dir%/}"
	basename="${basename##*/}"

	case "$basename" in
		nodes|sessions) continue ;;
	esac

	if [[ "$basename" =~ ^(fresh|desktop|server)-to-(fresh|desktop|server)-([0-9]{8}T[0-9]{6})$ ]]; then
		sessions+=("$basename")
		session_types+=("${BASH_REMATCH[2]}")
	fi
done

if [ ${#sessions[@]} -eq 0 ]; then
	printf 'No old backup sessions found. Nothing to migrate.\n'
	exit 0
fi

# ── Sort sessions chronologically ──────────────────────────────────────

sorted_indices=()
while IFS=$'\t' read -r _ts idx; do
	sorted_indices+=("$idx")
done < <(
	for i in "${!sessions[@]}"; do
		ts="${sessions[$i]##*-}"
		printf '%s\t%s\n' "$ts" "$i"
	done | sort -t$'\t' -k1,1
)

# ── Dry-run report ────────────────────────────────────────────────────

if [ "$CFG_DRY_RUN" = true ]; then
	printf '=== Migration Dry Run ===\n\n'
	printf 'Found %d old backup session(s):\n\n' "${#sessions[@]}"
	for i in "${sorted_indices[@]}"; do
		printf '  %s -> %s\n' "${sessions[$i]}" "${session_types[$i]}"
	done
	printf '\nWould create:\n'
	printf '  1 root fresh node\n'
	printf '  %d transition nodes\n' "${#sessions[@]}"
	printf '\nOld sessions would be moved to %s/sessions/\n' "$backup_root"
	exit 0
fi

# ── Initialize node system ────────────────────────────────────────────

cfg_nodes_init "$backup_root"

printf 'Migrating %d old backup session(s) to node system...\n\n' "${#sessions[@]}"

# Create root fresh node
root_code=$(cfg_node_create "fresh" "null")
printf 'Created root node: %s (fresh)\n' "$root_code"

# ── Create nodes for each session ─────────────────────────────────────

parent_code="$root_code"
last_code=""

for i in "${sorted_indices[@]}"; do
	session_name="${sessions[$i]}"
	target_type="${session_types[$i]}"

	session_dir="$backup_root/$session_name"
	manifest="$session_dir/MANIFEST.txt"

	node_code=$(cfg_node_create "$target_type" "$parent_code")

	node_dir="$backup_root/nodes/$node_code"
	mkdir -p "$node_dir/backup" "$node_dir/files"

	if [ -f "$manifest" ]; then
		cp -- "$manifest" "$node_dir/manifest.txt"

		while IFS=$'\t' read -r rel_path md5 status; do
			[[ "$rel_path" =~ ^# ]] && continue
			[ -z "$rel_path" ] && continue

			src="$session_dir/$rel_path"
			dst="$node_dir/backup/$rel_path"
			if [ -e "$src" ]; then
				mkdir -p "$(dirname "$dst")"
				cp -a -- "$src" "$dst"
			fi
		done < "$manifest"
	fi

	printf 'Migrated: %s -> node %s (%s)\n' "$session_name" "$node_code" "$target_type"

	parent_code="$node_code"
	last_code="$node_code"
done

# ── Set HEAD to last node ─────────────────────────────────────────────

if [ -n "$last_code" ]; then
	cfg_head_set "$last_code"
	cfg_deploy_status_set "deployed"
	printf '\nHEAD set to: %s\n' "$last_code"
fi

# ── Move old sessions to sessions/ ────────────────────────────────────

sessions_archive="$backup_root/sessions"
mkdir -p "$sessions_archive"

for session_name in "${sessions[@]}"; do
	mv -- "$backup_root/$session_name" "$sessions_archive/$session_name"
done

printf '\n=== Migration Complete ===\n'
printf 'Nodes created: %d (1 root + %d transitions)\n' "$(( ${#sessions[@]} + 1 ))" "${#sessions[@]}"
printf 'Old sessions archived to: %s\n' "$sessions_archive"
printf 'Run "dotcfg list" to see your nodes.\n'
