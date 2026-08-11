#!/usr/bin/env bats
# config-versions.bats - Unit tests for config version management
# TC-CV01 through TC-CV07

load helpers.bash

NODES_LIB="$DOTFILES_ROOT/.local/lib/dotfiles/utils/nodes.sh"
TEST_VERSION_FILES=()

setup() {
	setup_test_home
	local test_lib="$HOME/dotfiles-lib"
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$test_lib"
	rm -f -- "$test_lib"/categories-*.conf
	export DOTFILES_LIB_DIR="$test_lib"
	source_nodes_lib
	source_categories_lib
	TEST_VERSION_FILES=()
}

teardown() {
	for f in "${TEST_VERSION_FILES[@]}"; do
		rm -f "$f"
	done
	teardown_test_home
}

source_nodes_lib() {
	unset _CFG_NODES_LOADED
	unset CFG_NODES_DIR CFG_NODES_INDEX CFG_HEAD_FILE CFG_DEPLOY_STATUS_FILE
	unset _CFG_NODE_CODES _CFG_NODE_TYPES _CFG_NODE_TIMESTAMPS _CFG_NODE_PARENTS _CFG_NODE_CHILDREN
	unset _CFG_NODE_CONFIG_VERSIONS _CFG_NODE_STATUSES
	unset _CFG_NODE_INDEX_BY_CODE _CFG_NODES_INDEX_LOADED
	[ -f "$NODES_LIB" ] && . "$NODES_LIB"
}

# ── Helper: create version files ───────────────────────────────────────

create_version_file() {
	local version="$1"
	local name="${2:-}"
	local desc="${3:-}"
	local conf="$DOTFILES_LIB_DIR/categories-${version}.conf"
	{
		printf '# VERSION = %s\n' "$version"
		[ -n "$name" ] && printf '# NAME = %s\n' "$name"
		[ -n "$desc" ] && printf '# DESCRIPTION = %s\n' "$desc"
		printf '\n'
		printf 'category = macos\n'
		printf '+ .bashrc\n'
		printf '+ .zshrc\n'
		printf '\n'
		printf 'category = min\n'
		printf 'include = macos\n'
		printf '+ .custom.el\n'
	} > "$conf"
	TEST_VERSION_FILES+=("$conf")
	declare -F cfg_config_versions_invalidate >/dev/null && cfg_config_versions_invalidate
	declare -F cfg_categories_invalidate >/dev/null && cfg_categories_invalidate
}

# ── Version Discovery ──────────────────────────────────────────────────

@test "TC-CV01: cfg_config_version_list discovers version files" {
	local before after
	before=$(cfg_config_version_list | wc -l)

	create_version_file "99.0.0" "Initial"
	create_version_file "99.1.0" "Update"
	create_version_file "99.2.0" "Major"

	after=$(cfg_config_version_list | wc -l)
	[ "$after" -eq $((before + 3)) ]

	local versions
	versions=$(cfg_config_version_list)
	[[ "$versions" == *"99.0.0"* ]]
	[[ "$versions" == *"99.1.0"* ]]
	[[ "$versions" == *"99.2.0"* ]]
}

@test "TC-CV01b: cfg_config_version_list returns only existing files" {
	create_version_file "99.3.0" "Only Fixture"
	local versions
	versions=$(cfg_config_version_list)
	[ "$versions" = "99.3.0" ]
}

