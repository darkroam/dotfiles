#!/usr/bin/env bats
# exclude-rules.bats - Fresh backup exclusion rule tests
# TC-E01 through TC-E04

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
}

# TC-E01: hardcoded exclusion rules

@test "TC-E01: hardcoded rules exclude Downloads, caches and histories" {
	run run_dotcfg check-exclude Downloads/foo.tar.gz
	[ "$status" -eq 0 ]
	assert_output_contains "hardcoded"

	run run_dotcfg check-exclude .cache/x
	[ "$status" -eq 0 ]
	assert_output_contains "hardcoded"

	run run_dotcfg check-exclude .bash_history
	[ "$status" -eq 0 ]
	assert_output_contains "hardcoded"
}

# TC-E02: regular config path is not excluded

@test "TC-E02: normal config path is not excluded" {
	run run_dotcfg check-exclude .config/app/settings.ini
	[ "$status" -eq 1 ]
	assert_output_contains "not excluded"
}

# TC-E03: exclude.conf rules are honored

@test "TC-E03: exclude.conf rule excludes matching paths" {
	# Work on a private copy of the library so the real exclude.conf is untouched
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$HOME/dlib"
	printf 'mycustom/*\n' > "$HOME/dlib/exclude.conf"

	run env DOTFILES_LIB_DIR="$HOME/dlib" bash "$HOME/dlib/commands/check-exclude.sh" "mycustom/thing"
	[ "$status" -eq 0 ]
	assert_output_contains "exclude.conf"
}

# TC-E04: absolute paths in exclude.conf are ignored

@test "TC-E04: absolute path in exclude.conf is ignored with warning" {
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$HOME/dlib"
	printf '/etc/passwd\n' > "$HOME/dlib/exclude.conf"

	run env DOTFILES_LIB_DIR="$HOME/dlib" bash "$HOME/dlib/commands/check-exclude.sh" "etc/passwd"
	[ "$status" -eq 1 ]
	assert_output_contains "not excluded"
}
