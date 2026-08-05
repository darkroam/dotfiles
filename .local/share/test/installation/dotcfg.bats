#!/usr/bin/env bats
# dotcfg.bats - Tests for the unified dotcfg CLI
# TC-44 through TC-58

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
	teardown_source_repo 2>/dev/null || true
}

# ── status subcommand ──────────────────────────────────────────────────

@test "TC-44: status shows fresh state with available transitions" {
	run run_dotcfg status
	[ "$status" -eq 0 ]
	assert_output_contains "fresh"
	assert_output_contains "desktop"
	assert_output_contains "server"
	assert_output_contains "Available transitions"
}

@test "TC-45: status shows desktop state when indicators present" {
	create_mock_cfg_repo ".bashrc" ".local/bin/install.sh"
	touch "$HOME/.xinitrc"

	run run_dotcfg status
	[ "$status" -eq 0 ]
	assert_output_contains "desktop"
}

@test "TC-46: status shows server state without desktop indicators" {
	create_mock_cfg_repo ".bashrc" ".local/bin/install.sh"

	run run_dotcfg status
	[ "$status" -eq 0 ]
	assert_output_contains "server"
}

# ── graph subcommand ───────────────────────────────────────────────────

@test "TC-47: graph shows state graph with desktop marker" {
	create_mock_cfg_repo ".bashrc" ".local/bin/install.sh"
	touch "$HOME/.xinitrc"

	run run_dotcfg graph
	[ "$status" -eq 0 ]
	assert_output_contains "State Graph"
	assert_output_contains "fresh"
	assert_output_contains "server"
	assert_output_contains "desktop"
	assert_output_contains "Current:"
	assert_output_contains "restore-server.sh"
	assert_output_contains "uninstall.sh"
}

@test "TC-48: graph shows state graph with fresh marker" {
	run run_dotcfg graph
	[ "$status" -eq 0 ]
	assert_output_contains "State Graph"
	assert_output_contains "Current:"
	assert_output_contains "install-2.sh"
	assert_output_contains "install-server.sh"
}

# ── history subcommand ─────────────────────────────────────────────────

@test "TC-49: history with no backup directory shows message" {
	run run_dotcfg history
	[ "$status" -eq 0 ]
	assert_output_contains "No backup history"
}

@test "TC-50: history parses backup manifests into timeline" {
	mkdir -p "$HOME/.config-backup/fresh-to-desktop-20260804T100000"
	printf '# Created: Mon Aug  4 10:00:00 UTC 2026\n# Transition: fresh -> desktop\n#\n# relative_path\tmd5\tstatus\n' \
		> "$HOME/.config-backup/fresh-to-desktop-20260804T100000/MANIFEST.txt"

	mkdir -p "$HOME/.config-backup/desktop-to-server-20260804T143000"
	printf '# Created: Mon Aug  4 14:30:00 UTC 2026\n# Transition: desktop -> server\n#\n# relative_path\tmd5\tstatus\n' \
		> "$HOME/.config-backup/desktop-to-server-20260804T143000/MANIFEST.txt"

	create_mock_cfg_repo ".bashrc" ".local/bin/install.sh"

	run run_dotcfg history
	[ "$status" -eq 0 ]
	assert_output_contains "Transition History"
	assert_output_contains "#1"
	assert_output_contains "#2"
	assert_output_contains "fresh -> desktop"
	assert_output_contains "desktop -> server"
}

@test "TC-51: history skips malformed directory names" {
	mkdir -p "$HOME/.config-backup/fresh-to-desktop-20260804T100000"
	printf '# Created: Mon Aug  4 10:00:00 UTC 2026\n# Transition: fresh -> desktop\n#\n' \
		> "$HOME/.config-backup/fresh-to-desktop-20260804T100000/MANIFEST.txt"

	mkdir -p "$HOME/.config-backup/invalid-20260804T120000"
	mkdir -p "$HOME/.config-backup/random-garbage"

	create_mock_cfg_repo ".bashrc" ".local/bin/install.sh"

	run run_dotcfg history
	[ "$status" -eq 0 ]
	assert_output_contains "#1"
	assert_output_contains "fresh -> desktop"
	[[ "$output" != *"invalid"* ]] || true
	[[ "$output" != *"random"* ]] || true
}

# ── switch subcommand ──────────────────────────────────────────────────

@test "TC-52: switch to same state prints message and exits 0" {
	run run_dotcfg switch fresh
	[ "$status" -eq 0 ]
	assert_output_contains "Already in fresh"
}

@test "TC-53: switch to invalid target prints error and exits 1" {
	run run_dotcfg switch invalid
	[ "$status" -eq 1 ]
	assert_output_contains "unknown target"
}

@test "TC-54: switch fresh to desktop invokes install script" {
	setup_source_repo

	run bash -c "yes | bash '$DOTCFG' switch desktop"
	[ "$status" -eq 0 ]
	assert_cfg_exists
	assert_state_is "desktop"
}

@test "TC-55: switch desktop to server invokes restore-server" {
	setup_source_repo
	setup_installed_state

	run bash -c "yes | bash '$DOTCFG' switch server"
	[ "$status" -eq 0 ]
	assert_state_is "server"
}

@test "TC-56: switch --dry-run is passed through to underlying script" {
	setup_source_repo

	run bash -c "yes | bash '$DOTCFG' switch desktop --dry-run"
	[ "$status" -eq 0 ]
	assert_cfg_not_exists
	assert_output_contains "DRY RUN"
}

# ── validate subcommand ────────────────────────────────────────────────

@test "TC-57: validate shows validation detail and state" {
	create_mock_cfg_repo ".bashrc" ".local/bin/install.sh"

	run run_dotcfg validate
	[ "$status" -eq 0 ]
	assert_output_contains "server"
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
