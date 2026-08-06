#!/usr/bin/env bats
# validate.bats - Unit tests for cfg_validate() in cfg-validate.sh
# TC-34, TC-35

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
}

# TC-34: cfg_validate correctly identifies .cfg states

@test "TC-34a: no .cfg directory → missing" {
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "missing" ]
	[ "$CFG_IS_OURS" = "false" ]
}

@test "TC-34b: .cfg is a regular file → not_git" {
	touch "$HOME/.cfg"
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "not_git" ]
}

@test "TC-34c: .cfg is an empty directory → not_git" {
	mkdir -p "$HOME/.cfg"
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "not_git" ]
}

@test "TC-34d: .cfg is a non-bare git repo → not_git" {
	mkdir -p "$HOME/.cfg"
	(cd "$HOME/.cfg" && git init >/dev/null 2>&1)
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "not_git" ]
}

@test "TC-34e: bare repo, no remote, no signature → foreign_repo" {
	create_mock_cfg_repo ".bashrc"
	# Remove the origin remote to test no-remote case
	git --git-dir="$HOME/.cfg/" remote remove origin 2>/dev/null || true
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "foreign_repo" ]
	[ "$CFG_IS_OURS" = "false" ]
}

@test "TC-34f: bare repo with correct SSH remote → valid" {
	create_mock_cfg_repo_with_remote "git@github.com:darkroam/dotfiles.git" ".bashrc" ".local/bin/dotcfg"
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "valid" ]
	[ "$CFG_IS_OURS" = "true" ]
}

@test "TC-34g: bare repo with signature file, no remote → valid" {
	create_mock_cfg_repo ".local/bin/dotcfg" ".bashrc"
	git --git-dir="$HOME/.cfg/" remote remove origin 2>/dev/null || true
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "valid" ]
	[ "$CFG_IS_OURS" = "true" ]
}

@test "TC-34h: .cfg is a symlink to valid bare repo → valid" {
	local real_dir="$HOME/real-cfg"
	create_mock_cfg_repo ".local/bin/dotcfg" ".bashrc"
	mv "$HOME/.cfg" "$real_dir"
	ln -s "$real_dir" "$HOME/.cfg"
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "valid" ]
}

@test "TC-34i: .cfg is a broken symlink → not_git" {
	ln -s /nonexistent/path "$HOME/.cfg"
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "not_git" ]
}

@test "TC-34j: bare repo with wrong remote URL → foreign_repo" {
	create_mock_cfg_repo_with_remote "git@github.com:someone/else.git" ".bashrc"
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "foreign_repo" ]
	[ "$CFG_IS_OURS" = "false" ]
}

@test "TC-34k: HTTPS URL normalized to match SSH → valid" {
	create_mock_cfg_repo_with_remote "https://github.com/darkroam/dotfiles.git" ".bashrc" ".local/bin/dotcfg"
	source_validate_lib
	cfg_validate "$HOME/.cfg"
	[ "$CFG_STATE" = "valid" ]
}

# TC-35: new scripts require validation library

@test "TC-35: consolidated scripts require validation library" {
	# Verify the unified switch.sh sources utils/common.sh
	local switch_sh="$DOTFILES_ROOT/.local/lib/dotfiles/commands/switch.sh"
	grep -q "utils/common.sh" "$switch_sh"
	grep -q "utils/common.sh" "$COMMANDS_UNINSTALL"
	# Forwarder scripts reference switch.sh
	grep -q "switch.sh" "$SWITCH_DESKTOP"
	grep -q "switch.sh" "$SWITCH_SERVER"
}
