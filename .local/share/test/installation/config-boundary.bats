#!/usr/bin/env bats
# config-boundary.bats - Configuration-driven and fixed-semantics boundaries
# TC-CB01 through TC-CB05

load helpers.bash

setup() {
	setup_test_home
	local test_lib="$HOME/dotfiles-lib"
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$test_lib"
	rm -f -- "$test_lib"/categories-*.conf "$test_lib/categories.conf"
	export DOTFILES_LIB_DIR="$test_lib"
	unset _CFG_COMMON_LOADED _CFG_CATEGORIES_LOADED _CFG_FILES_LOADED
	. "$DOTFILES_LIB_DIR/utils/common.sh"
}

teardown() {
	teardown_test_home
}

write_custom_config() {
	cat > "$DOTFILES_LIB_DIR/categories.conf"
	cfg_categories_invalidate
}

@test "TC-CB01: available configuration defines ordinary categories" {
	write_custom_config <<'CONF'
category = workstation
+ .workstationrc
CONF

	cfg_categories_load
	cfg_category_exists workstation
	[ "$(cfg_category_get_files workstation)" = ".workstationrc" ]
	! cfg_category_exists min
}

@test "TC-CB02: missing configuration falls back to built-in categories" {
	cfg_categories_load
	cfg_category_exists macos
	cfg_category_exists min
	cfg_category_exists full
	[ "$(cfg_category_get_files macos | wc -l)" -eq 17 ]
	[ "$(cfg_category_get_files min | wc -l)" -eq 24 ]
}

@test "TC-CB03: full dynamically returns every tracked file" {
	create_mock_cfg_repo ".tracked-one" ".config/app/tracked-two" ".local/bin/dotcfg"
	cfg_categories_load

	local files
	files=$(cfg_category_get_files full "$HOME/.cfg")
	printf '%s\n' "$files" | grep -qFx ".tracked-one"
	printf '%s\n' "$files" | grep -qFx ".config/app/tracked-two"
	printf '%s\n' "$files" | grep -qFx ".local/bin/dotcfg"
}

@test "TC-CB04: configuration cannot override or remove full" {
	create_mock_cfg_repo ".tracked"
	write_custom_config <<'CONF'
category = full
+ .configured-but-ignored

category = tiny
+ .tinyrc
CONF
	cfg_categories_load

	[ "$(cfg_categories_list | grep -c '^full$')" -eq 1 ]
	[ "$(cfg_category_get_files full "$HOME/.cfg")" = ".tracked" ]
}

@test "TC-CB05: installation infrastructure is invariant across categories" {
	create_mock_cfg_repo ".bashrc" ".other" ".local/bin/dotcfg" \
		".local/lib/dotfiles/cfg-validate.sh"
	write_custom_config <<'CONF'
category = tiny
+ .bashrc
CONF
	cfg_categories_load

	local selected removed
	selected=$(cfg_get_tracked_files_for_state "$HOME/.cfg" tiny)
	printf '%s\n' "$selected" | grep -qFx ".bashrc"
	printf '%s\n' "$selected" | grep -qFx ".local/bin/dotcfg"
	printf '%s\n' "$selected" | grep -qFx ".local/lib/dotfiles/cfg-validate.sh"

	removed=$(cfg_get_files_to_remove "$HOME/.cfg" full tiny)
	printf '%s\n' "$removed" | grep -qFx ".other"
	! printf '%s\n' "$removed" | grep -qF ".local/bin/dotcfg"
	! printf '%s\n' "$removed" | grep -qF ".local/lib/dotfiles/"
}
