#!/usr/bin/env bats
# detect-state.bats - Unit tests for cfg_detect_state() in cfg-validate.sh
# TC-01, TC-02, TC-03

load helpers.bash

setup() {
	setup_test_home
	source_validate_lib
}

teardown() {
	teardown_test_home
}

# TC-01: $HOME/.cfg does not exist → fresh

@test "TC-01: no .cfg → fresh" {
	local state
	state=$(cfg_detect_state "$HOME/.cfg")
	[ "$state" = "fresh" ]
}

# TC-02: .cfg exists + graphical indicators → full

@test "TC-02a: .cfg + .xinitrc → full" {
	create_mock_cfg_repo ".bashrc"
	touch "$HOME/.xinitrc"
	local state
	state=$(cfg_detect_state "$HOME/.cfg")
	[ "$state" = "full" ]
}

@test "TC-02b: .cfg + .xprofile → full" {
	create_mock_cfg_repo ".bashrc"
	touch "$HOME/.xprofile"
	local state
	state=$(cfg_detect_state "$HOME/.cfg")
	[ "$state" = "full" ]
}

@test "TC-02c: .cfg + .config/x11/xinitrc → full" {
	create_mock_cfg_repo ".bashrc"
	mkdir -p "$HOME/.config/x11"
	touch "$HOME/.config/x11/xinitrc"
	local state
	state=$(cfg_detect_state "$HOME/.cfg")
	[ "$state" = "full" ]
}

@test "TC-02d: .cfg + .xinitrc as symlink → full" {
	create_mock_cfg_repo ".bashrc"
	ln -s /dev/null "$HOME/.xinitrc"
	local state
	state=$(cfg_detect_state "$HOME/.cfg")
	[ "$state" = "full" ]
}

# TC-03: .cfg exists, no graphical indicators → min

@test "TC-03a: .cfg only, no indicators → min" {
	create_mock_cfg_repo ".bashrc"
	local state
	state=$(cfg_detect_state "$HOME/.cfg")
	[ "$state" = "min" ]
}

@test "TC-03b: .cfg + random files but no graphical indicators → min" {
	create_mock_cfg_repo ".bashrc" ".gitconfig"
	touch "$HOME/.tmux.conf"
	mkdir -p "$HOME/.config/lf"
	echo "test" > "$HOME/.config/lf/lfrc"
	local state
	state=$(cfg_detect_state "$HOME/.cfg")
	[ "$state" = "min" ]
}

@test "TC-03c: empty .config/x11 directory is not a full indicator" {
	create_mock_cfg_repo ".bashrc"
	mkdir -p "$HOME/.config/x11"
	local state
	state=$(cfg_detect_state "$HOME/.cfg")
	[ "$state" = "min" ]
}

@test "TC-03d: macos HEAD metadata overrides graphical compatibility indicators" {
	create_mock_cfg_repo ".bashrc"
	mkdir -p "$HOME/.config/x11"
	touch "$HOME/.config/x11/xinitrc"

	unset _CFG_NODES_LOADED
	. "$DOTFILES_LIB_DIR/utils/nodes.sh"
	cfg_nodes_init "$HOME/.config-backup"
	local root_code macos_code state
	root_code=$(cfg_node_create "fresh" "null" "1.0.0")
	macos_code=$(cfg_node_create "macos" "$root_code" "1.0.0")
	cfg_head_set "$macos_code"

	state=$(cfg_detect_state "$HOME/.cfg")
	[ "$state" = "macos" ]
}
