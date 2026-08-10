#!/usr/bin/env bats
# commands-lifecycle.bats - Integration tests for lifecycle commands
# TC-CL01 through TC-CL07

load helpers.bash

NODES_LIB="$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
REMOVE_SH="$DOTFILES_ROOT/.local/lib/dotfiles/commands/remove.sh"
UNREMOVE_SH="$DOTFILES_ROOT/.local/lib/dotfiles/commands/unremove.sh"
AUTOCLEAN_SH="$DOTFILES_ROOT/.local/lib/dotfiles/commands/autoclean.sh"

setup() {
	setup_test_home
	local test_lib="$HOME/dotfiles-lib"
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$test_lib"
	rm -f -- "$test_lib"/categories-*.conf
	export DOTFILES_LIB_DIR="$test_lib"
	source_nodes_lib
}

source_nodes_lib() {
	unset _CFG_NODES_LOADED
	unset CFG_NODES_DIR CFG_NODES_INDEX CFG_HEAD_FILE CFG_DEPLOY_STATUS_FILE
	unset _CFG_NODE_CODES _CFG_NODE_TYPES _CFG_NODE_TIMESTAMPS _CFG_NODE_PARENTS _CFG_NODE_CHILDREN
	unset _CFG_NODE_CONFIG_VERSIONS _CFG_NODE_STATUSES
	unset _CFG_NODE_INDEX_BY_CODE _CFG_NODES_INDEX_LOADED
	if [ -f "$NODES_LIB" ]; then
		. "$NODES_LIB"
	else
		echo "WARNING: nodes library not found at $NODES_LIB" >&2
		return 1
	fi
}

setup_node_tree() {
	local child_version="${1:-1.0.0}"
	local grandchild_version="${2:-1.1.0}"
	cfg_nodes_init "$HOME/.config-backup"
	local root child1 child2 grandchild
	root=$(cfg_node_create "fresh" "null")
	cfg_head_set "$root"
	child1=$(cfg_node_create "desktop" "$root" "$child_version")
	child2=$(cfg_node_create "server" "$root" "$child_version")
	grandchild=$(cfg_node_create "desktop" "$child1" "$grandchild_version")
	cfg_head_set "$grandchild"
	echo "$root $child1 $child2 $grandchild"
}

init_from_tree() {
	read -r _st_root _st_child1 _st_child2 _st_grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"
}

# ── remove.sh ──────────────────────────────────────────────────────────

@test "TC-CL01: remove.sh marks a node for removal" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	cfg_head_set "$child1"

	run bash "$REMOVE_SH" "$child2"
	[ "$status" -eq 0 ]
	[[ "$output" == *"marked for removal"* ]]

	local status_val
	cfg_nodes_invalidate
	status_val=$(cfg_node_get "$child2" "status")
	[ "$status_val" = "marked_for_removal" ]
}

@test "TC-CL01b: remove.sh refuses to mark HEAD node" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	run bash "$REMOVE_SH" "$grandchild"
	[ "$status" -ne 0 ]
	[[ "$output" == *"HEAD"* ]] || [[ "$output" == *"current"* ]]
}

@test "TC-CL01c: remove.sh refuses to remove fresh root node" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	run bash "$REMOVE_SH" "$root"
	[ "$status" -ne 0 ]
	[[ "$output" == *"root"* ]] || [[ "$output" == *"fresh"* ]]
}

@test "TC-CL01d: remove.sh refuses node with active children" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	cfg_head_set "$child2"

	run bash "$REMOVE_SH" "$child1"
	[ "$status" -ne 0 ]
	[[ "$output" == *"active children"* ]]
}

@test "TC-CL01e: remove.sh reports already marked" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	cfg_head_set "$child1"
	cfg_node_set_status "$child2" "marked_for_removal"

	run bash "$REMOVE_SH" "$child2"
	[ "$status" -eq 0 ]
	[[ "$output" == *"already marked"* ]]
}

# ── unremove.sh ────────────────────────────────────────────────────────

@test "TC-CL02: unremove.sh restores a marked node" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	cfg_node_set_status "$child2" "marked_for_removal"

	run bash "$UNREMOVE_SH" "$child2"
	[ "$status" -eq 0 ]
	[[ "$output" == *"restored to active"* ]]

	local status_val
	cfg_nodes_invalidate
	status_val=$(cfg_node_get "$child2" "status")
	[ "$status_val" = "active" ]
}

