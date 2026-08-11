#!/usr/bin/env bats
# categories.bats - Unit tests for utils/categories.sh
# TC-C01 through TC-C16

load helpers.bash

setup() {
	setup_test_home
	local test_lib="$HOME/dotfiles-lib"
	mkdir -p "$test_lib/utils"
	cp "$REAL_HOME/.local/lib/dotfiles/utils/categories.sh" "$test_lib/utils/categories.sh"
	export DOTFILES_LIB_DIR="$test_lib"
	source_categories_lib
}

teardown() {
	teardown_test_home
}

# TC-C01: Built-in defaults load correctly without categories.conf

@test "TC-C01: built-in defaults load without categories.conf" {
	cfg_categories_load
	cfg_category_exists "macos"
	cfg_category_exists "min"
	cfg_category_exists "full"
	! cfg_category_exists "server"
	! cfg_category_exists "desktop"
	! cfg_category_exists "empty"
}

# TC-C02: macos category returns the maintained baseline

@test "TC-C02: macos category has 17 files" {
	cfg_categories_load
	local count
	count=$(cfg_category_get_files "macos" | wc -l)
	[ "$count" -eq 17 ]
}

# TC-C03: min includes macos plus Linux command-line files

@test "TC-C03: min includes macos + command-line files" {
	cfg_categories_load
	local min_files
	min_files=$(cfg_category_get_files "min")
	printf '%s\n' "$min_files" | grep -qFx ".bashrc"
	printf '%s\n' "$min_files" | grep -qFx ".custom.el"
	printf '%s\n' "$min_files" | grep -qFx ".config/lf/lfrc"
	! printf '%s\n' "$min_files" | grep -qE '^\.config/(mpd|ncmpcpp|newsboat)/'
	local count
	count=$(printf '%s\n' "$min_files" | wc -l)
	[ "$count" -eq 24 ]
}

# TC-C04: cfg_category_exists works correctly

@test "TC-C04: cfg_category_exists returns correct results" {
	cfg_categories_load
	cfg_category_exists "macos"
	cfg_category_exists "min"
	! cfg_category_exists "server"
	! cfg_category_exists "desktop"
	! cfg_category_exists "empty"
	! cfg_category_exists "nonexistent"
}

# TC-C05: Custom categories.conf overrides built-in

@test "TC-C05: custom categories.conf overrides built-in" {
	local conf="$DOTFILES_LIB_DIR/categories.conf"
	cat > "$conf" <<'CONF'
category = minimal
+ .bashrc
+ .zshrc
CONF
	cfg_categories_load
	cfg_category_exists "minimal"
	! cfg_category_exists "macos"
	local count
	count=$(cfg_category_get_files "minimal" | wc -l)
	[ "$count" -eq 2 ]
	rm -f "$conf"
}

# TC-C06: Corrupted categories.conf falls back to built-in

@test "TC-C06: corrupted categories.conf falls back to built-in" {
	local conf="$DOTFILES_LIB_DIR/categories.conf"
	printf 'this is not valid config\n' > "$conf"
	cfg_categories_load
	cfg_category_exists "macos"
	rm -f "$conf"
}

# TC-C07: Circular include detection

@test "TC-C07: circular include is detected" {
	local conf="$DOTFILES_LIB_DIR/categories.conf"
	cat > "$conf" <<'CONF'
category = alpha
include = beta
+ .bashrc

category = beta
include = alpha
+ .zshrc
CONF
	local stderr
	cfg_categories_load 2>/dev/null
	stderr=$(cfg_category_get_files "alpha" 2>&1 >/dev/null) || true
	[[ "$stderr" == *"circular"* ]]
	rm -f "$conf"
}

# TC-C08: Out-of-order lines are silently ignored

@test "TC-C08: out-of-order lines are ignored" {
	local conf="$DOTFILES_LIB_DIR/categories.conf"
	cat > "$conf" <<'CONF'
category = test
- .bashrc
+ .zshrc
include = macos
CONF
	cfg_categories_load
	local files
	files=$(cfg_category_get_files "test")
	printf '%s\n' "$files" | grep -qFx ".zshrc"
	! printf '%s\n' "$files" | grep -qFx ".bashrc"
	rm -f "$conf"
}

