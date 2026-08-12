#!/usr/bin/env bats
# switch-full.bats - Integration tests for dotcfg switch full
# Includes compatibility coverage for the old switch-desktop wrapper.
# TC-11 through TC-16 and TC-SF01 through TC-SF07

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
	teardown_source_repo
}

# TC-11: Fresh install — no .cfg, no existing user files

@test "TC-11: fresh install creates .cfg and checks out all files" {
	setup_source_repo
	run run_switch_full
	[ "$status" -eq 0 ]

	assert_cfg_exists
	assert_checkout_state_exists
	assert_file_exists ".bashrc"
	assert_file_exists ".zshrc"
	assert_file_exists ".profile"
	assert_file_exists ".xinitrc"
	assert_file_exists ".gitconfig"
	assert_file_exists ".tmux.conf"
	assert_file_exists ".config/shell/profile"
	assert_file_exists ".config/x11/xinitrc"
	assert_file_exists ".config/tmux/tmux.conf"

	# No backup should be created (no pre-existing user files)
	assert_backup_count 0

	# State should be desktop after install (xinitrc is a desktop indicator)
	assert_state_is "full"
}

# TC-12: Fresh install with pre-existing user files → backup created

@test "TC-12: fresh install backs up existing user files" {
	setup_source_repo

	# Create user files that differ from repo content
	echo "user's custom bashrc" > "$HOME/.bashrc"
	echo "user's custom gitconfig" > "$HOME/.gitconfig"
	mkdir -p "$HOME/.config/custom-untracked"
	echo "untracked config" > "$HOME/.config/custom-untracked/settings.conf"

	run run_switch_full
	[ "$status" -eq 0 ]

	# Backup directory should exist with proper naming
	assert_node_backup_exists
	assert_node_manifest_exists

	# Backup should contain the user's original files
	assert_node_backup_contains ".bashrc"
	assert_node_backup_contains ".gitconfig"

	# MANIFEST should record modified/untracked status
	local manifest
	manifest=$(find "$HOME/.config-backup/nodes" -name "manifest.txt" -type f 2>/dev/null | sort | tail -1)
	grep -q '.bashrc' "$manifest"
	grep -q '.gitconfig' "$manifest"

	# Current files should now be repo versions, not user versions
	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "repo content for .bashrc"
	assert_file_contains ".gitconfig" "repo content for .gitconfig"

	assert_cfg_exists
	assert_checkout_state_exists
}

# TC-13: Dry run makes no changes

@test "TC-13: --dry-run reports plan without modifying anything" {
	setup_source_repo
	echo "user bashrc" > "$HOME/.bashrc"

	run run_switch_full --dry-run
	[ "$status" -eq 0 ]

	# Nothing should have changed
	assert_cfg_not_exists
	assert_checkout_state_not_exists
	assert_backup_count 0

	# User file should be untouched
	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "user bashrc"

	# Output should mention dry run
	[[ "$output" == *"DRY RUN"* ]]
}

# TC-14: --force with existing valid .cfg backs up old repo and clones fresh

@test "TC-14: --force replaces existing valid repository" {
	setup_source_repo
	create_valid_existing_cfg ".bashrc" ".gitconfig" ".local/bin/dotcfg"

	run run_switch_full --force
	[ "$status" -eq 0 ]

	# Old .cfg should have been backed up
	local backup_dirs
	backup_dirs=$(find "$HOME/.config-backup" -mindepth 1 -maxdepth 1 -name 'valid-*' -type d 2>/dev/null)
	[ -n "$backup_dirs" ]

	# New .cfg should exist and be valid
	assert_cfg_exists
	assert_checkout_state_exists

	# All desktop files should now be installed
	assert_file_exists ".bashrc"
	assert_file_exists ".xinitrc"
	assert_file_contains ".bashrc" "repo content for .bashrc"
}

# TC-15: .cfg-checkout-state created with path:hash entries

@test "TC-15: checkout state file records all tracked files" {
	setup_source_repo

	run run_switch_full
	[ "$status" -eq 0 ]

	assert_checkout_state_exists

	# State file should contain path:hash entries
	local state_file="$HOME/.cfg-checkout-state"
	[ -s "$state_file" ]

	# Each line should match format path:md5hash
	local line_count
	line_count=$(wc -l < "$state_file")
	(( line_count > 0 ))

	# Verify a known file is recorded
	grep -q '^\.bashrc:' "$state_file"
	grep -q '^\.gitconfig:' "$state_file"
}

