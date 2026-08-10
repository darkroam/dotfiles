#!/usr/bin/env bats
# e2e-state-machine.bats - End-to-end state transition tests
# TC-36 through TC-38: Full lifecycle and category invariants

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
	teardown_source_repo
}

# TC-36: fresh → desktop → server → desktop → fresh

@test "TC-36: full lifecycle fresh→desktop→server→desktop→fresh" {
	setup_source_repo

	# ── Fresh state: create user files ──
	echo "user's original bashrc" > "$HOME/.bashrc"
	echo "user's original gitconfig" > "$HOME/.gitconfig"
	mkdir -p "$HOME/.ssh"
	echo "Host *" > "$HOME/.ssh/config"
	assert_state_is "fresh"

	# ── fresh → desktop (install-2.sh) ──
	run run_install_desktop
	[ "$status" -eq 0 ]
	assert_state_is "full"
	assert_cfg_exists
	assert_checkout_state_exists
	assert_file_exists ".xinitrc"
	assert_file_contains ".bashrc" "repo content for .bashrc"
	assert_node_backup_exists
	assert_node_backup_contains ".bashrc"
	assert_node_backup_contains ".gitconfig"

	# ── desktop → server (restore-server.sh) ──
	run run_restore_server
	[ "$status" -eq 0 ]
	assert_state_is "min"
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".xprofile"
	assert_file_exists ".bashrc"
	assert_file_exists ".config/shell/profile"

	# ── server → desktop (restore-desktop.sh) ──
	run run_restore_desktop
	[ "$status" -eq 0 ]
	assert_state_is "full"
	assert_file_exists ".xinitrc"
	assert_file_exists ".xprofile"
	assert_file_exists ".bashrc"
	assert_file_exists ".config/x11/xinitrc"

	# ── desktop → fresh (uninstall.sh) ──
	run run_uninstall
	[ "$status" -eq 0 ]

	# Repo-only files should be removed
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".config/shell/profile"
	assert_checkout_state_not_exists

	# .cfg should still exist (manual removal)
	assert_cfg_exists

	# User's original files should be restored from the latest backup
	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "user's original bashrc"
	assert_file_exists ".gitconfig"
	assert_file_contains ".gitconfig" "user's original gitconfig"

	# Untracked files (like .ssh/config) should still exist (never touched)
	assert_file_exists ".ssh/config"
}

# TC-37: fresh → server → desktop → server → fresh

@test "TC-37: full lifecycle fresh→server→desktop→server→fresh" {
	setup_source_repo

	# ── Fresh state: create user files ──
	echo "user's server bashrc" > "$HOME/.bashrc"
	echo "user's server gitconfig" > "$HOME/.gitconfig"
	assert_state_is "fresh"

	# ── fresh → server (install-server.sh) ──
	run run_install_server
	[ "$status" -eq 0 ]
	assert_state_is "min"
	assert_cfg_exists
	assert_checkout_state_exists
	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "repo content for .bashrc"
	assert_file_not_exists ".xinitrc"
	assert_node_backup_exists
	assert_node_backup_contains ".bashrc"

	# ── server → desktop (restore-desktop.sh) ──
	run run_restore_desktop
	[ "$status" -eq 0 ]
	assert_state_is "full"
	assert_file_exists ".xinitrc"
	assert_file_exists ".xprofile"
	assert_file_exists ".bashrc"
	assert_file_exists ".config/x11/xinitrc"

	# ── desktop → server (restore-server.sh) ──
	run run_restore_server
	[ "$status" -eq 0 ]
	assert_state_is "min"
	assert_file_not_exists ".xinitrc"
	assert_file_not_exists ".xprofile"
	assert_file_exists ".bashrc"
	assert_file_exists ".config/shell/profile"

	# ── server → fresh (uninstall.sh) ──
	run run_uninstall
	[ "$status" -eq 0 ]

	# Repo-only files removed
	assert_file_not_exists ".config/shell/profile"
	assert_checkout_state_not_exists
	assert_cfg_exists

	# User's original files restored from latest backup
	assert_file_exists ".bashrc"
	assert_file_contains ".bashrc" "user's server bashrc"
	assert_file_exists ".gitconfig"
	assert_file_contains ".gitconfig" "user's server gitconfig"
}

@test "TC-38: full to min removes ordinary local scripts but preserves dotcfg infrastructure" {
	setup_source_repo \
		".bashrc" ".xinitrc" ".local/bin/tool" ".local/bin/dotcfg" \
		".local/lib/dotfiles/cfg-validate.sh"
	mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/dotfiles"
	printf 'installed dotcfg sentinel\n' > "$HOME/.local/bin/dotcfg"
	printf 'installed library sentinel\n' > "$HOME/.local/lib/dotfiles/keep"

	run bash -c "printf 'y\n' | bash '$DOTCFG' switch full"
	[ "$status" -eq 0 ]
	assert_file_exists ".local/bin/tool"
	assert_file_exists ".local/bin/dotcfg"
	assert_file_exists ".local/lib/dotfiles/keep"

	run bash -c "printf 'y\n' | bash '$DOTCFG' switch min"
	[ "$status" -eq 0 ]
	assert_state_is "min"
	assert_file_not_exists ".local/bin/tool"
	assert_file_exists ".local/bin/dotcfg"
	assert_file_exists ".local/lib/dotfiles/keep"
}
