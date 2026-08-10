#!/usr/bin/env bats
# fresh-node.bats - Fresh root node, track/untrack and fresh-* command tests
# TC-F01 through TC-F11

load helpers.bash

setup() {
	setup_test_home
	setup_bootstrap_env
	mkdir -p "$HOME/.config/app" "$HOME/.config/ignored" "$HOME/.local/share"
	echo "user original bashrc" > "$HOME/.bashrc"
	echo "unmanaged config" > "$HOME/.config/app/unmanaged.conf"
	echo "tracked config original" > "$HOME/.config/ignored/tracked.conf"
	echo "excluded unmanaged config" > "$HOME/.config/ignored/unmanaged.conf"
	echo "unmanaged root data" > "$HOME/.unmanaged-root"
	echo "user local original" > "$HOME/.local/share/tracked-test.conf"
	echo "unmanaged local state" > "$HOME/.local/share/unmanaged-state"
	run run_dotcfg status # triggers bootstrap
	[ "$status" -eq 0 ]
	BOOTSTRAP_OUTPUT="$output"
}

teardown() {
	teardown_test_home
	teardown_bootstrap_env
}

fresh_manifest() {
	printf '%s' "$HOME/.config-backup/nodes/fresh_root/manifest.txt"
}

# TC-F01: fresh_root node with 5-column manifest, tracked_at_install status

@test "TC-F01: fresh_root node created with 5-column manifest" {
	local manifest
	manifest=$(fresh_manifest)
	[ -f "$manifest" ]

	local line
	line=$(grep "^\.bashrc" "$manifest")
	[ -n "$line" ]
	# Exactly 5 tab-separated columns: path, md5, size, status, timestamp.
	local cols
	cols=$(printf '%s' "$line" | awk -F'\t' '{print NF}')
	[ "$cols" -eq 5 ]
	[[ "$line" == *"tracked_at_install"* ]]

	# md5 column preserves the pre-checkout user file.
	local md5
	md5=$(printf 'user original bashrc\n' | md5sum | cut -d' ' -f1)
	[[ "$line" == *"$md5"* ]]

	# Mixed mode: all ~/.config files plus tracked paths elsewhere.
	[ -f "$HOME/.config-backup/nodes/fresh_root/backup/.config/app/unmanaged.conf" ]
	[ -f "$HOME/.config-backup/nodes/fresh_root/backup/.config/ignored/tracked.conf" ]
	[ ! -e "$HOME/.config-backup/nodes/fresh_root/backup/.config/ignored/unmanaged.conf" ]
	[ -f "$HOME/.config-backup/nodes/fresh_root/backup/.local/share/tracked-test.conf" ]
	[ ! -e "$HOME/.config-backup/nodes/fresh_root/backup/.unmanaged-root" ]
	[ ! -e "$HOME/.config-backup/nodes/fresh_root/backup/.local/share/unmanaged-state" ]
	[ ! -e "$HOME/.config-backup/nodes/fresh_root/backup/.local/bin/dotcfg" ]
	[[ "$BOOTSTRAP_OUTPUT" == *"Creating fresh backup (mixed mode)"* ]]
	[[ "$BOOTSTRAP_OUTPUT" == *"~/.config/: 2 files backed up (full)"* ]]
	[[ "$BOOTSTRAP_OUTPUT" == *"Other tracked files: 1 files backed up"* ]]
	[[ "$BOOTSTRAP_OUTPUT" == *"~/.local/ tracked files: 1 files backed up"* ]]
	[[ "$BOOTSTRAP_OUTPUT" == *"Total: 4 files backed up to fresh_root"* ]]
}

# TC-F02: track adds a file with tracked_by_user status

@test "TC-F02: track backs up file and marks it tracked_by_user" {
	echo "new config" > "$HOME/.myconfig"

	run run_dotcfg track .myconfig --no-add
	[ "$status" -eq 0 ]

	[ -f "$HOME/.config-backup/nodes/fresh_root/backup/.myconfig" ]
	grep -q "tracked_by_user" "$(fresh_manifest)"
}

