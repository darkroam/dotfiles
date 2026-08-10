#!/usr/bin/env bats
# deploy-undeploy.bats - Tests for deploy and undeploy commands

load helpers.bash

DEPLOY_CMD="$DOTFILES_ROOT/.local/lib/dotfiles/commands/deploy.sh"
UNDEPLOY_CMD="$DOTFILES_ROOT/.local/lib/dotfiles/commands/undeploy.sh"
NODES_LIB="$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"

setup() {
	setup_test_home
	source_nodes_lib
}

teardown() {
	teardown_test_home
}

source_nodes_lib() {
	unset _CFG_NODES_LOADED
	. "$NODES_LIB"
}

# ── Helpers ────────────────────────────────────────────────────────────

setup_node_with_repo() {
	setup_source_repo
	setup_installed_state

	cfg_nodes_init "$HOME/.config-backup"
	local root_code
	root_code=$(cfg_node_create "fresh" "null")
	local desktop_code
	desktop_code=$(cfg_node_create "desktop" "$root_code")
	cfg_head_set "$desktop_code"
	cfg_deploy_status_set "deployed"
}

run_deploy() {
	yes | bash "$DEPLOY_CMD" "$@" 2>&1
}

run_undeploy() {
	yes | bash "$UNDEPLOY_CMD" "$@" 2>&1
}

# ── Deploy Tests ───────────────────────────────────────────────────────

@test "TC-D01: deploy fails when HEAD not set" {
	setup_source_repo
	setup_installed_state
	mkdir -p "$HOME/.config-backup/nodes"
	cfg_nodes_init "$HOME/.config-backup"

	run run_deploy
	[[ "$output" == *"HEAD not set"* ]]
}

@test "TC-D02: deploy on already deployed node exits gracefully" {
	setup_node_with_repo

	run run_deploy
	[ "$status" -eq 0 ]
	[[ "$output" == *"already deployed"* ]]
}

@test "TC-D03: deploy --force redeploys" {
	setup_node_with_repo

	run run_deploy --force
	[ "$status" -eq 0 ]
	[[ "$output" == *"Deploy Complete"* ]]
}

@test "TC-D04: deploy on fresh node reports nothing to deploy" {
	setup_source_repo
	cfg_nodes_init "$HOME/.config-backup"
	local root_code
	root_code=$(cfg_node_create "fresh" "null")
	cfg_head_set "$root_code"
	cfg_deploy_status_set "uninstalled"

	run run_deploy
	[ "$status" -eq 0 ]
	[[ "$output" == *"fresh"* ]]
	[[ "$output" == *"Nothing to deploy"* ]]
}

@test "TC-D05: deploy --dry-run makes no changes" {
	setup_node_with_repo
	cfg_deploy_status_set "uninstalled"

	run run_deploy --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"dry-run"* ]]
}

# ── Undeploy Tests ─────────────────────────────────────────────────────

@test "TC-U01: undeploy fails when HEAD not set" {
	mkdir -p "$HOME/.config-backup/nodes"
	cfg_nodes_init "$HOME/.config-backup"

	run run_undeploy
	[[ "$output" == *"HEAD not set"* ]]
}

@test "TC-U02: undeploy on already uninstalled node exits gracefully" {
	setup_node_with_repo
	cfg_deploy_status_set "uninstalled"

	run run_undeploy
	[ "$status" -eq 0 ]
	[[ "$output" == *"already undeployed"* ]]
}

@test "TC-U03: undeploy on deployed fresh node restores backup" {
	setup_source_repo
	cfg_nodes_init "$HOME/.config-backup"

	echo "original bashrc" > "$HOME/.bashrc"
	local root_code
	root_code=$(cfg_node_create "fresh" "null")
	cfg_head_set "$root_code"
	cfg_deploy_status_set "deployed"

	mkdir -p "$HOME/.config-backup/nodes/$root_code/backup"
	echo "pre-install bashrc" > "$HOME/.config-backup/nodes/$root_code/backup/.bashrc"
	mkdir -p "$HOME/.config-backup/nodes/$root_code/backup/.config/shell"
	echo "pre-install zprofile" > "$HOME/.config-backup/nodes/$root_code/backup/.config/shell/zprofile"
	ln -s .config/shell/zprofile "$HOME/.config-backup/nodes/$root_code/backup/.zprofile"
	printf '.bashrc\tabc123\tmodified\n.zprofile\tdef456\tmodified\n.config/shell/zprofile\tghi789\tmodified\n' \
		> "$HOME/.config-backup/nodes/$root_code/manifest.txt"

	rm -f "$HOME/.bashrc"

	run run_undeploy
	[ "$status" -eq 0 ]
	[[ "$output" == *"Undeploy Complete"* ]]
	assert_is_symlink ".zprofile"
	[ "$(readlink "$HOME/.zprofile")" = ".config/shell/zprofile" ]
}

@test "TC-U04: undeploy --dry-run makes no changes" {
	setup_node_with_repo

	run run_undeploy --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"dry-run"* ]]
}

# ── Deploy Status Tracking ─────────────────────────────────────────────

@test "TC-DS01: deploy sets status to deployed" {
	setup_node_with_repo
	cfg_deploy_status_set "uninstalled"

	run run_deploy --force
	[ "$status" -eq 0 ]
	[ "$(cfg_deploy_status_get)" = "deployed" ]
}

@test "TC-DS02: undeploy sets status to uninstalled" {
	setup_node_with_repo

	run run_undeploy --force
	[ "$status" -eq 0 ]
	[ "$(cfg_deploy_status_get)" = "uninstalled" ]
	assert_file_exists ".local/bin/dotcfg"
	assert_file_exists ".local/lib/dotfiles/cfg-validate.sh"
}