@test "TC-CV01c: cfg_config_version_list succeeds when no files exist" {
	run cfg_config_version_list
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ── Latest Version ─────────────────────────────────────────────────────

@test "TC-CV02: cfg_config_version_latest returns highest version" {
	create_version_file "99.0.0"
	create_version_file "99.1.0"
	create_version_file "99.2.0"

	local latest
	latest=$(cfg_config_version_latest)
	[ "$latest" = "99.2.0" ]
}

@test "TC-CV02b: cfg_config_version_latest sorts numerically" {
	create_version_file "98.0.0"
	create_version_file "98.9.0"
	create_version_file "98.10.0"

	local latest
	latest=$(cfg_config_version_latest)
	[ "$latest" = "98.10.0" ]
}

# ── Version Read ───────────────────────────────────────────────────────

@test "TC-CV03: cfg_config_version_read parses header metadata" {
	create_version_file "97.0.0" "My Config" "Initial configuration set"

	cfg_config_version_read "97.0.0" >/dev/null
	[ "$_CFG_CONF_VERSION" = "97.0.0" ]
	[ "$_CFG_CONF_NAME" = "My Config" ]
	[ "$_CFG_CONF_DESCRIPTION" = "Initial configuration set" ]

	local body
	body=$(cfg_config_version_read "97.0.0")
	[[ "$body" == *"category = macos"* ]]
	[[ "$body" == *".bashrc"* ]]
}

@test "TC-CV03b: cfg_config_version_read returns error for missing version" {
	run cfg_config_version_read "99.9.9"
	[ "$status" -ne 0 ]
}

# ── Categories Load with Version ───────────────────────────────────────

@test "TC-CV04: cfg_categories_load uses specified version" {
	create_version_file "96.0.0" "V1"

	cfg_categories_load "96.0.0"
	cfg_category_exists "macos"
	cfg_category_exists "min"

	local macos_files
	macos_files=$(cfg_category_get_files "macos")
	[[ "$macos_files" == *".bashrc"* ]]
	[[ "$macos_files" == *".zshrc"* ]]
}

@test "TC-CV04b: cfg_categories_load falls back to builtin for bad version" {
	cfg_categories_load "99.9.9" || true
	cfg_category_exists "macos"
	cfg_category_exists "min"
}

# ── Special Categories: full ───────────────────────────────────────────

@test "TC-CV05: full category returns all tracked files" {
	local bare_dir="$HOME/.cfg"
	local temp_work
	temp_work=$(mktemp -d "/tmp/dotfiles-test-work.XXXXXX")

	git init --bare "$bare_dir" >/dev/null 2>&1
	(cd "$temp_work" && {
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		mkdir -p .config/x11
		echo "content" > .bashrc
		echo "content" > .zshrc
		echo "content" > .xinitrc
		echo "content" > .config/x11/xresources
		git add -A
		git commit -m "test files" >/dev/null 2>&1
		git remote add origin "$bare_dir"
		git push origin master >/dev/null 2>&1 || git push origin main >/dev/null 2>&1
	})
	rm -rf "$temp_work"

	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- . >/dev/null 2>&1

	cfg_categories_load
	local full_files
	full_files=$(cfg_category_get_files "full")
	[[ "$full_files" == *".bashrc"* ]]
	[[ "$full_files" == *".zshrc"* ]]
	[[ "$full_files" == *".xinitrc"* ]]

	local count
	count=$(printf '%s\n' "$full_files" | wc -l)
	[ "$count" -eq 4 ]
}

# ── Reserved and ordinary category names ──────────────────────────────

@test "TC-CV06: only full is reserved; empty is an ordinary category name" {
	create_mock_cfg_repo ".tracked"
	local conf="$DOTFILES_LIB_DIR/categories-98.0.0.conf"
	cat > "$conf" <<'CONF'
# VERSION = "98.0.0"
# CATEGORY_ALIASES = "full:empty,everything:full"

category = full
+ .ignored-definition

category = empty
+ .ordinary-empty-name

category = desktop
+ .ordinary-desktop-name

category = server
+ .ordinary-server-name
CONF
	cfg_categories_load "98.0.0"
	[ "$(cfg_categories_list | grep -c '^full$')" -eq 1 ]
	! cfg_category_alias_target full
	[ "$(cfg_category_canonical_name full)" = "full" ]
	[ "$(cfg_category_get_files full "$HOME/.cfg")" = ".tracked" ]
	[ "$(cfg_category_canonical_name everything)" = "full" ]
	[ "$(cfg_category_get_files everything "$HOME/.cfg")" = ".tracked" ]
	cfg_category_exists empty
	[ "$(cfg_category_get_files empty)" = ".ordinary-empty-name" ]
	cfg_category_exists desktop
	[ "$(cfg_category_get_files desktop)" = ".ordinary-desktop-name" ]
	cfg_category_exists server
	[ "$(cfg_category_get_files server)" = ".ordinary-server-name" ]
}

# ── cfg_category_exists for the reserved full category ────────────────

@test "TC-CV07: cfg_category_exists reserves only full" {
	cfg_categories_load
	cfg_category_exists "full"
	! cfg_category_exists "empty"
	! cfg_category_exists "desktop"
	! cfg_category_exists "server"
	! cfg_category_exists "nonexistent"
}

@test "TC-CV07b: cfg_categories_list includes configured categories and full" {
	cfg_categories_load
	local list
	list=$(cfg_categories_list)
	[[ "$list" == *"macos"* ]]
	[[ "$list" == *"min"* ]]
	[[ "$list" == *"full"* ]]
	[[ "$list" != *"empty"* ]]
}

@test "TC-CV08: explicit invalidation refreshes version caches" {
	create_version_file "97.1.0" "Original Name"
	cfg_config_versions_load
	cfg_config_version_read "97.1.0" >/dev/null
	[ "$_CFG_CONF_NAME" = "Original Name" ]
	[ "$_CFG_CONFIG_VERSIONS_LOADED" = true ]
	[ ${#_CFG_CONFIG_BODY_CACHE[@]} -eq 1 ]

	sed -i 's/Original Name/Updated Name/' "$DOTFILES_LIB_DIR/categories-97.1.0.conf"
	cfg_config_versions_invalidate
	cfg_categories_invalidate
	cfg_config_versions_load
	cfg_config_version_read "97.1.0" >/dev/null

	[ "$_CFG_CONF_NAME" = "Updated Name" ]
	[[ "$(cfg_config_version_list)" == *"97.1.0"* ]]
}

@test "TC-CV09: optional metadata controls tags, aliases and state indicators" {
	local conf="$DOTFILES_LIB_DIR/categories-97.2.0.conf"
	cat > "$conf" <<'CONF'
# VERSION = "97.2.0"
# TAG = "qa"
# VALID_TAGS = "stable,qa"
# CATEGORY_ALIASES = "gui:graphical,cli:terminal"
# STATE_DEFAULT = "terminal"
# STATE_INDICATORS = "graphical:.custom-display"

category = graphical
+ .bashrc

category = terminal
+ .zshrc
CONF
	TEST_VERSION_FILES+=("$conf")
	cfg_config_versions_invalidate
	cfg_categories_invalidate

	cfg_categories_load "97.2.0"
	[ "$(cfg_config_get_tag 97.2.0)" = "qa" ]
	cfg_config_tag_is_valid qa
	[ "$(cfg_category_canonical_name gui)" = "graphical" ]
	[ "$(cfg_category_canonical_name cli)" = "terminal" ]
	[ "$(cfg_state_default_category)" = "terminal" ]
	[ "$(cfg_state_indicator_category .custom-display)" = "graphical" ]
}