# TC-F03: track refuses duplicates

@test "TC-F03: track duplicate file is refused" {
	run run_dotcfg track .bashrc --no-add
	[ "$status" -ne 0 ]
	assert_output_contains "already in fresh node backup"
}

# TC-F04: track warns on excluded path but proceeds

@test "TC-F04: track warns on excluded file but tracks it anyway" {
	echo "log data" > "$HOME/.somefile.log"

	run run_dotcfg track .somefile.log --no-add
	[ "$status" -eq 0 ]
	assert_output_contains "exclusion rule"
	[ -f "$HOME/.config-backup/nodes/fresh_root/backup/.somefile.log" ]
}

# TC-F05: untrack removes backup file and manifest entry

@test "TC-F05: untrack removes file from fresh backup" {
	echo "new config" > "$HOME/.myconfig"
	run run_dotcfg track .myconfig --no-add
	[ "$status" -eq 0 ]

	run run_dotcfg untrack .myconfig --force
	[ "$status" -eq 0 ]

	[ ! -f "$HOME/.config-backup/nodes/fresh_root/backup/.myconfig" ]
	run grep ".myconfig" "$(fresh_manifest)"
	[ "$status" -ne 0 ]
}

# TC-F06: untrack requires confirmation without --force

@test "TC-F06: untrack asks for confirmation and can be cancelled" {
	echo "new config" > "$HOME/.myconfig"
	run run_dotcfg track .myconfig --no-add
	[ "$status" -eq 0 ]

	run bash -c "printf 'n\n' | bash '$DOTCFG' untrack .myconfig"
	[ "$status" -eq 0 ]
	assert_output_contains "Cancelled"
	[ -f "$HOME/.config-backup/nodes/fresh_root/backup/.myconfig" ]
}

# TC-F07: fresh-status shows statistics

@test "TC-F07: fresh-status reports backup statistics" {
	run run_dotcfg fresh-status
	[ "$status" -eq 0 ]
	assert_output_contains "fresh_root"
	assert_output_contains "tracked_at_install"
}

# TC-F08: fresh-diff classifies Modified / New / Missing

@test "TC-F08: fresh-diff detects modified, new and missing files" {
	echo "changed content" > "$HOME/.bashrc"        # modified
	mkdir -p "$HOME/.config/new-app"
	echo "brand new" > "$HOME/.config/new-app/brandnew" # new

	run run_dotcfg fresh-diff
	[ "$status" -eq 0 ]
	assert_output_contains "Modified files"
	assert_output_contains "New files"
	assert_output_contains ".config/new-app/brandnew"
}

# TC-F09: fresh-update rebuilds backup and keeps a .bak copy

@test "TC-F09: fresh-update rebuilds backup with .bak protection" {
	echo "changed content" > "$HOME/.bashrc"

	run run_dotcfg fresh-update --force
	[ "$status" -eq 0 ]

	[ -d "$HOME/.config-backup/nodes/fresh_root.bak" ]
	# manifest now reflects the new content
	local md5
	md5=$(md5sum "$HOME/.bashrc" | cut -d' ' -f1)
	grep -q "$md5" "$(fresh_manifest)"
	[ -f "$HOME/.config-backup/nodes/fresh_root/backup/.bashrc" ]
}

# TC-F10: root node protection

@test "TC-F10: remove fresh_root is refused" {
	run run_dotcfg remove fresh_root
	[ "$status" -eq 1 ]
	assert_output_contains "Cannot remove root node"
}

# TC-F11: fresh alias and ● marker

@test "TC-F11: switch fresh resolves to root; list shows root marker" {
	run run_dotcfg switch fresh
	[ "$status" -eq 0 ]
	assert_output_contains "Already at node fresh_root"

	run run_dotcfg list
	[ "$status" -eq 0 ]
	assert_output_contains "●"
}
