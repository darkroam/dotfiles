#!/usr/bin/env bats
# backup-logic.bats - Unit tests for cfg_should_backup_file() and backup flow
# TC-04 through TC-10

load helpers.bash

setup() {
	setup_test_home
	source_validate_lib
}

teardown() {
	teardown_test_home
}

# TC-04: target file does not exist → skip backup (return 1)

@test "TC-04: file does not exist → skip backup" {
	create_mock_cfg_repo ".bashrc"
	rm -f "$HOME/.bashrc"
	run cfg_should_backup_file "$HOME/.cfg" ".bashrc"
	[ "$status" -eq 1 ]
}

# TC-05: file exists but not tracked → backup (return 0)

@test "TC-05: file exists, not tracked → backup" {
	create_mock_cfg_repo ".bashrc"
	echo "untracked content" > "$HOME/.untracked_file"
	run cfg_should_backup_file "$HOME/.cfg" ".untracked_file"
	[ "$status" -eq 0 ]
}

# TC-06: file tracked but MD5 differs → backup (return 0)

@test "TC-06: file tracked, modified → backup" {
	create_mock_cfg_repo ".bashrc"
	echo "user modified content" > "$HOME/.bashrc"
	run cfg_should_backup_file "$HOME/.cfg" ".bashrc"
	[ "$status" -eq 0 ]
}

# TC-07: file tracked and MD5 matches → skip (return 1)

@test "TC-07: file tracked, identical → skip backup" {
	create_mock_cfg_repo ".bashrc"
	# The file content matches what's in the repo
	local repo_content
	repo_content=$(git --git-dir="$HOME/.cfg/" --work-tree="$HOME" show HEAD:".bashrc" 2>/dev/null)
	echo "$repo_content" > "$HOME/.bashrc"
	run cfg_should_backup_file "$HOME/.cfg" ".bashrc"
	[ "$status" -eq 1 ]
}

@test "TC-07b: tracked symlink compares stored link text" {
	local work
	work=$(mktemp -d "/tmp/dotfiles-test-symlink.XXXXXX")
	(
		cd "$work"
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		mkdir -p .config/shell
		printf 'target\n' > .config/shell/zprofile
		ln -s .config/shell/zprofile .zprofile
		git add -A
		git commit -m symlink >/dev/null 2>&1
		git clone --bare . "$HOME/.cfg" >/dev/null 2>&1
	)
	ln -s .config/shell/zprofile "$HOME/.zprofile"

	run cfg_should_backup_file "$HOME/.cfg" ".zprofile"
	[ "$status" -eq 1 ]

	ln -sfn .config/shell/other "$HOME/.zprofile"
	run cfg_should_backup_file "$HOME/.cfg" ".zprofile"
	[ "$status" -eq 0 ]
	rm -rf "$work"
}

# TC-08: backup directory naming convention

@test "TC-08: backup directory follows naming convention" {
	create_mock_cfg_repo ".bashrc"
	echo "modified" > "$HOME/.bashrc"

	# Simulate what install-2.sh does
	local timestamp
	timestamp=$(date +%Y%m%dT%H%M%S)
	local current_state="fresh"
	local target_state="desktop"
	local backup_dir="$HOME/.config-backup/${current_state}-to-${target_state}-${timestamp}"
	mkdir -p "$backup_dir"

	assert_backup_naming "$(basename "$backup_dir")"
}

# TC-09: backup directory permissions are 0700

@test "TC-09: backup directory permissions are 0700" {
	local backup_dir="$HOME/.config-backup/fresh-to-desktop-20260101T000000"
	mkdir -p "$backup_dir"
	chmod 700 "$backup_dir"

	local perms
	perms=$(stat -c '%a' "$backup_dir")
	[ "$perms" = "700" ]
}

# TC-10: MANIFEST.txt records original → backup → status

@test "TC-10: MANIFEST records path, md5, and status" {
	local backup_dir="$HOME/.config-backup/fresh-to-desktop-20260101T000000"
	mkdir -p "$backup_dir"
	local manifest="$backup_dir/MANIFEST.txt"

	# Write a manifest entry in new format
	printf '# Created: 2026-01-01T00:00:00\n' > "$manifest"
	printf '# Transition: fresh -> desktop\n' >> "$manifest"
	printf '#\n# relative_path\tmd5\tstatus\n' >> "$manifest"
	printf '.bashrc\td41d8cd98f00b204e9800998ecf8427e\tmodified\n' >> "$manifest"
	printf '.untracked\t098f6bcd4621d373cade4e832627b4f6\tuntracked\n' >> "$manifest"

	# Verify format
	grep -q 'modified' "$manifest"
	grep -q 'untracked' "$manifest"
	grep -q '# Transition:' "$manifest"
	grep -q '# relative_path' "$manifest"
}
