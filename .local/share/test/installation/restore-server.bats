#!/usr/bin/env bats
# restore-server.bats - Integration tests for restore-server.sh
# TC-26 through TC-29

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
	teardown_source_repo
}

# TC-26: Desktop → Server — desktop symlinks removed, server files checked out

@test "TC-26: restore-server removes desktop indicators and verifies server files" {
	setup_source_repo
	setup_installed_state

	# Verify we're in desktop state
	[ -e "$HOME/.xinitrc" ]

	run run_restore_server
	[ "$status" -eq 0 ]

	# Desktop symlinks should be removed
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".xprofile"
	assert_file_not_exists ".asoundrc"
	assert_file_not_exists ".gtkrc-2.0"

	# Server files should still exist
	assert_file_exists ".bashrc"
	assert_file_exists ".gitconfig"
	assert_file_exists ".config/shell/profile"
	assert_file_exists ".config/tmux/tmux.conf"

	# State should be server
	assert_state_is "server"
}

# TC-27: Restore-server with modified files → backup created

@test "TC-27: restore-server backs up modified desktop files" {
	setup_source_repo
	setup_installed_state

	# Modify a file that's in the desktop_symlinks list but is a regular file (not symlink)
	# .gitconfig is checked out as regular file, and is in the desktop_symlinks list
	echo "user modified gitconfig" > "$HOME/.gitconfig"

	run run_restore_server
	[ "$status" -eq 0 ]

	# The modified file should be backed up before removal
	assert_backup_dir_exists
	assert_manifest_exists

	# Desktop indicators should be gone
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".xprofile"

	# Server files should be present
	assert_file_exists ".bashrc"
	assert_file_exists ".config/tmux/tmux.conf"
}

# TC-28: --dry-run makes no changes

@test "TC-28: restore-server --dry-run reports plan without modifying" {
	setup_source_repo
	setup_installed_state

	# Verify desktop state
	[ -e "$HOME/.xinitrc" ]

	run run_restore_server --dry-run
	[ "$status" -eq 0 ]

	# Desktop files should still exist
	assert_file_exists ".xinitrc"
	assert_file_exists ".xprofile"

	# No backup created
	assert_backup_count 0

	# State should still be desktop
	assert_state_is "desktop"

	[[ "$output" == *"DRY RUN"* ]]
}

# TC-29: After restore-server, state is server and checkout state updated

@test "TC-29: restore-server updates checkout state and git config" {
	setup_source_repo
	setup_installed_state

	run run_restore_server
	[ "$status" -eq 0 ]

	assert_checkout_state_exists
	assert_show_untracked_no

	# State should be server
	assert_state_is "server"

	# Desktop-only files should not exist
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".asoundrc"
}

# TC-30: restore-server.sh fails when not in desktop state

@test "TC-30: restore-server fails in fresh state" {
	setup_source_repo
	# Don't setup any .cfg - fresh state

	run run_restore_server
	[ "$status" -eq 1 ]
	# In fresh state, fails at validation before state check
	[[ "$output" == *"not found"* ]] || [[ "$output" == *"Run install"* ]]
}

@test "TC-30b: restore-server fails in server state" {
	setup_source_repo

	# Setup server state (has .cfg but no desktop indicators)
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- \
		. ':!.xinitrc' ':!.xprofile' ':!.asoundrc' \
		':!.config/x11' ':!.config/alsa' ':!.gtkrc-2.0' >/dev/null 2>&1

	run run_restore_server
	[ "$status" -eq 1 ]
	[[ "$output" == *"requires desktop state"* ]]
	[[ "$output" == *"current state is server"* ]]
}
