#!/usr/bin/env bats
# history-graph.bats - Tests for list and history commands

load helpers.bash

NODES_LIB="$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"

setup() {
	setup_test_home
	source_nodes_lib
}

teardown() {
	teardown_test_home
}

source_nodes_lib() {
	unset _CFG_NODES_LOADED
	. "$NODES_LIB"
}

# ── Helpers ────────────────────────────────────────────────────────────

setup_linear_history() {
	cfg_nodes_init "$HOME/.config-backup"
	local root c1 c2
	root=$(cfg_node_create "fresh" "null")
	c1=$(cfg_node_create "server" "$root")
	c2=$(cfg_node_create "desktop" "$c1")
	cfg_head_set "$c2"
	cfg_deploy_status_set "deployed"
}

setup_branching_history() {
	cfg_nodes_init "$HOME/.config-backup"
	local root c1 c2 c3
	root=$(cfg_node_create "fresh" "null")
	c1=$(cfg_node_create "server" "$root")
	c2=$(cfg_node_create "desktop" "$c1")
	c3=$(cfg_node_create "server" "$root")
	cfg_head_set "$c3"
	cfg_deploy_status_set "deployed"
}

run_dotcfg() {
	bash "$DOTCFG" "$@" 2>&1
}

# ── List Tests ─────────────────────────────────────────────────────────

@test "TC-L01: list shows header row" {
	setup_linear_history
	run run_dotcfg list
	[[ "$output" == *"DEPLOY"* ]]
	[[ "$output" == *"TYPE"* ]]
	[[ "$output" == *"TIME"* ]]
	[[ "$output" == *"CODE"* ]]
}

@test "TC-L02: list shows all nodes" {
	setup_linear_history
	run run_dotcfg list
	[[ "$output" == *"fresh"* ]]
	[[ "$output" == *"server"* ]]
	[[ "$output" == *"desktop"* ]]
}

@test "TC-L03: list marks HEAD node with [*]" {
	setup_linear_history
	run run_dotcfg list
	[[ "$output" == *"[*]"* ]]
}

@test "TC-L04: list shows 8-char codes" {
	setup_linear_history
	run run_dotcfg list
	local code_count
	code_count=$(echo "$output" | grep -oE '[a-z0-9]{8}' | wc -l)
	[ "$code_count" -ge 3 ]
}

@test "TC-L05: list with no nodes shows message" {
	mkdir -p "$HOME/.config-backup/nodes"
	cfg_nodes_init "$HOME/.config-backup"
	run run_dotcfg list
	[[ "$output" == *"No nodes"* ]]
}

# ── History Tests ──────────────────────────────────────────────────────

@test "TC-H01: history shows graph-style node list" {
	setup_linear_history
	run run_dotcfg history
	[[ "$output" == *"*"* ]]
	[[ "$output" == *"fresh"* ]]
}

@test "TC-H02: history marks HEAD with *" {
	setup_linear_history
	run run_dotcfg history
	[[ "$output" == *"*"* ]]
	[[ "$output" == *"HEAD"* ]]
}

@test "TC-H03: history shows all node types" {
	setup_linear_history
	run run_dotcfg history
	[[ "$output" == *"fresh"* ]]
	[[ "$output" == *"server"* ]]
	[[ "$output" == *"desktop"* ]]
}

@test "TC-H04: history shows branching structure" {
	setup_branching_history
	run run_dotcfg history
	[[ "$output" == *"fresh"* ]]
	[[ "$output" == *"server"* ]]
	[[ "$output" == *"desktop"* ]]
}

@test "TC-H05: history with no nodes shows message" {
	mkdir -p "$HOME/.config-backup/nodes"
	cfg_nodes_init "$HOME/.config-backup"
	run run_dotcfg history
	[[ "$output" == *"No history"* ]]
}

@test "TC-H06: history shows deploy status" {
	setup_linear_history
	run run_dotcfg history
	[[ "$output" == *"deployed"* ]]
}
