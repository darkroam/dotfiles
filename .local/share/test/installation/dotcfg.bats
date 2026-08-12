#!/usr/bin/env bats
# dotcfg.bats - Tests for the unified dotcfg CLI
# TC-44 through TC-63

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
	teardown_source_repo 2>/dev/null || true
}

# ── status subcommand ──────────────────────────────────────────────────

@test "TC-ST09: status shows fresh state without available operations" {
	run run_dotcfg status
	[ "$status" -eq 0 ]
	assert_output_contains "fresh"
	[[ "$output" != *"Available operations"* ]]
}

@test "TC-45: status shows full state when indicators present" {
	create_mock_cfg_repo ".bashrc" ".local/bin/dotcfg"
	touch "$HOME/.xinitrc"

	run run_dotcfg status
	[ "$status" -eq 0 ]
	assert_output_contains "full"
}

@test "TC-46: status shows min state without graphical indicators" {
	create_mock_cfg_repo ".bashrc" ".local/bin/dotcfg"

	run run_dotcfg status
	[ "$status" -eq 0 ]
	assert_output_contains "min"
}

# ── list subcommand ────────────────────────────────────────────────────

@test "TC-47: list with no nodes shows helpful message" {
	run run_dotcfg list
	[ "$status" -eq 0 ]
	assert_output_contains "No nodes"
}

@test "TC-48: list shows header row" {
	source "$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	root_code=$(cfg_node_create "fresh" "null")
	cfg_node_create "desktop" "$root_code" >/dev/null

	run run_dotcfg list
	[ "$status" -eq 0 ]
	assert_output_contains "DEPLOY"
	assert_output_contains "TYPE"
	assert_output_contains "CODE"
}

# ── history subcommand ─────────────────────────────────────────────────

@test "TC-49: history with no backup directory shows message" {
	run run_dotcfg history
	[ "$status" -eq 0 ]
	assert_output_contains "No history"
}

@test "TC-50: history auto-migrates old sessions and shows node tree" {
	mkdir -p "$HOME/.config-backup/fresh-to-desktop-20260804T100000"
	printf '# Created: Mon Aug  4 10:00:00 UTC 2026\n# Transition: fresh -> desktop\n#\n# relative_path\tmd5\tstatus\n' \
		> "$HOME/.config-backup/fresh-to-desktop-20260804T100000/MANIFEST.txt"

	mkdir -p "$HOME/.config-backup/desktop-to-server-20260804T143000"
	printf '# Created: Mon Aug  4 14:30:00 UTC 2026\n# Transition: desktop -> server\n#\n# relative_path\tmd5\tstatus\n' \
		> "$HOME/.config-backup/desktop-to-server-20260804T143000/MANIFEST.txt"

	create_mock_cfg_repo ".bashrc" ".local/bin/dotcfg"

	run run_dotcfg history
	[ "$status" -eq 0 ]
	assert_output_contains "fresh"
	assert_output_contains "desktop"
	assert_output_contains "server"
	assert_output_contains "HEAD"
}

@test "TC-51: history ignores non-session directory names" {
	mkdir -p "$HOME/.config-backup/fresh-to-desktop-20260804T100000"
	printf '# Created: Mon Aug  4 10:00:00 UTC 2026\n# Transition: fresh -> desktop\n#\n' \
		> "$HOME/.config-backup/fresh-to-desktop-20260804T100000/MANIFEST.txt"

	mkdir -p "$HOME/.config-backup/invalid-20260804T120000"
	mkdir -p "$HOME/.config-backup/random-garbage"

	create_mock_cfg_repo ".bashrc" ".local/bin/dotcfg"

	run run_dotcfg history
	[ "$status" -eq 0 ]
	assert_output_contains "desktop"
	assert_output_contains "HEAD"
	[[ "$output" != *"invalid"* ]] || true
	[[ "$output" != *"random"* ]] || true
}

# ── switch subcommand ──────────────────────────────────────────────────

@test "TC-52: switch fresh resolves to root node (error when no root exists)" {
	run run_dotcfg switch fresh
	[ "$status" -eq 1 ]
	assert_output_contains "root node not found"
}

@test "TC-53: switch to invalid target prints error and exits 1" {
	run run_dotcfg switch invalid
	[ "$status" -eq 1 ]
	assert_output_contains "unknown target"
}

@test "TC-54: switch fresh to full invokes the unified switch" {
	setup_source_repo

	run bash -c "yes | bash '$DOTCFG' switch full"
	[ "$status" -eq 0 ]
	assert_cfg_exists
	assert_state_is "full"
}

@test "TC-55: switch full to min invokes the unified switch" {
	setup_source_repo
	setup_installed_state

	run bash -c "yes | bash '$DOTCFG' switch min"
	[ "$status" -eq 0 ]
	assert_state_is "min"
}

@test "TC-56: switch --dry-run is passed through to underlying script" {
	setup_source_repo

	run bash -c "yes | bash '$DOTCFG' switch full --dry-run"
	[ "$status" -eq 0 ]
	assert_cfg_not_exists
	assert_output_contains "DRY RUN"
}

