#!/usr/bin/env bats
# switch-min.bats - Integration tests for dotcfg switch min
# Includes compatibility coverage for the old switch-server wrapper.
# TC-17 through TC-21 and TC-SM01 through TC-SM07

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
	teardown_source_repo
}

# TC-17: Fresh server install — only whitelisted files installed

@test "TC-17: fresh min install checks out only command-line files" {
	setup_source_repo

	run run_switch_min
	[ "$status" -eq 0 ]

	assert_cfg_exists
	assert_checkout_state_exists

	# Server-whitelisted files should be installed
	assert_file_exists ".bashrc"
	assert_file_exists ".zshrc"
	assert_file_exists ".profile"
	assert_file_exists ".gitconfig"
	assert_file_exists ".config/shell/profile"
	assert_file_exists ".config/tmux/tmux.conf"
	assert_file_exists ".config/lf/lfrc"

	# Desktop-only files should NOT be installed
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".xprofile"
	assert_file_not_exists ".asoundrc"
	assert_file_not_exists ".config/x11/xinitrc"
	assert_file_not_exists ".config/x11/picom.conf"

	# State should be server (no desktop indicators)
	assert_state_is "min"
}

# TC-18: Server install with existing user files → backup created

@test "TC-18: min install backs up existing user files" {
	setup_source_repo

	echo "user's bashrc" > "$HOME/.bashrc"
	echo "user's gitconfig" > "$HOME/.gitconfig"

	run run_switch_min
	[ "$status" -eq 0 ]

	assert_node_backup_exists
	assert_node_manifest_exists

	# Backup should contain user's files
	assert_node_backup_contains ".bashrc"
	assert_node_backup_contains ".gitconfig"

	# MANIFEST should record backed-up files
	local manifest
	manifest=$(find "$HOME/.config-backup/nodes" -name "manifest.txt" -type f 2>/dev/null | sort | tail -1)
	grep -q '.bashrc' "$manifest"

	# Current files should be repo versions
	assert_file_contains ".bashrc" "repo content for .bashrc"
	assert_file_contains ".gitconfig" "repo content for .gitconfig"

	assert_cfg_exists
}

# TC-19: Server dry run makes no changes

@test "TC-19: min --dry-run reports plan without modifying anything" {
	setup_source_repo
	echo "user bashrc" > "$HOME/.bashrc"

	run run_switch_min --dry-run
	[ "$status" -eq 0 ]

	assert_cfg_not_exists
	assert_checkout_state_not_exists
	assert_backup_count 0

	# User file untouched
	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "user bashrc"

	[[ "$output" == *"DRY RUN"* ]]
}

# TC-20: Server install excludes desktop-only files

@test "TC-20: min category excludes desktop-only files" {
	setup_source_repo

	run run_switch_min
	[ "$status" -eq 0 ]

	# These are in the source repo but NOT in the server whitelist
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".xprofile"
	assert_file_not_exists ".asoundrc"
	assert_file_not_exists ".gtkrc-2.0"
	assert_file_not_exists ".config/x11/xinitrc"
	assert_file_not_exists ".config/x11/xprofile"
	assert_file_not_exists ".config/x11/picom.conf"
	assert_file_not_exists ".config/alsa/asoundrc"

	# Server files should be present
	assert_file_exists ".bashrc"
	assert_file_exists ".gitconfig"
	assert_file_exists ".config/tmux/tmux.conf"
}

# TC-21: Server checkout state and showUntrackedFiles

@test "TC-21: min install creates checkout state and configures git" {
	setup_source_repo

	run run_switch_min
	[ "$status" -eq 0 ]

	assert_checkout_state_exists
	assert_show_untracked_no

	# State file should only contain server-whitelisted files
	local state_file="$HOME/.cfg-checkout-state"
	grep -q '^\.bashrc:' "$state_file"
	grep -q '^\.gitconfig:' "$state_file"

	# Desktop-only files should NOT be in the state file
	! grep -q '^\.xinitrc:' "$state_file"
	! grep -q '^\.asoundrc:' "$state_file"
}

# ── Existing-state and compatibility coverage (formerly restore-server) ──

@test "TC-SM01: switch min removes full-only files" {
	setup_source_repo
	setup_installed_state
	[ -e "$HOME/.xinitrc" ]

	run run_switch_min
	[ "$status" -eq 0 ]
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".xprofile"
	assert_file_not_exists ".asoundrc"
	assert_file_not_exists ".gtkrc-2.0"
	assert_file_exists ".bashrc"
	assert_file_exists ".gitconfig"
	assert_file_exists ".config/shell/profile"
	assert_file_exists ".config/tmux/tmux.conf"
	assert_state_is "min"
}

@test "TC-SM02: switch min backs up modified files before removal" {
	setup_source_repo
	setup_installed_state
	echo "user modified gitconfig" > "$HOME/.gitconfig"

	run run_switch_min
	[ "$status" -eq 0 ]
	assert_node_backup_exists
	assert_node_manifest_exists
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".xprofile"
	assert_file_exists ".bashrc"
	assert_file_exists ".config/tmux/tmux.conf"
}

@test "TC-SM03: switch min --dry-run preserves full state" {
	setup_source_repo
	setup_installed_state

	run run_switch_min --dry-run
	[ "$status" -eq 0 ]
	assert_file_exists ".xinitrc"
	assert_file_exists ".xprofile"
	assert_backup_count 0
	assert_state_is "full"
	[[ "$output" == *"DRY RUN"* ]]
}

@test "TC-SM04: switch min updates checkout state and git config" {
	setup_source_repo
	setup_installed_state

	run run_switch_min
	[ "$status" -eq 0 ]
	assert_checkout_state_exists
	assert_show_untracked_no
	assert_state_is "min"
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".asoundrc"
}

@test "TC-SM05: switch min works from a fresh state" {
	setup_source_repo
	run run_switch_min
	[ "$status" -eq 0 ]
	assert_cfg_exists
	assert_file_exists ".bashrc"
	assert_file_exists ".gitconfig"
	assert_file_not_exists ".xinitrc"
	assert_state_is "min"
}

@test "TC-SM06: switch min --reinstall is accepted in min state" {
	setup_source_repo
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- \
		. ':!.xinitrc' ':!.xprofile' ':!.asoundrc' \
		':!.config/x11' ':!.config/alsa' ':!.gtkrc-2.0' >/dev/null 2>&1

	run run_switch_min --reinstall
	[ "$status" -eq 0 ]
	assert_file_exists ".bashrc"
	assert_state_is "min"
}

@test "TC-SM07: legacy switch-server wrapper still targets min" {
	setup_source_repo
	run run_legacy_switch_min --dry-run
	[ "$status" -eq 0 ]
	assert_cfg_not_exists
	[[ "$output" == *"Target state: min"* ]]
	[[ "$output" == *"DRY RUN"* ]]
}
