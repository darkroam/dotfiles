#!/usr/bin/env bats
# switch-macos.bats - Integration tests for dotcfg switch macos
# TC-MC01 through TC-MC04

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
	teardown_source_repo
}

@test "TC-MC01: fresh macos switch installs only cross-platform core files" {
	setup_source_repo
	run run_switch_macos
	[ "$status" -eq 0 ]

	assert_cfg_exists
	assert_checkout_state_exists
	assert_file_exists ".bashrc"
	assert_file_exists ".zshrc"
	assert_file_exists ".profile"
	assert_file_exists ".zprofile"
	assert_file_exists ".gitconfig"
	assert_file_exists ".config/shell/profile"
	assert_file_exists ".config/tmux/tmux.conf"
	assert_file_not_exists ".config/lf/lfrc"
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".config/x11/xinitrc"
	run run_dotcfg status
	[ "$status" -eq 0 ]
	[[ "$output" == *"(macos)"* ]]
}

@test "TC-MC02: macos switch backs up conflicting core files" {
	setup_source_repo
	echo "user bashrc" > "$HOME/.bashrc"
	echo "user gitconfig" > "$HOME/.gitconfig"

	run run_switch_macos
	[ "$status" -eq 0 ]
	assert_node_backup_exists
	assert_node_backup_contains ".bashrc"
	assert_node_backup_contains ".gitconfig"
	assert_file_contains ".bashrc" "repo content for .bashrc"
	assert_file_contains ".gitconfig" "repo content for .gitconfig"
}

@test "TC-MC03: macos --dry-run makes no changes" {
	setup_source_repo
	echo "user bashrc" > "$HOME/.bashrc"

	run run_switch_macos --dry-run
	[ "$status" -eq 0 ]
	assert_cfg_not_exists
	assert_checkout_state_not_exists
	assert_backup_count 0
	assert_file_contains ".bashrc" "user bashrc"
	[[ "$output" == *"Target state: macos"* ]]
	[[ "$output" == *"DRY RUN"* ]]
}

@test "TC-MC04: switching from full to macos removes non-core files" {
	setup_source_repo
	setup_installed_state

	run run_switch_macos
	[ "$status" -eq 0 ]
	assert_file_exists ".bashrc"
	assert_file_exists ".config/tmux/tmux.conf"
	assert_file_not_exists ".config/lf/lfrc"
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".config/x11/xinitrc"
	run run_dotcfg status
	[ "$status" -eq 0 ]
	[[ "$output" == *"(macos)"* ]]
}