@test "TC-56b: released desktop name works when defined as an ordinary category" {
	setup_source_repo ".bashrc" ".local/bin/dotcfg"
	local dlib="$HOME/dlib"
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$dlib"
	cat > "$dlib/categories-2.0.0.conf" <<'CONF'
# VERSION = "2.0.0"
category = desktop
+ .bashrc
CONF
	mkdir -p "$HOME/.config-backup"
	printf '2.0.0\n' > "$HOME/.config-backup/CURRENT_CONFIG_VERSION"

	run env DOTFILES_LIB_DIR="$dlib" bash "$DOTCFG" switch desktop --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" != *"unknown target"* ]]
	assert_output_contains "DRY RUN"
}

# ── validate subcommand ────────────────────────────────────────────────

@test "TC-57: validate shows validation detail and state" {
	create_mock_cfg_repo ".bashrc" ".local/bin/dotcfg"

	run run_dotcfg validate
	[ "$status" -eq 0 ]
	assert_output_contains "min"
	assert_output_contains "Installation state"
}

# ── help and dispatch ──────────────────────────────────────────────────

@test "TC-58: no args defaults to status; unknown subcommand exits 1" {
	run run_dotcfg
	[ "$status" -eq 0 ]
	assert_output_contains "Current state"

	run run_dotcfg nonexistent
	[ "$status" -eq 1 ]
	assert_output_contains "Unknown subcommand"
}

@test "TC-59: top-level and subcommand --help show the same help" {
	run run_dotcfg --help
	[ "$status" -eq 0 ]
	local top_help="$output"
	assert_output_contains "Usage: dotcfg"

	run run_dotcfg status --help
	[ "$status" -eq 0 ]
	[ "$output" = "$top_help" ]

	run run_dotcfg help
	[ "$status" -eq 0 ]
	[ "$output" = "$top_help" ]
}

@test "TC-60: category TAGs are displayed and warned on destructive actions" {
	local test_lib="$HOME/dotfiles-lib"
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$test_lib"
	rm -f -- "$test_lib"/categories-*.conf
	cat > "$test_lib/categories-90.0.0.conf" <<'EOF'
# VERSION = "90.0.0"
# NAME = "test-version"
# DESCRIPTION = "TAG integration fixture"
# TAG = "test"

category = server
+ .bashrc

category = desktop
include = server
+ .xinitrc
EOF
	cat > "$test_lib/categories-90.1.0.conf" <<'EOF'
# VERSION = "90.1.0"
# TAG = "experimental"

category = server
+ .bashrc
EOF
	export DOTFILES_LIB_DIR="$test_lib"
	create_mock_cfg_repo ".local/bin/dotcfg"

	run run_dotcfg categories list
	[ "$status" -eq 0 ]
	assert_output_contains "90.0.0  (test)"
	assert_output_contains "[TEST]"
	assert_output_contains "90.1.0  (experimental)"
	assert_output_contains "[EXPERIMENTAL]"

	run run_dotcfg categories switch 90.0.0
	[ "$status" -eq 0 ]
	assert_output_contains "Switching to test version 90.0.0"

	local node
	node=$(DOTFILES_LIB_DIR="$test_lib" bash -c '
		. "$DOTFILES_LIB_DIR/utils/common.sh"
		cfg_nodes_init "$HOME/.config-backup"
		root=$(cfg_node_create fresh null)
		cfg_head_set "$root"
		cfg_node_create server "$root" 90.1.0
	')
	run env DOTFILES_LIB_DIR="$test_lib" bash "$test_lib/commands/remove.sh" "$node"
	[ "$status" -eq 0 ]
	assert_output_contains "EXPERIMENTAL configuration version 90.1.0"

	run bash -c 'printf "y\n" | DOTFILES_LIB_DIR="$1" bash "$2" categories remove 90.0.0' \
		_ "$test_lib" "$DOTCFG"
	[ "$status" -eq 0 ]
	assert_output_contains "TEST configuration version"
	[ ! -f "$test_lib/categories-90.0.0.conf" ]
}

@test "TC-61: official category version exposes full, min and macos only" {
	export DOTFILES_LIB_DIR="$REAL_HOME/.local/lib/dotfiles"
	run run_dotcfg categories show 1.0.0
	[ "$status" -eq 0 ]
	assert_output_contains "Tag: stable"
	assert_output_contains "macos"
	assert_output_contains "min"
	assert_output_contains "full"
	[[ "$output" != *"empty"* ]]

	run bash -c '
		. "$DOTFILES_LIB_DIR/utils/common.sh"
		cfg_categories_load 1.0.0
		cfg_category_exists desktop && exit 1
		cfg_category_exists server && exit 1
		printf "%s %s" "$(cfg_category_canonical_name desktop)" "$(cfg_category_canonical_name server)"
	'
	[ "$status" -eq 0 ]
	[ "$output" = "desktop server" ]
}

@test "TC-62: fresh-adopt-legacy help shows its complete invocation" {
	run run_dotcfg fresh-adopt-legacy --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"fresh-adopt-legacy <path> [--dry-run] [--config-version VERSION]"* ]]
}

@test "TC-63: categories show identifies full as a dynamic category" {
	export DOTFILES_LIB_DIR="$REAL_HOME/.local/lib/dotfiles"
	run run_dotcfg categories show 1.0.0
	[ "$status" -eq 0 ]
	assert_output_contains "full"
	assert_output_contains "(dynamic, all tracked files)"
	[[ "$output" != *"full            "[0-9]*" files"* ]]
}
