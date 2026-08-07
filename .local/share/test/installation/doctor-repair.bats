#!/usr/bin/env bats
# doctor-repair.bats - System integrity check and repair tests
# TC-D01 through TC-D04

load helpers.bash

setup() {
	setup_test_home
	setup_bootstrap_env
	run run_dotcfg status # triggers bootstrap
	[ "$status" -eq 0 ]
}

teardown() {
	teardown_test_home
	teardown_bootstrap_env
}

# TC-D01: doctor on a healthy system

@test "TC-D01: doctor reports healthy system" {
	run run_dotcfg doctor
	[ "$status" -eq 0 ]
	assert_output_contains "healthy"
	assert_output_contains "Issues found: 0"
}

# TC-D02: doctor detects broken HEAD; repair fixes it

@test "TC-D02: doctor detects invalid HEAD and repair resets it" {
	echo "nonexistent" > "$HOME/.config-backup/HEAD"

	run run_dotcfg doctor
	[ "$status" -eq 1 ]
	assert_output_contains "invalid node"

	run run_dotcfg repair --force
	[ "$status" -eq 0 ]

	[ "$(cat "$HOME/.config-backup/HEAD")" = "fresh_root" ]

	run run_dotcfg doctor
	[ "$status" -eq 0 ]
}

# TC-D03: repair restores missing DEPLOY_STATUS

@test "TC-D03: repair restores missing DEPLOY_STATUS" {
	rm -f "$HOME/.config-backup/DEPLOY_STATUS"

	run run_dotcfg doctor
	[ "$status" -eq 1 ]

	run run_dotcfg repair --force
	[ "$status" -eq 0 ]

	[ "$(cat "$HOME/.config-backup/DEPLOY_STATUS")" = "deployed" ]
}

# TC-D04: lightweight startup self-check hints at doctor

@test "TC-D04: startup self-check warns when HEAD points to missing node" {
	echo "nonexistent" > "$HOME/.config-backup/HEAD"

	run run_dotcfg list
	[ "$status" -eq 0 ]
	assert_output_contains "dotcfg doctor"
}
