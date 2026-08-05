#!/usr/bin/env bats
# restore-desktop.bats - Integration tests for restore-desktop.sh
# TC-22 through TC-25

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
	teardown_source_repo
}

# TC-22: Server → Desktop — desktop-only files are checked out

@test "TC-22: restore-desktop adds desktop files from server state" {
	setup_source_repo

	# Simulate server-mode install: .cfg exists but no desktop indicators
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- \
		. ':!.xinitrc' ':!.xprofile' ':!.asoundrc' \
		':!.config/x11' ':!.config/alsa' ':!.gtkrc-2.0' >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" config status.showUntrackedFiles no

	# Verify we're in server state (no desktop indicators)
	[ ! -e "$HOME/.xinitrc" ]
	[ ! -e "$HOME/.xprofile" ]

	run run_restore_desktop
	[ "$status" -eq 0 ]

	# Desktop-only files should now exist
	assert_file_exists ".xinitrc"
	assert_file_exists ".xprofile"
	assert_file_exists ".asoundrc"
	assert_file_exists ".config/x11/xinitrc"
	assert_file_exists ".config/x11/picom.conf"

	# Server files should still exist
	assert_file_exists ".bashrc"
	assert_file_exists ".gitconfig"

	# State should be desktop
	assert_state_is "desktop"
}

# TC-23: Restore with modified files → backup created

@test "TC-23: restore-desktop backs up modified files" {
	setup_source_repo

	# Simulate server-mode install: .cfg exists but no desktop indicators
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- \
		. ':!.xinitrc' ':!.xprofile' ':!.asoundrc' \
		':!.config/x11' ':!.config/alsa' ':!.gtkrc-2.0' >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" config status.showUntrackedFiles no

	# Modify some files to create conflicts
	echo "user modified bashrc" > "$HOME/.bashrc"
	echo "user modified gitconfig" > "$HOME/.gitconfig"

	run run_restore_desktop
	[ "$status" -eq 0 ]

	# Backup should be created
	assert_backup_dir_exists
	assert_manifest_exists

	# Backup should contain user's modified files
	assert_backup_contains ".bashrc"
	assert_backup_contains ".gitconfig"

	# Current files should be repo versions
	assert_file_contains ".bashrc" "repo content for .bashrc"
	assert_file_contains ".gitconfig" "repo content for .gitconfig"
}

# TC-24: --dry-run makes no changes

@test "TC-24: restore-desktop --dry-run reports plan without modifying" {
	setup_source_repo

	# Create server state
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- \
		. ':!.xinitrc' ':!.xprofile' ':!.asoundrc' \
		':!.config/x11' ':!.config/alsa' ':!.gtkrc-2.0' >/dev/null 2>&1

	echo "user bashrc" > "$HOME/.bashrc"

	run run_restore_desktop --dry-run
	[ "$status" -eq 0 ]

	# Desktop files should NOT be added
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".xprofile"

	# User file should be untouched
	assert_file_contains ".bashrc" "user bashrc"

	# No backup created
	assert_backup_count 0

	[[ "$output" == *"DRY RUN"* ]]
}

# TC-25: --auto-stash removes conflicting files without backup

@test "TC-25: restore-desktop --auto-stash overwrites without backup" {
	setup_source_repo

	# Simulate server-mode install: .cfg exists but no desktop indicators
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- \
		. ':!.xinitrc' ':!.xprofile' ':!.asoundrc' \
		':!.config/x11' ':!.config/alsa' ':!.gtkrc-2.0' >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" config status.showUntrackedFiles no

	# Modify files to create conflicts
	echo "user modified" > "$HOME/.bashrc"
	echo "user modified" > "$HOME/.gitconfig"

	run run_restore_desktop --auto-stash
	[ "$status" -eq 0 ]

	# No backup directory should be created (auto-stash skips backup)
	assert_backup_count 0

	# Files should be repo versions (conflicts removed, then checked out)
	assert_file_contains ".bashrc" "repo content for .bashrc"
	assert_file_contains ".gitconfig" "repo content for .gitconfig"

	# Output should mention auto-stash
	[[ "$output" == *"auto-stash"* ]]
}

# TC-26: restore-desktop.sh fails when not in server state

@test "TC-26: restore-desktop fails in fresh state" {
	setup_source_repo
	# Don't setup any .cfg - fresh state

	run run_restore_desktop
	[ "$status" -eq 1 ]
	# In fresh state, fails at validation before state check
	[[ "$output" == *"not found"* ]] || [[ "$output" == *"Run install"* ]]
}

@test "TC-26b: restore-desktop fails in desktop state" {
	setup_source_repo
	setup_installed_state

	# We're in desktop state (has desktop indicators)
	run run_restore_desktop
	[ "$status" -eq 1 ]
	[[ "$output" == *"requires server state"* ]]
	[[ "$output" == *"current state is desktop"* ]]
}
