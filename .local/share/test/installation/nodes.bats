#!/usr/bin/env bats
# nodes.bats - Unit tests for utils/nodes.sh

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
	unset _CFG_NODE_INDEX_BY_CODE _CFG_NODES_INDEX_LOADED
	if [ -f "$NODES_LIB" ]; then
		. "$NODES_LIB"
	else
		echo "WARNING: nodes library not found at $NODES_LIB" >&2
		return 1
	fi
}

@test "TC-N29: node lookups use the cached code index" {
	cfg_nodes_init
	local root child
	root=$(cfg_node_create "fresh" "null" "bootstrap")
	child=$(cfg_node_create "full" "$root" "1.0.0")
	cfg_nodes_read_index
	cfg_nodes_invalidate
	cfg_nodes_read_index

	[ "${_CFG_NODE_INDEX_BY_CODE[$root]}" = "0" ]
	[ "${_CFG_NODE_INDEX_BY_CODE[$child]}" = "1" ]
	[ "$(cfg_node_get "$child" type)" = "full" ]
	cfg_node_set_status "$child" marked_for_removal
	[ "$(cfg_node_get "$child" status)" = "marked_for_removal" ]
}

@test "TC-N30: cache invalidation reloads an externally changed index" {
	cfg_nodes_init
	local root
	root=$(cfg_node_create "fresh" "null" "bootstrap")
	cfg_nodes_read_index
	cfg_node_exists "$root"

	printf '{\n  "nodes": []\n}\n' > "$CFG_NODES_INDEX"
	cfg_nodes_invalidate

	[ "$(cfg_nodes_count)" -eq 0 ]
	! cfg_node_exists "$root"
}

# ── Initialization ─────────────────────────────────────────────────────

@test "TC-N01: cfg_nodes_init creates nodes directory" {
	cfg_nodes_init "$HOME/.config-backup"
	[ -d "$HOME/.config-backup/nodes" ]
	[ "$CFG_NODES_DIR" = "$HOME/.config-backup/nodes" ]
	[ "$CFG_NODES_INDEX" = "$HOME/.config-backup/nodes/index.json" ]
	[ "$CFG_HEAD_FILE" = "$HOME/.config-backup/HEAD" ]
	[ "$CFG_DEPLOY_STATUS_FILE" = "$HOME/.config-backup/DEPLOY_STATUS" ]
}

@test "TC-N02: cfg_nodes_init uses default backup root" {
	cfg_nodes_init
	[ "$CFG_NODES_DIR" = "$HOME/.config-backup/nodes" ]
}

# ── Code Generation ────────────────────────────────────────────────────

