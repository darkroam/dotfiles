#!/usr/bin/env bats
# nodes-lifecycle.bats - Unit tests for node lifecycle management
# TC-NL01 through TC-NL07

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

# ── Config Version Recording ───────────────────────────────────────────

@test "TC-NL01: cfg_node_create records config_version" {
	cfg_nodes_init
	local code
	code=$(cfg_node_create "desktop" "null" "1.0.0")

	[ -n "$code" ]
	local ver
	ver=$(cfg_node_get "$code" "config_version")
	[ "$ver" = "1.0.0" ]
}

@test "TC-NL01b: cfg_node_create defaults config_version to empty" {
	cfg_nodes_init
	local code
	code=$(cfg_node_create "server" "null")

	local ver
	ver=$(cfg_node_get "$code" "config_version")
	[ -z "$ver" ]
}

# ── Status Management ──────────────────────────────────────────────────

@test "TC-NL02: cfg_node_set_status marks and unmarks nodes" {
	cfg_nodes_init
	local code
	code=$(cfg_node_create "desktop" "null")

	local status
	status=$(cfg_node_get "$code" "status")
	[ "$status" = "active" ]

	cfg_node_set_status "$code" "marked_for_removal"
	status=$(cfg_node_get "$code" "status")
	[ "$status" = "marked_for_removal" ]

	cfg_node_set_status "$code" "active"
	status=$(cfg_node_get "$code" "status")
	[ "$status" = "active" ]
}

@test "TC-NL02b: cfg_node_set_status returns error for unknown code" {
	cfg_nodes_init
	cfg_node_create "fresh" "null"
	run cfg_node_set_status "nonexist" "active"
	[ "$status" -ne 0 ]
}

# ── List Marked Nodes ──────────────────────────────────────────────────

@test "TC-NL03: cfg_nodes_list_marked lists only marked nodes" {
	cfg_nodes_init
	local code1 code2 code3
	code1=$(cfg_node_create "fresh" "null")
	code2=$(cfg_node_create "desktop" "$code1")
	code3=$(cfg_node_create "server" "$code1")

	cfg_node_set_status "$code2" "marked_for_removal"

	local marked
	marked=$(cfg_nodes_list_marked)
	[[ "$marked" == *"$code2"* ]]
	[[ "$marked" != *"$code1"* ]]
	[[ "$marked" != *"$code3"* ]]
}

@test "TC-NL03b: cfg_nodes_list_marked returns empty when none marked" {
	cfg_nodes_init
	cfg_node_create "fresh" "null"
	local marked
	marked=$(cfg_nodes_list_marked)
	[ -z "$marked" ]
}

# ── Node Deletion ──────────────────────────────────────────────────────

@test "TC-NL04: cfg_nodes_delete removes node and updates index" {
	cfg_nodes_init
	local root_code child_code
	root_code=$(cfg_node_create "fresh" "null")
	child_code=$(cfg_node_create "desktop" "$root_code")

	[ "$(cfg_nodes_count)" -eq 2 ]

	cfg_nodes_delete "$child_code"
	[ "$(cfg_nodes_count)" -eq 1 ]

	! cfg_node_exists "$child_code"
	cfg_node_exists "$root_code"

	cfg_nodes_read_index
	local root_children
	root_children=$(cfg_node_get "$root_code" "children")
	[[ "$root_children" != *"$child_code"* ]]
}

@test "TC-NL04b: cfg_nodes_delete returns error for unknown code" {
	cfg_nodes_init
	cfg_node_create "fresh" "null"
	run cfg_nodes_delete "nonexist"
	[ "$status" -ne 0 ]
}

# ── Orphaned Children ──────────────────────────────────────────────────

@test "TC-NL05: cfg_nodes_orphaned_children lists child nodes" {
	cfg_nodes_init
	local root_code child1 child2
	root_code=$(cfg_node_create "fresh" "null")
	child1=$(cfg_node_create "desktop" "$root_code")
	child2=$(cfg_node_create "server" "$root_code")

	local children
	children=$(cfg_nodes_orphaned_children "$root_code")
	[[ "$children" == *"$child1"* ]]
	[[ "$children" == *"$child2"* ]]
}

@test "TC-NL05b: cfg_nodes_orphaned_children returns empty for leaf node" {
	cfg_nodes_init
	local root_code child_code
	root_code=$(cfg_node_create "fresh" "null")
	child_code=$(cfg_node_create "desktop" "$root_code")

	local children
	children=$(cfg_nodes_orphaned_children "$child_code")
	[ -z "$children" ]
}

# ── Index Persistence with New Fields ──────────────────────────────────

@test "TC-NL06: index.json read/write preserves config_version and status" {
	cfg_nodes_init
	local code
	code=$(cfg_node_create "desktop" "null" "2.0.0")
	cfg_node_set_status "$code" "marked_for_removal"

	cfg_nodes_invalidate
	cfg_nodes_read_index
	[ "${#_CFG_NODE_CODES[@]}" -eq 1 ]
	[ "${_CFG_NODE_CONFIG_VERSIONS[0]}" = "2.0.0" ]
	[ "${_CFG_NODE_STATUSES[0]}" = "marked_for_removal" ]

	grep -q '"config_version"' "$CFG_NODES_INDEX"
	grep -q '"status"' "$CFG_NODES_INDEX"
}

# ── Backward Compatibility ─────────────────────────────────────────────

@test "TC-NL07: old index.json without new fields reads with defaults" {
	cfg_nodes_init
	mkdir -p "$CFG_NODES_DIR"
	cat > "$CFG_NODES_INDEX" <<'EOF'
{
  "nodes": [
    {
      "code": "oldnode01",
      "type": "fresh",
      "timestamp": "2026-01-01T00:00:00",
      "parent": null,
      "children": []
    }
  ]
}
EOF

	cfg_nodes_invalidate
	cfg_nodes_read_index
	[ "${#_CFG_NODE_CODES[@]}" -eq 1 ]
	[ "${_CFG_NODE_CODES[0]}" = "oldnode01" ]
	[ "${_CFG_NODE_STATUSES[0]}" = "active" ]
	[ -z "${_CFG_NODE_CONFIG_VERSIONS[0]}" ]

	local status
	status=$(cfg_node_get "oldnode01" "status")
	[ "$status" = "active" ]
}