@test "TC-CL02b: unremove.sh reports node not marked" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	run bash "$UNREMOVE_SH" "$child2"
	[ "$status" -eq 0 ]
	[[ "$output" == *"not marked"* ]]
}

@test "TC-CL02c: unremove.sh errors on unknown node" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	run bash "$UNREMOVE_SH" "nonexist"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not found"* ]]
}

# ── autoclean.sh ───────────────────────────────────────────────────────

@test "TC-CL03: autoclean.sh --dry-run previews deletion" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	cfg_head_set "$child1"
	cfg_node_set_status "$child2" "marked_for_removal"

	run bash "$AUTOCLEAN_SH" "--dry-run"
	[ "$status" -eq 0 ]
	[[ "$output" == *"$child2"* ]]
	[[ "$output" == *"dry-run"* ]] || [[ "$output" == *"will be deleted"* ]]

	cfg_node_exists "$child2"
}

@test "TC-CL04: autoclean.sh deletes marked nodes" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	cfg_head_set "$child1"
	cfg_node_set_status "$child2" "marked_for_removal"

	mkdir -p "$HOME/.config-backup/nodes/$child2/backup"
	echo "test" > "$HOME/.config-backup/nodes/$child2/backup/testfile"

	run bash -c 'echo "y" | bash "$1"' _ "$AUTOCLEAN_SH"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Deleted"* ]]

	cfg_nodes_invalidate
	! cfg_node_exists "$child2"
	[ ! -d "$HOME/.config-backup/nodes/$child2" ]
}

@test "TC-CL04b: autoclean.sh reports no marked nodes" {
	read -r root child1 child2 grandchild <<< "$(setup_node_tree)"
	cfg_nodes_init "$HOME/.config-backup"

	run bash "$AUTOCLEAN_SH"
	[ "$status" -eq 0 ]
	[[ "$output" == *"No nodes marked"* ]]
}

# ── dotcfg categories ──────────────────────────────────────────────────

TEST_VERSION_FILES=()

create_test_version_file() {
	local version="$1"
	local name="${2:-}"
	local conf="$DOTFILES_LIB_DIR/categories-${version}.conf"
	{
		printf '# VERSION = %s\n' "$version"
		[ -n "$name" ] && printf '# NAME = %s\n' "$name"
		printf '\n'
		printf 'category = macos\n'
		printf '+ .bashrc\n'
		printf '+ .zshrc\n'
		printf '\n'
		printf 'category = min\n'
		printf 'include = macos\n'
		printf '+ .custom.el\n'
	} > "$conf"
	TEST_VERSION_FILES+=("$conf")
}

teardown() {
	for f in "${TEST_VERSION_FILES[@]}"; do
		rm -f "$f"
	done
	teardown_test_home
}

@test "TC-CL05: dotcfg categories list shows versions" {
	create_test_version_file "95.0.0" "Initial"
	create_test_version_file "95.1.0" "Update"

	run run_dotcfg categories list
	[ "$status" -eq 0 ]
	[[ "$output" == *"95.0.0"* ]]
	[[ "$output" == *"95.1.0"* ]]
}

@test "TC-CL06: dotcfg categories show displays version details" {
	create_test_version_file "94.0.0" "Test Config"

	run run_dotcfg categories show "94.0.0"
	[ "$status" -eq 0 ]
	[[ "$output" == *"94.0.0"* ]]
	[[ "$output" == *"macos"* ]] || [[ "$output" == *"Categories"* ]]
}

@test "TC-CL07: dotcfg categories current shows global version" {
	mkdir -p "$HOME/.config-backup"
	echo "95.0.0" > "$HOME/.config-backup/CURRENT_CONFIG_VERSION"

	run run_dotcfg categories current
	[ "$status" -eq 0 ]
	[[ "$output" == *"95.0.0"* ]]
}

@test "TC-CL07b: dotcfg categories switch updates global version" {
	create_test_version_file "95.0.0"
	create_test_version_file "95.1.0" "Test Switch"
	mkdir -p "$HOME/.config-backup"
	echo "95.0.0" > "$HOME/.config-backup/CURRENT_CONFIG_VERSION"

	run run_dotcfg categories switch "95.1.0"
	[ "$status" -eq 0 ]

	local current
	current=$(<"$HOME/.config-backup/CURRENT_CONFIG_VERSION")
	current="${current%%$'\n'*}"
	[ "$current" = "95.1.0" ]
}
