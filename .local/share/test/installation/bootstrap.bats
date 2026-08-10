#!/usr/bin/env bats
# bootstrap.bats - Bootstrap installation tests (self-install when library missing)
# TC-B01 through TC-B03

load helpers.bash

setup() {
	setup_test_home
	setup_bootstrap_env
}

teardown() {
	teardown_test_home
	teardown_bootstrap_env
}

# TC-B01: Full bootstrap install from local mock remote

@test "TC-B01: bootstrap installs library, fresh_root node and deploys" {
	echo "user original" > "$HOME/.bashrc"
	[ ! -e "$HOME/.local/bin" ]

	run run_dotcfg status
	[ "$status" -eq 0 ]
	assert_output_contains "bootstrap installation"

	# Command directory and executable are created from a fresh HOME
	[ -x "$HOME/.local/bin/dotcfg" ]

	# Library installed into test HOME
	[ -f "$HOME/.local/lib/dotfiles/cfg-validate.sh" ]
	[ -f "$HOME/.local/lib/dotfiles/utils/fresh.sh" ]
	[ -f "$HOME/.local/lib/dotfiles/utils/exclude.sh" ]

	# Repository cloned
	[ -d "$HOME/.cfg" ]

	# fresh_root node with mixed-mode backup and manifest
	[ -d "$HOME/.config-backup/nodes/fresh_root/backup" ]
	[ -f "$HOME/.config-backup/nodes/fresh_root/manifest.txt" ]
	grep -q $'^\.bashrc\t' "$HOME/.config-backup/nodes/fresh_root/manifest.txt"
	[ -f "$HOME/.config-backup/nodes/fresh_root/backup/.bashrc" ]

	# State files
	[ "$(cat "$HOME/.config-backup/HEAD")" = "fresh_root" ]
	[ "$(cat "$HOME/.config-backup/DEPLOY_STATUS")" = "deployed" ]
	[ "$(cat "$HOME/.config-backup/CURRENT_CONFIG_VERSION")" = "bootstrap" ]
}

# TC-B02: Existing foreign repository is refused

@test "TC-B02: bootstrap refuses foreign repository" {
	git init --bare "$HOME/.cfg" >/dev/null 2>&1
	local work
	work=$(mktemp -d "/tmp/dotfiles-test-foreign.XXXXXX")
	(cd "$work" && {
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		echo "foreign" > README.md
		git add -A
		git commit -m "foreign" >/dev/null 2>&1
		git push --quiet "$HOME/.cfg" HEAD:refs/heads/master 2>/dev/null || \
			git push --quiet "$HOME/.cfg" HEAD:refs/heads/main
	})
	rm -rf "$work"

	run run_dotcfg status
	[ "$status" -eq 1 ]
	assert_output_contains "rm -rf"
}

# TC-B03: Idempotency — second run uses normal mode

@test "TC-B03: bootstrap is idempotent (second run uses normal mode)" {
	run run_dotcfg status
	[ "$status" -eq 0 ]
	assert_output_contains "bootstrap installation"

	run run_dotcfg status
	[ "$status" -eq 0 ]
	[[ "$output" != *"bootstrap installation"* ]]
	assert_output_contains "fresh_root"
}