# TC-16: status.showUntrackedFiles set to no

@test "TC-16: showUntrackedFiles configured to no" {
	setup_source_repo

	run run_switch_full
	[ "$status" -eq 0 ]

	assert_cfg_exists
	assert_show_untracked_no
}

# ── Existing-state and compatibility coverage (formerly restore-desktop) ──

@test "TC-SF01: switch full adds desktop files from a min state" {
	setup_source_repo
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- \
		. ':!.xinitrc' ':!.xprofile' ':!.asoundrc' \
		':!.config/x11' ':!.config/alsa' ':!.gtkrc-2.0' >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" config status.showUntrackedFiles no
	[ ! -e "$HOME/.xinitrc" ]

	run run_switch_full
	[ "$status" -eq 0 ]
	assert_file_exists ".xinitrc"
	assert_file_exists ".xprofile"
	assert_file_exists ".asoundrc"
	assert_file_exists ".config/x11/xinitrc"
	assert_file_exists ".config/x11/picom.conf"
	assert_file_exists ".bashrc"
	assert_file_exists ".gitconfig"
	assert_state_is "full"
}

@test "TC-SF02: switch full backs up modified files" {
	setup_source_repo
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- \
		. ':!.xinitrc' ':!.xprofile' ':!.asoundrc' \
		':!.config/x11' ':!.config/alsa' ':!.gtkrc-2.0' >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" config status.showUntrackedFiles no
	echo "user modified bashrc" > "$HOME/.bashrc"
	echo "user modified gitconfig" > "$HOME/.gitconfig"

	run run_switch_full
	[ "$status" -eq 0 ]
	assert_node_backup_exists
	assert_file_contains ".bashrc" "repo content for .bashrc"
	assert_file_contains ".gitconfig" "repo content for .gitconfig"
}

@test "TC-SF03: switch full --dry-run preserves a min state" {
	setup_source_repo
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- \
		. ':!.xinitrc' ':!.xprofile' ':!.asoundrc' \
		':!.config/x11' ':!.config/alsa' ':!.gtkrc-2.0' >/dev/null 2>&1
	echo "user bashrc" > "$HOME/.bashrc"

	run run_switch_full --dry-run
	[ "$status" -eq 0 ]
	assert_file_not_exists ".xinitrc"
	assert_file_contains ".bashrc" "user bashrc"
	assert_backup_count 0
	[[ "$output" == *"DRY RUN"* ]]
}

@test "TC-SF04: switch full --auto-stash backs up without prompting" {
	setup_source_repo
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- \
		. ':!.xinitrc' ':!.xprofile' ':!.asoundrc' \
		':!.config/x11' ':!.config/alsa' ':!.gtkrc-2.0' >/dev/null 2>&1
	echo "user modified" > "$HOME/.bashrc"
	echo "user modified" > "$HOME/.gitconfig"

	run run_switch_full --auto-stash
	[ "$status" -eq 0 ]
	assert_node_backup_count 1
	assert_file_contains ".bashrc" "repo content for .bashrc"
	assert_file_contains ".gitconfig" "repo content for .gitconfig"
	[[ "$output" == *"auto-stash"* ]]
}

@test "TC-SF05: switch full works from a fresh state" {
	setup_source_repo
	run run_switch_full
	[ "$status" -eq 0 ]
	assert_cfg_exists
	assert_file_exists ".bashrc"
	assert_file_exists ".xinitrc"
	assert_state_is "full"
}

@test "TC-SF06: switch full --reinstall is accepted in full state" {
	setup_source_repo
	setup_installed_state
	run run_switch_full --reinstall
	[ "$status" -eq 0 ]
	assert_file_exists ".bashrc"
	assert_file_exists ".xinitrc"
	assert_state_is "full"
}

@test "TC-SF07: legacy switch-desktop wrapper still targets full" {
	setup_source_repo
	run run_legacy_switch_full --dry-run
	[ "$status" -eq 0 ]
	assert_cfg_not_exists
	[[ "$output" == *"Target state: full"* ]]
	[[ "$output" == *"DRY RUN"* ]]
}
