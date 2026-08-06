#!/usr/bin/env bats
# migration.bats - Tests for old session → node migration

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
}

# ── Helpers ──────────────────────────────────────────────────────────────

# Create a fake old-style backup session directory
# create_old_session <from>-to-<to>-<timestamp> <file1> <file2> ...
create_old_session() {
	local name="$1"
	shift
	local files=("$@")
	local dir="$HOME/.config-backup/$name"
	mkdir -p "$dir"

	printf '# Created: %s\n' "$(date)" > "$dir/MANIFEST.txt"
	printf '# Transition: %s\n' "$name" >> "$dir/MANIFEST.txt"
	printf '#\n# relative_path\tmd5\tstatus\n' >> "$dir/MANIFEST.txt"

	for f in "${files[@]}"; do
		mkdir -p "$(dirname "$dir/$f")"
		printf 'original content for %s\n' "$f" > "$dir/$f"
		local md5
		md5=$(printf 'original content for %s\n' "$f" | md5sum | cut -d' ' -f1)
		printf '%s\t%s\tmodified\n' "$f" "$md5" >> "$dir/MANIFEST.txt"
	done
}

run_migrate() {
	bash "$DOTFILES_ROOT/.local/lib/dotfiles/commands/migrate.sh" "$@" 2>&1
}

assert_node_exists() {
	local code="$1"
	local nodes_dir="$HOME/.config-backup/nodes"
	[ -d "$nodes_dir/$code" ] || {
		echo "expected node directory to exist: $code" >&2
		return 1
	}
}

assert_head_is() {
	local expected="$1"
	local actual
	actual=$(<"$HOME/.config-backup/HEAD")
	actual="${actual%%$'\n'*}"
	[ "$actual" = "$expected" ] || {
		echo "expected HEAD=$expected, got HEAD=$actual" >&2
		return 1
	}
}

assert_sessions_archived() {
	local count
	count=$(find "$HOME/.config-backup/sessions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
	(( count > 0 )) || {
		echo "expected archived sessions in sessions/" >&2
		return 1
	}
}

assert_session_moved() {
	local name="$1"
	[ -d "$HOME/.config-backup/sessions/$name" ] || {
		echo "expected session archived: sessions/$name" >&2
		return 1
	}
	[ ! -d "$HOME/.config-backup/$name" ] || {
		echo "expected old session directory removed: $name" >&2
		return 1
	}
}

# ── TC-M01: No sessions, no index → nothing to migrate ──────────────────

@test "TC-M01: migrate with no sessions exits cleanly" {
	mkdir -p "$HOME/.config-backup"
	run run_migrate
	[ "$status" -eq 0 ]
	[[ "$output" == *"Nothing to migrate"* ]] || [[ "$output" == *"already initialized"* ]]
}

# ── TC-M02: Already migrated (index exists) → no-op ────────────────────

@test "TC-M02: migrate with existing index is no-op" {
	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	cfg_node_create "fresh" "null" >/dev/null

	run run_migrate
	[ "$status" -eq 0 ]
	[[ "$output" == *"already initialized"* ]]
}

# ── TC-M03: Single session migration ────────────────────────────────────

@test "TC-M03: migrate single session creates root + 1 node" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc" ".zshrc"

	run run_migrate
	[ "$status" -eq 0 ]
	[[ "$output" == *"Migration Complete"* ]]
	[[ "$output" == *"Nodes created: 2"* ]]

	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	cfg_nodes_read_index
	[ ${#_CFG_NODE_CODES[@]} -eq 2 ]
	[ "${_CFG_NODE_TYPES[0]}" = "fresh" ]
	[ "${_CFG_NODE_TYPES[1]}" = "desktop" ]
}

# ── TC-M04: Multiple sessions migrated in order ─────────────────────────

@test "TC-M04: migrate multiple sessions preserves order" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"
	create_old_session "desktop-to-server-20260201T120000" ".tmux.conf"
	create_old_session "server-to-desktop-20260301T120000" ".xinitrc"

	run run_migrate
	[ "$status" -eq 0 ]
	[[ "$output" == *"Nodes created: 4"* ]]

	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	cfg_nodes_read_index
	[ ${#_CFG_NODE_CODES[@]} -eq 4 ]
	[ "${_CFG_NODE_TYPES[0]}" = "fresh" ]
	[ "${_CFG_NODE_TYPES[1]}" = "desktop" ]
	[ "${_CFG_NODE_TYPES[2]}" = "server" ]
	[ "${_CFG_NODE_TYPES[3]}" = "desktop" ]
}

# ── TC-M05: Parent-child chain is correct ───────────────────────────────

@test "TC-M05: migrated nodes have correct parent chain" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"
	create_old_session "desktop-to-server-20260201T120000" ".tmux.conf"

	run run_migrate
	[ "$status" -eq 0 ]

	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	cfg_nodes_read_index

	# Root has null parent
	[ "${_CFG_NODE_PARENTS[0]}" = "null" ]
	# Second node's parent is root
	[ "${_CFG_NODE_PARENTS[1]}" = "${_CFG_NODE_CODES[0]}" ]
	# Third node's parent is second
	[ "${_CFG_NODE_PARENTS[2]}" = "${_CFG_NODE_CODES[1]}" ]
}

# ── TC-M06: HEAD set to last migrated node ──────────────────────────────

@test "TC-M06: HEAD points to last migrated node" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"
	create_old_session "desktop-to-server-20260201T120000" ".tmux.conf"

	run run_migrate
	[ "$status" -eq 0 ]

	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	cfg_nodes_read_index

	local last_code="${_CFG_NODE_CODES[${#_CFG_NODE_CODES[@]}-1]}"
	assert_head_is "$last_code"
}

# ── TC-M07: Backup files are copied to node ─────────────────────────────

@test "TC-M07: migrated node contains backup files" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc" ".zshrc"

	run run_migrate
	[ "$status" -eq 0 ]

	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	cfg_nodes_read_index

	local desktop_code="${_CFG_NODE_CODES[1]}"
	[ -f "$HOME/.config-backup/nodes/$desktop_code/backup/.bashrc" ]
	[ -f "$HOME/.config-backup/nodes/$desktop_code/backup/.zshrc" ]
}