@test "TC-N03: cfg_generate_node_code produces 8-char code" {
	cfg_nodes_init
	local code
	code=$(cfg_generate_node_code)
	[ ${#code} -eq 8 ]
	[[ "$code" =~ ^[a-z0-9]+$ ]]
}

@test "TC-N04: cfg_generate_node_code produces unique codes" {
	cfg_nodes_init
	local -a codes=()
	local i code
	for ((i = 0; i < 20; i++)); do
		code=$(cfg_generate_node_code)
		codes+=("$code")
	done

	local unique
	unique=$(printf '%s\n' "${codes[@]}" | sort -u | wc -l)
	[ "$unique" -eq 20 ]
}

# ── Node CRUD ──────────────────────────────────────────────────────────

@test "TC-N05: cfg_node_create creates node with directory structure" {
	cfg_nodes_init
	local code
	code=$(cfg_node_create "fresh" "null")

	[ -n "$code" ]
	[ -d "$CFG_NODES_DIR/$code" ]
	[ -d "$CFG_NODES_DIR/$code/backup" ]
	[ -d "$CFG_NODES_DIR/$code/files" ]
	[ -f "$CFG_NODES_INDEX" ]
}

@test "TC-N06: cfg_node_create records node in index" {
	cfg_nodes_init
	local code
	code=$(cfg_node_create "desktop" "null")

	cfg_nodes_read_index
	[ "${#_CFG_NODE_CODES[@]}" -eq 1 ]
	[ "${_CFG_NODE_CODES[0]}" = "$code" ]
	[ "${_CFG_NODE_TYPES[0]}" = "desktop" ]
	[ "${_CFG_NODE_PARENTS[0]}" = "null" ]
}

@test "TC-N07: cfg_node_create with parent updates parent children" {
	cfg_nodes_init
	local root_code child_code
	root_code=$(cfg_node_create "fresh" "null")
	child_code=$(cfg_node_create "server" "$root_code")

	cfg_nodes_read_index
	[ "${#_CFG_NODE_CODES[@]}" -eq 2 ]

	local root_idx=-1 child_idx=-1
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		[ "${_CFG_NODE_CODES[$i]}" = "$root_code" ] && root_idx=$i
		[ "${_CFG_NODE_CODES[$i]}" = "$child_code" ] && child_idx=$i
	done

	[ "$root_idx" -ge 0 ]
	[ "$child_idx" -ge 0 ]
	[ "${_CFG_NODE_PARENTS[$child_idx]}" = "$root_code" ]
	[[ "${_CFG_NODE_CHILDREN[$root_idx]}" == *"$child_code"* ]]
}

@test "TC-N08: cfg_node_get returns correct field values" {
	cfg_nodes_init
	local code
	code=$(cfg_node_create "server" "null")

	[ "$(cfg_node_get "$code" "type")" = "server" ]
	[ "$(cfg_node_get "$code" "parent")" = "null" ]
	[ -n "$(cfg_node_get "$code" "timestamp")" ]
}

@test "TC-N09: cfg_node_get returns error for unknown code" {
	cfg_nodes_init
	cfg_node_create "fresh" "null"
	run cfg_node_get "nonexist" "type"
	[ "$status" -ne 0 ]
}

@test "TC-N10: cfg_node_exists returns true for existing node" {
	cfg_nodes_init
	local code
	code=$(cfg_node_create "fresh" "null")
	cfg_node_exists "$code"
}

@test "TC-N11: cfg_node_exists returns false for unknown code" {
	cfg_nodes_init
	cfg_node_create "fresh" "null"
	! cfg_node_exists "nonexist"
}

# ── HEAD Management ────────────────────────────────────────────────────

@test "TC-N12: cfg_head_set and cfg_head_get work correctly" {
	cfg_nodes_init
	cfg_head_set "abc12345"
	local head
	head=$(cfg_head_get)
	[ "$head" = "abc12345" ]
}

@test "TC-N13: cfg_head_get returns error when no HEAD" {
	cfg_nodes_init
	run cfg_head_get
	[ "$status" -ne 0 ]
}

@test "TC-N14: cfg_head_set overwrites previous HEAD" {
	cfg_nodes_init
	cfg_head_set "first123"
	cfg_head_set "second45"
	[ "$(cfg_head_get)" = "second45" ]
}

# ── Deploy Status ──────────────────────────────────────────────────────

@test "TC-N15: cfg_deploy_status_set and cfg_deploy_status_get" {
	cfg_nodes_init
	cfg_deploy_status_set "deployed"
	[ "$(cfg_deploy_status_get)" = "deployed" ]
}

@test "TC-N16: cfg_deploy_status_get defaults to uninstalled" {
	cfg_nodes_init
	[ "$(cfg_deploy_status_get)" = "uninstalled" ]
}

@test "TC-N17: cfg_deploy_status_set overwrites previous status" {
	cfg_nodes_init
	cfg_deploy_status_set "deployed"
	cfg_deploy_status_set "uninstalled"
	[ "$(cfg_deploy_status_get)" = "uninstalled" ]
}

# ── Tree Operations ────────────────────────────────────────────────────

@test "TC-N18: cfg_nodes_get_root finds root node" {
	cfg_nodes_init
	local root_code child_code grandchild_code
	root_code=$(cfg_node_create "fresh" "null")
	child_code=$(cfg_node_create "server" "$root_code")
	grandchild_code=$(cfg_node_create "desktop" "$child_code")

	local found_root
	found_root=$(cfg_nodes_get_root)
	[ "$found_root" = "$root_code" ]
}

@test "TC-N19: cfg_nodes_get_root returns error with no nodes" {
	cfg_nodes_init
	run cfg_nodes_get_root
	[ "$status" -ne 0 ]
}

@test "TC-N20: cfg_nodes_ancestors returns chain from node to root" {
	cfg_nodes_init
	local root_code child_code grandchild_code
	root_code=$(cfg_node_create "fresh" "null")
	child_code=$(cfg_node_create "server" "$root_code")
	grandchild_code=$(cfg_node_create "desktop" "$child_code")

	local -a ancestors=()
	while IFS= read -r code; do
		ancestors+=("$code")
	done < <(cfg_nodes_ancestors "$grandchild_code")

	[ "${#ancestors[@]}" -eq 3 ]
	[ "${ancestors[0]}" = "$grandchild_code" ]
	[ "${ancestors[1]}" = "$child_code" ]
	[ "${ancestors[2]}" = "$root_code" ]
}

@test "TC-N21: cfg_nodes_count returns correct count" {
	cfg_nodes_init
	cfg_node_create "fresh" "null"
	cfg_node_create "server" "placeholder"
	[ "$(cfg_nodes_count)" -eq 2 ]
}

@test "TC-N22: cfg_nodes_count returns 0 with no index" {
	cfg_nodes_init
	[ "$(cfg_nodes_count)" -eq 0 ]
}

# ── Index Persistence ──────────────────────────────────────────────────

@test "TC-N23: index survives re-read (write then read)" {
	cfg_nodes_init
	local root_code child_code
	root_code=$(cfg_node_create "fresh" "null")
	child_code=$(cfg_node_create "desktop" "$root_code")

	unset _CFG_NODE_CODES _CFG_NODE_TYPES _CFG_NODE_TIMESTAMPS _CFG_NODE_PARENTS _CFG_NODE_CHILDREN
	_CFG_NODE_CODES=()
	_CFG_NODE_TYPES=()
	_CFG_NODE_TIMESTAMPS=()
	_CFG_NODE_PARENTS=()
	_CFG_NODE_CHILDREN=()

	cfg_nodes_read_index
	[ "${#_CFG_NODE_CODES[@]}" -eq 2 ]

	local found_root=false found_child=false
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		if [ "${_CFG_NODE_CODES[$i]}" = "$root_code" ]; then
			found_root=true
			[ "${_CFG_NODE_TYPES[$i]}" = "fresh" ]
		fi
		if [ "${_CFG_NODE_CODES[$i]}" = "$child_code" ]; then
			found_child=true
			[ "${_CFG_NODE_TYPES[$i]}" = "desktop" ]
			[ "${_CFG_NODE_PARENTS[$i]}" = "$root_code" ]
		fi
	done
	$found_root
	$found_child
}

@test "TC-N24: index.json is valid structure" {
	cfg_nodes_init
	cfg_node_create "fresh" "null"

	[ -f "$CFG_NODES_INDEX" ]
	grep -q '"nodes"' "$CFG_NODES_INDEX"
	grep -q '"code"' "$CFG_NODES_INDEX"
	grep -q '"type"' "$CFG_NODES_INDEX"
	grep -q '"timestamp"' "$CFG_NODES_INDEX"
	grep -q '"parent"' "$CFG_NODES_INDEX"
	grep -q '"children"' "$CFG_NODES_INDEX"
}

# ── Migration Detection ────────────────────────────────────────────────

@test "TC-N25: cfg_nodes_needs_migration returns false with no sessions" {
	mkdir -p "$HOME/.config-backup"
	! cfg_nodes_needs_migration "$HOME/.config-backup"
}

@test "TC-N26: cfg_nodes_needs_migration returns true with old sessions" {
	mkdir -p "$HOME/.config-backup/fresh-to-desktop-20260806T100000"
	cfg_nodes_needs_migration "$HOME/.config-backup"
}

@test "TC-N27: cfg_nodes_needs_migration returns false if index exists" {
	cfg_nodes_init
	cfg_node_create "fresh" "null"
	mkdir -p "$HOME/.config-backup/fresh-to-desktop-20260806T100000"
	! cfg_nodes_needs_migration "$HOME/.config-backup"
}

# ── Branching ──────────────────────────────────────────────────────────

@test "TC-N28: multiple children from same parent" {
	cfg_nodes_init
	local root_code child1 child2
	root_code=$(cfg_node_create "fresh" "null")
	child1=$(cfg_node_create "server" "$root_code")
	child2=$(cfg_node_create "desktop" "$root_code")

	cfg_nodes_read_index
	local root_idx=-1
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		[ "${_CFG_NODE_CODES[$i]}" = "$root_code" ] && root_idx=$i
	done

	local children="${_CFG_NODE_CHILDREN[$root_idx]}"
	[[ "$children" == *"$child1"* ]]
	[[ "$children" == *"$child2"* ]]
}
