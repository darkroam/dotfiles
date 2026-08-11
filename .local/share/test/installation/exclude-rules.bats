#!/usr/bin/env bats
# exclude-rules.bats - Fresh backup exclusion rule tests
# TC-E01 through TC-E09

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
	[ "$output" = "Path is excluded by hardcoded rule: ~/Downloads/" ]

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
	[ "$output" = "Path is NOT excluded." ]
}

# TC-E03: exclude.conf rules are honored

@test "TC-E03: exclude.conf rule excludes matching paths" {
	# Work on a private copy of the library so the real exclude.conf is untouched
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$HOME/dlib"
	printf '.config/private/*\n' > "$HOME/dlib/exclude.conf"

	run env DOTFILES_LIB_DIR="$HOME/dlib" bash "$HOME/dlib/commands/check-exclude.sh" ".config/private/secret"
	[ "$status" -eq 0 ]
	[ "$output" = "Path is excluded by exclude.conf: ~/.config/private/" ]
}

# TC-E04: absolute paths in exclude.conf are ignored

@test "TC-E04: absolute path in exclude.conf is ignored with warning" {
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$HOME/dlib"
	printf '/etc/passwd\n' > "$HOME/dlib/exclude.conf"

	run env DOTFILES_LIB_DIR="$HOME/dlib" bash "$HOME/dlib/commands/check-exclude.sh" "etc/passwd"
	[ "$status" -eq 1 ]
	assert_output_contains "NOT excluded"
}

@test "TC-E05: cfg_is_path_tracked checks repository HEAD" {
	create_mock_cfg_repo ".bashrc" ".local/bin/dotcfg"
	unset _CFG_EXCLUDE_LOADED
	. "$DOTFILES_ROOT/.local/lib/dotfiles/utils/exclude.sh"

	run cfg_is_path_tracked "$HOME/.bashrc" "$HOME/.cfg"
	[ "$status" -eq 0 ]

	run cfg_is_path_tracked "$HOME/.not-tracked" "$HOME/.cfg"
	[ "$status" -ne 0 ]
}

@test "TC-E06: emergency backup and mutable application state are excluded" {
	for path in \
		.config-backup.bak/.bashrc \
		.config/microsoft-edge/Cache/data \
		.config/nvm/cache/archive \
		.config/chromium/Default/History \
		.config/google-chrome-for-testing/Default/History; do
		run run_dotcfg check-exclude "$path"
		[ "$status" -eq 0 ]
		assert_output_contains "hardcoded"
	done
}

@test "TC-E07: missing exclude.conf uses the compatibility fallback" {
	local dlib="$HOME/dlib"
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$dlib"
	rm -f "$dlib/exclude.conf"

	run env DOTFILES_LIB_DIR="$dlib" bash "$dlib/commands/check-exclude.sh" "Downloads/file.pdf"
	[ "$status" -eq 0 ]
	[ "$output" = "Path is excluded by hardcoded rule: ~/Downloads/" ]

	run env DOTFILES_LIB_DIR="$dlib" bash "$dlib/commands/check-exclude.sh" \
		"Library/Application Support/app/state"
	[ "$status" -eq 0 ]
	assert_output_contains "hardcoded"
}

@test "TC-E08: compatibility and user rules keep distinct labels" {
	local dlib="$HOME/dlib"
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$dlib"
	cat > "$dlib/exclude.conf" <<'CONF'
# DOTCFG_COMPATIBILITY_RULES_BEGIN
.config/policy/*
# DOTCFG_COMPATIBILITY_RULES_END
.config/private/*
CONF

	run env DOTFILES_LIB_DIR="$dlib" bash "$dlib/commands/check-exclude.sh" \
		".config/policy/secret"
	[ "$status" -eq 0 ]
	[ "$output" = "Path is excluded by hardcoded rule: ~/.config/policy/" ]

	run env DOTFILES_LIB_DIR="$dlib" bash "$dlib/commands/check-exclude.sh" \
		".config/private/secret"
	[ "$status" -eq 0 ]
	[ "$output" = "Path is excluded by exclude.conf: ~/.config/private/" ]
}

@test "TC-E09: macOS user directories and Finder metadata are excluded" {
	local path
	for path in \
		Applications/App.app/Contents/Info.plist \
		"Library/Application Support/app/state" \
		Movies/recording.mov \
		Public/shared.txt \
		Sites/index.html \
		.Trash/deleted.txt \
		.config/app/.DS_Store; do
		run run_dotcfg check-exclude "$path"
		[ "$status" -eq 0 ]
		assert_output_contains "hardcoded"
	done

	unset _CFG_EXCLUDE_LOADED
	. "$DOTFILES_ROOT/.local/lib/dotfiles/utils/exclude.sh"
	fresh_exclude_invalidate
	_fresh_exclude_load_conf
	[ "${#_FRESH_EXCLUDE_COMPAT_PATTERNS[@]}" -eq 30 ]
	[ "${_FRESH_EXCLUDE_COMPAT_PATTERNS[*]}" = \
		"${_FRESH_EXCLUDE_POLICY_FALLBACK[*]}" ]

	create_mock_cfg_repo "Library/Preferences/example.plist"
	source_validate_lib
	unset _CFG_FILES_LOADED
	. "$DOTFILES_LIB_DIR/utils/files.sh"
	cfg_get_files_for_state "$HOME/.cfg" "full"
	[[ " ${CFG_TO_INSTALL[*]} " == *" Library/Preferences/example.plist "* ]]

	mkdir -p "$HOME/Library/Preferences"
	printf 'pre-install value\n' > "$HOME/Library/Preferences/example.plist"
	unset _CFG_FRESH_LOADED
	. "$DOTFILES_LIB_DIR/utils/fresh.sh"
	fresh_collect_backup_files "$HOME/.cfg"
	[[ " ${_FRESH_BACKUP_FILES[*]} " == *" Library/Preferences/example.plist "* ]]
}
