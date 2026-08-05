#!/usr/bin/env bats
# uninstall.bats - Integration tests for uninstall.sh
# TC-30 through TC-33, TC-38 through TC-43

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
	teardown_source_repo
}

# TC-30: Uninstall after desktop install — all repo files removed

@test "TC-30: uninstall removes all checked-out files" {
	setup_source_repo
	setup_installed_state

	# Verify files exist before uninstall
	assert_file_exists ".bashrc"
	assert_file_exists ".gitconfig"
	assert_file_exists ".xinitrc"
	assert_cfg_exists

	run run_uninstall
	[ "$status" -eq 0 ]

	# All checked-out files should be removed
	assert_file_not_exists ".bashrc"
	assert_file_not_exists ".gitconfig"
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".profile"
	assert_file_not_exists ".config/shell/profile"

	# .cfg should still exist (manual removal required)
	assert_cfg_exists

	# Checkout state should be removed
	assert_checkout_state_not_exists
}

# TC-31: Uninstall restores from earliest backup in chain

@test "TC-31: uninstall restores user files from earliest backup" {
	setup_source_repo

	# Simulate fresh install with pre-existing user files (creates backup)
	echo "user's original bashrc" > "$HOME/.bashrc"
	echo "user's original gitconfig" > "$HOME/.gitconfig"

	run run_install_desktop
	[ "$status" -eq 0 ]

	# Verify backup was created
	assert_backup_dir_exists
	assert_file_contains ".bashrc" "repo content for .bashrc"

	# Now uninstall — should restore user's original files from earliest backup
	run run_uninstall
	[ "$status" -eq 0 ]

	# Repo files should be removed
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".config/shell/profile"

	# User's original files should be restored from backup
	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "user's original bashrc"
	assert_file_exists ".gitconfig"
	assert_file_contains ".gitconfig" "user's original gitconfig"
}

# TC-32: --dry-run makes no changes

@test "TC-32: uninstall --dry-run reports plan without modifying" {
	setup_source_repo
	setup_installed_state

	assert_file_exists ".bashrc"
	assert_cfg_exists

	run run_uninstall --dry-run
	[ "$status" -eq 0 ]

	# Everything should still be in place
	assert_file_exists ".bashrc"
	assert_file_exists ".gitconfig"
	assert_cfg_exists
	assert_checkout_state_exists

	[[ "$output" == *"DRY RUN"* ]]
}

# TC-33: Uninstall with no .cfg → error

@test "TC-33: uninstall fails when no repository exists" {
	run run_uninstall
	[ "$status" -eq 1 ]

	[[ "$output" == *"Nothing to uninstall"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"Repository not found"* ]]
}

# TC-38: Uninstall removes .cfg-checkout-state metadata

@test "TC-38: uninstall removes checkout state file" {
	setup_source_repo
	setup_installed_state

	assert_checkout_state_exists

	run run_uninstall
	[ "$status" -eq 0 ]

	assert_checkout_state_not_exists

	# .cfg itself should still exist
	assert_cfg_exists
}

# TC-39: --latest restores newest version from backup chain

@test "TC-39: uninstall --latest restores newest backup version" {
	setup_source_repo

	# Create initial user file
	echo "version 1" > "$HOME/.bashrc"

	# fresh → desktop: backs up "version 1"
	run run_install_desktop
	[ "$status" -eq 0 ]
	assert_backup_count 1

	# Modify .bashrc to simulate user change
	echo "version 2" > "$HOME/.bashrc"

	# Reinstall (will backup "version 2" as modified)
	run run_install_desktop --reinstall
	[ "$status" -eq 0 ]

	# Now we have two backup sessions
	# --latest should restore "version 2"
	run run_uninstall --latest
	[ "$status" -eq 0 ]

	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "version 2"
}

# TC-40: Multi-transition chain — uninstall restores all backed-up files

@test "TC-40: multi-transition uninstall restores files from all sessions" {
	setup_source_repo

	# Fresh: create user files
	echo "user's original bashrc" > "$HOME/.bashrc"
	echo "user's original gitconfig" > "$HOME/.gitconfig"

	# fresh → desktop: backs up .bashrc and .gitconfig
	run run_install_desktop
	[ "$status" -eq 0 ]
	assert_backup_count 1

	# Modify a file that will be backed up in next transition
	echo "user modified gitconfig" > "$HOME/.gitconfig"

	# desktop → server: backs up modified .gitconfig, removes desktop files
	run run_restore_server
	[ "$status" -eq 0 ]
	assert_backup_count 2

	# Uninstall should restore from earliest backup for each file
	# .bashrc: only in session 1 (fresh-to-desktop) → restored from there
	# .gitconfig: in session 1 (untracked) and session 2 (modified) → earliest = session 1
	run run_uninstall
	[ "$status" -eq 0 ]

	# Both files should be restored
	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "user's original bashrc"
	assert_file_exists ".gitconfig"
	assert_file_contains ".gitconfig" "user's original gitconfig"

	# Desktop-only files should be gone
	assert_file_not_exists ".xinitrc"
}

# TC-41: Idempotency — running uninstall twice produces same result

@test "TC-41: uninstall is idempotent" {
	setup_source_repo

	echo "user's original bashrc" > "$HOME/.bashrc"

	# Install then uninstall
	run run_install_desktop
	[ "$status" -eq 0 ]

	run run_uninstall
	[ "$status" -eq 0 ]

	# Record state after first uninstall
	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "user's original bashrc"
	assert_file_not_exists ".xinitrc"
	assert_checkout_state_not_exists

	# Run uninstall again — should succeed with nothing to do
	run run_uninstall
	[ "$status" -eq 0 ]

	# Same state
	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "user's original bashrc"
	assert_file_not_exists ".xinitrc"
	assert_checkout_state_not_exists
}

# TC-42: --clean-backups deletes all backup directories

@test "TC-42: --clean-backups removes all backup sessions" {
	setup_source_repo

	echo "user's bashrc" > "$HOME/.bashrc"

	run run_install_desktop
	[ "$status" -eq 0 ]
	assert_backup_dir_exists

	run run_uninstall --clean-backups
	[ "$status" -eq 0 ]

	# Backup directory should be completely removed
	[ ! -d "$HOME/.config-backup" ] || {
		echo "expected .config-backup to be removed" >&2
		return 1
	}
}

# TC-43: Files in managed set but not in any backup are deleted without restore

@test "TC-43: managed files without backup are deleted" {
	setup_source_repo
	setup_installed_state

	# .xinitrc is managed (in checkout state) but was never backed up
	# (fresh install with no pre-existing files → no backup created)
	assert_file_exists ".xinitrc"
	assert_backup_count 0

	run run_uninstall
	[ "$status" -eq 0 ]

	# Should be deleted
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".bashrc"
	assert_file_not_exists ".gitconfig"
}