# TC-C09: Directory expansion for existing directories

@test "TC-C09: directory path preserved in category" {
	local conf="$DOTFILES_LIB_DIR/categories.conf"
	mkdir -p "$HOME/.config/x11"
	touch "$HOME/.config/x11/xinitrc"
	touch "$HOME/.config/x11/xresources"
	cat > "$conf" <<'CONF'
category = paths
+ .config/x11
CONF
	cfg_categories_load
	local files
	files=$(cfg_category_get_files "paths")
	printf '%s\n' "$files" | grep -qFx ".config/x11"
}

# TC-C10: Non-existent directory preserves original path

@test "TC-C10: non-existent directory preserves path" {
	local conf="$DOTFILES_LIB_DIR/categories.conf"
	cat > "$conf" <<'CONF'
category = paths
+ .config/x11
CONF
	cfg_categories_load
	local files
	files=$(cfg_category_get_files "paths")
	printf '%s\n' "$files" | grep -qFx ".config/x11"
}

# TC-C11: Subtraction (-) removes files

@test "TC-C11: subtraction removes files" {
	local conf="$DOTFILES_LIB_DIR/categories.conf"
	cat > "$conf" <<'CONF'
category = base
+ .bashrc
+ .zshrc
+ .profile

category = trimmed
include = base
- .profile
CONF
	cfg_categories_load
	local files
	files=$(cfg_category_get_files "trimmed")
	printf '%s\n' "$files" | grep -qFx ".bashrc"
	printf '%s\n' "$files" | grep -qFx ".zshrc"
	! printf '%s\n' "$files" | grep -qFx ".profile"
	rm -f "$conf"
}

# TC-C12: cfg_exclude_match glob matching

@test "TC-C12: cfg_exclude_match matches globs" {
	cfg_categories_load
	cfg_exclude_match ".local/lib/dotfiles/cfg-validate.sh"
	cfg_exclude_match ".cfg/something"
	! cfg_exclude_match ".bashrc"
}

# TC-C13: Built-in exclude protects dotfiles library

@test "TC-C13: built-in exclude protects dotfiles library" {
	cfg_categories_load
	cfg_exclude_match ".local/lib/dotfiles/utils/files.sh"
	cfg_exclude_match ".config-backup/nodes/abc/backup/file"
	cfg_exclude_match ".cfg-checkout-state"
}

# TC-C14: cfg_categories_list returns category names

@test "TC-C14: cfg_categories_list returns names" {
	cfg_categories_load
	local names
	names=$(cfg_categories_list)
	printf '%s\n' "$names" | grep -qFx "macos"
	printf '%s\n' "$names" | grep -qFx "min"
	printf '%s\n' "$names" | grep -qFx "full"
}

# TC-C15: cfg_category_diff computes difference

@test "TC-C15: cfg_category_diff computes diff" {
	cfg_categories_load
	local diff
	diff=$(cfg_category_diff "macos" "min")
	printf '%s\n' "$diff" | grep -qFx ".custom.el"
	printf '%s\n' "$diff" | grep -qFx ".config/lf/lfrc"
	! printf '%s\n' "$diff" | grep -qFx ".bashrc"
	local count
	count=$(printf '%s\n' "$diff" | wc -l)
	[ "$count" -eq 7 ]
}

# TC-C16: The emergency fallback must stay identical to the stable definition.

@test "TC-C16: built-in fallback matches categories-1.0.0.conf" {
	cfg_categories_load
	local fallback_names fallback_macos fallback_min
	fallback_names=$(cfg_categories_list)
	fallback_macos=$(cfg_category_get_files "macos")
	fallback_min=$(cfg_category_get_files "min")

	cp "$REAL_HOME/.local/lib/dotfiles/categories-1.0.0.conf" \
		"$DOTFILES_LIB_DIR/categories-1.0.0.conf"
	cfg_categories_invalidate
	cfg_categories_load "1.0.0"

	[ "$(cfg_categories_list)" = "$fallback_names" ]
	[ "$(cfg_category_get_files "macos")" = "$fallback_macos" ]
	[ "$(cfg_category_get_files "min")" = "$fallback_min" ]
}