# ── TC-M08: Manifest is copied ──────────────────────────────────────────

@test "TC-M08: migrated node has manifest" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"

	run run_migrate
	[ "$status" -eq 0 ]

	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	cfg_nodes_read_index

	local desktop_code="${_CFG_NODE_CODES[1]}"
	[ -f "$HOME/.config-backup/nodes/$desktop_code/manifest.txt" ]
}

# ── TC-M09: Old sessions moved to sessions/ ─────────────────────────────

@test "TC-M09: old sessions archived after migration" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"
	create_old_session "desktop-to-server-20260201T120000" ".tmux.conf"

	run run_migrate
	[ "$status" -eq 0 ]

	assert_session_moved "fresh-to-desktop-20260101T120000"
	assert_session_moved "desktop-to-server-20260201T120000"
}

# ── TC-M10: Deploy status set after migration ───────────────────────────

@test "TC-M10: deploy status set to deployed after migration" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"

	run run_migrate
	[ "$status" -eq 0 ]

	[ -f "$HOME/.config-backup/DEPLOY_STATUS" ]
	local status
	status=$(<"$HOME/.config-backup/DEPLOY_STATUS")
	status="${status%%$'\n'*}"
	[ "$status" = "deployed" ]
}

# ── TC-M11: Dry-run mode doesn't create nodes ──────────────────────────

@test "TC-M11: migrate --dry-run shows plan without changes" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"

	run run_migrate --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"Dry Run"* ]]
	[[ "$output" == *"fresh-to-desktop-20260101T120000"* ]]

	[ ! -f "$HOME/.config-backup/nodes/index.json" ]
	[ -d "$HOME/.config-backup/fresh-to-desktop-20260101T120000" ]
}

# ── TC-M12: Non-session directories are ignored ─────────────────────────

@test "TC-M12: migrate ignores non-session directories" {
	mkdir -p "$HOME/.config-backup/random-dir"
	mkdir -p "$HOME/.config-backup/another-dir"
	create_old_session "fresh-to-server-20260101T120000" ".bashrc"

	run run_migrate
	[ "$status" -eq 0 ]

	[ -d "$HOME/.config-backup/random-dir" ]
	[ -d "$HOME/.config-backup/another-dir" ]

	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	cfg_nodes_read_index
	[ ${#_CFG_NODE_CODES[@]} -eq 2 ]
}

# ── TC-M13: Auto-migration triggered by dotcfg status ───────────────────

@test "TC-M13: auto-migration runs before status command" {
	setup_source_repo
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"

	run bash "$DOTCFG" status 2>&1
	[ "$status" -eq 0 ]
	[[ "$output" == *"migration"* ]] || [[ "$output" == *"Migrating"* ]] || [[ "$output" == *"Old backup"* ]]

	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	[ -f "$CFG_NODES_INDEX" ]
}

# ── TC-M14: Auto-migration not triggered for help ──────────────────────

@test "TC-M14: auto-migration skipped for help command" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"

	run bash "$DOTCFG" help 2>&1
	[ "$status" -eq 0 ]
	[[ "$output" != *"migration"* ]]

	[ ! -f "$HOME/.config-backup/nodes/index.json" ]
}

# ── TC-M15: Auto-migration not triggered for version ───────────────────

@test "TC-M15: auto-migration skipped for version command" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"

	run bash "$DOTCFG" version 2>&1
	[ "$status" -eq 0 ]
	[[ "$output" != *"migration"* ]]

	[ ! -f "$HOME/.config-backup/nodes/index.json" ]
}

# ── TC-M16: Children field populated correctly ──────────────────────────

@test "TC-M16: migrated nodes have correct children links" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"
	create_old_session "desktop-to-server-20260201T120000" ".tmux.conf"

	run run_migrate
	[ "$status" -eq 0 ]

	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	cfg_nodes_read_index

	# Root's children should include the desktop node
	[[ "${_CFG_NODE_CHILDREN[0]}" == *"${_CFG_NODE_CODES[1]}"* ]]
	# Desktop's children should include the server node
	[[ "${_CFG_NODE_CHILDREN[1]}" == *"${_CFG_NODE_CODES[2]}"* ]]
}

# ── TC-M17: Nodes directory structure created ───────────────────────────

@test "TC-M17: node directories have backup and files subdirs" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"

	run run_migrate
	[ "$status" -eq 0 ]

	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	cfg_nodes_read_index

	for code in "${_CFG_NODE_CODES[@]}"; do
		[ -d "$HOME/.config-backup/nodes/$code/backup" ]
		[ -d "$HOME/.config-backup/nodes/$code/files" ]
	done
}

# ── TC-M18: Explicit migrate command works ──────────────────────────────

@test "TC-M18: dotcfg migrate runs migration explicitly" {
	create_old_session "fresh-to-desktop-20260101T120000" ".bashrc"

	run bash "$DOTCFG" migrate 2>&1
	[ "$status" -eq 0 ]
	[[ "$output" == *"Migration Complete"* ]]
}
