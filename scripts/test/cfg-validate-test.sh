#!/usr/bin/env bash
# cfg-validate-test.sh - Unit tests for cfg-validate.sh
# Tests all validation scenarios for the .cfg repository
#
# ── 安全约束 ─────────────────────────────────────────────────────────
# 1. 禁止删除 $REAL_HOME/.cfg 或 $REAL_HOME 下的任何内容。
# 2. 禁止在 $REAL_HOME 根目录创建或修改文件。
# 3. 所有写操作（rm -rf、git init、文件创建）仅限 /tmp/ 下的临时测试目录。
# 4. cleanup 函数必须校验目标路径以 /tmp/ 开头且不等于 $REAL_HOME。
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VALIDATE_LIB="$SCRIPT_DIR/../../.local/share/dotfiles-lib/cfg-validate.sh"

if [ ! -f "$VALIDATE_LIB" ]; then
	printf 'ERROR: Cannot find validation library at %s\n' "$VALIDATE_LIB" >&2
	exit 1
fi

total=0
passed=0
failed=0
failed_tests=()

pass() {
	((passed++)) || true
	((total++)) || true
	printf '  PASS: %s\n' "$1"
}

fail() {
	((failed++)) || true
	((total++)) || true
	printf '  FAIL: %s\n' "$1" >&2
	failed_tests+=("$1")
}

# Save the real HOME before any test overrides it
REAL_HOME="${REAL_HOME:-$HOME}"

# Create a temporary HOME for each test
setup_test_home() {
	local test_name="$1"
	local test_home
	test_home=$(mktemp -d "/tmp/cfg-validate-test-${test_name}.XXXXXX")
	export HOME="$test_home"

	# Isolate XDG and git config from the real environment
	export XDG_CONFIG_HOME="$test_home/.config"
	export XDG_DATA_HOME="$test_home/.local/share"
	export XDG_CACHE_HOME="$test_home/.cache"
	export GIT_CONFIG_GLOBAL="$test_home/.gitconfig"
	export GIT_CONFIG_SYSTEM=/dev/null

	# Point to the real shared library so tests exercise it, not the inline fallback
	export DOTFILES_LIB_DIR="$REAL_HOME/.local/share/dotfiles-lib"

	# Reset the loaded flag so the library can be re-sourced
	unset _CFG_VALIDATE_LOADED
	unset CFG_STATE CFG_IS_OURS CFG_NEEDS_PULL CFG_REMOTE_URL
}

cleanup_test_home() {
	if [[ "${HOME:-}" == "$REAL_HOME" ]]; then
		printf 'FATAL: refusing to remove REAL_HOME: %s\n' "$HOME" >&2
		exit 1
	elif [[ "${HOME:-}" == /tmp/cfg-validate-test-* ]]; then
		rm -rf "$HOME"
	else
		printf 'WARNING: refusing to remove non-test HOME: %s\n' "$HOME" >&2
	fi
}

# Create a bare git repo with a commit containing a specific file tree
create_bare_repo_with_content() {
	local bare_dir="$1"
	shift
	local files=("$@")

	git init --bare "$bare_dir" >/dev/null 2>&1

	local temp_work
	temp_work=$(mktemp -d "/tmp/cfg-validate-work.XXXXXX")

	(cd "$temp_work" && {
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		for f in "${files[@]}"; do
			mkdir -p "$(dirname "$f")"
			printf 'content of %s\n' "$f" > "$f"
		done
		git add -A
		git commit -m "initial" >/dev/null 2>&1
		git remote add origin "$bare_dir"
		git push origin master >/dev/null 2>&1 || git push origin main >/dev/null 2>&1
	})

	rm -rf "$temp_work"
}

# ── Test cases ──────────────────────────────────────────────────────────

test_missing() {
	printf '\n[Test] No .cfg directory → missing\n'
	setup_test_home "missing"

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "missing" ]; then
		pass "CFG_STATE is 'missing'"
	else
		fail "CFG_STATE expected 'missing', got '$CFG_STATE'"
	fi
	if [ "$CFG_IS_OURS" = "false" ]; then
		pass "CFG_IS_OURS is 'false'"
	else
		fail "CFG_IS_OURS expected 'false', got '$CFG_IS_OURS'"
	fi

	cleanup_test_home
}

test_regular_file() {
	printf '\n[Test] .cfg is a regular file → not_git\n'
	setup_test_home "regular-file"
	touch "$HOME/.cfg"

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "not_git" ]; then
		pass "CFG_STATE is 'not_git'"
	else
		fail "CFG_STATE expected 'not_git', got '$CFG_STATE'"
	fi

	cleanup_test_home
}

test_empty_directory() {
	printf '\n[Test] .cfg is an empty directory → not_git\n'
	setup_test_home "empty-dir"
	mkdir -p "$HOME/.cfg"

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "not_git" ]; then
		pass "CFG_STATE is 'not_git'"
	else
		fail "CFG_STATE expected 'not_git', got '$CFG_STATE'"
	fi

	cleanup_test_home
}

test_non_bare_repo() {
	printf '\n[Test] .cfg is a non-bare git repo → not_git\n'
	setup_test_home "non-bare"
	mkdir -p "$HOME/.cfg"
	(cd "$HOME/.cfg" && git init >/dev/null 2>&1)

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "not_git" ]; then
		pass "CFG_STATE is 'not_git'"
	else
		fail "CFG_STATE expected 'not_git', got '$CFG_STATE'"
	fi

	cleanup_test_home
}

test_bare_no_remote_no_signature() {
	printf '\n[Test] Bare repo, no remote, no signature → foreign_repo\n'
	setup_test_home "bare-empty"
	git init --bare "$HOME/.cfg" >/dev/null 2>&1

	# Need at least one commit for HEAD to be valid
	local temp_work
	temp_work=$(mktemp -d "/tmp/cfg-validate-work.XXXXXX")
	(cd "$temp_work" && {
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		printf 'hello\n' > readme.txt
		git add -A
		git commit -m "initial" >/dev/null 2>&1
		git remote add origin "$HOME/.cfg"
		git push origin master >/dev/null 2>&1 || git push origin main >/dev/null 2>&1
	})
	rm -rf "$temp_work"

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "foreign_repo" ]; then
		pass "CFG_STATE is 'foreign_repo'"
	else
		fail "CFG_STATE expected 'foreign_repo', got '$CFG_STATE'"
	fi
	if [ "$CFG_IS_OURS" = "false" ]; then
		pass "CFG_IS_OURS is 'false'"
	else
		fail "CFG_IS_OURS expected 'false', got '$CFG_IS_OURS'"
	fi

	cleanup_test_home
}

test_bare_correct_remote() {
	printf '\n[Test] Bare repo with correct remote URL → valid\n'
	setup_test_home "correct-remote"
	git init --bare "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" remote add origin "git@github.com:darkroam/dotfiles.git"

	# Push some content
	local temp_work
	temp_work=$(mktemp -d "/tmp/cfg-validate-work.XXXXXX")
	(cd "$temp_work" && {
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		mkdir -p .local/bin
		printf '#!/bin/bash\n' > .local/bin/install.sh
		git add -A
		git commit -m "initial" >/dev/null 2>&1
		git remote add origin "$HOME/.cfg"
		git push origin master >/dev/null 2>&1 || git push origin main >/dev/null 2>&1
	})
	rm -rf "$temp_work"

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "valid" ]; then
		pass "CFG_STATE is 'valid'"
	else
		fail "CFG_STATE expected 'valid', got '$CFG_STATE'"
	fi
	if [ "$CFG_IS_OURS" = "true" ]; then
		pass "CFG_IS_OURS is 'true'"
	else
		fail "CFG_IS_OURS expected 'true', got '$CFG_IS_OURS'"
	fi

	cleanup_test_home
}

test_bare_signature_no_remote() {
	printf '\n[Test] Bare repo with signature file but no remote → valid\n'
	setup_test_home "signature-no-remote"

	create_bare_repo_with_content "$HOME/.cfg" ".local/bin/install.sh" ".bashrc"

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "valid" ]; then
		pass "CFG_STATE is 'valid'"
	else
		fail "CFG_STATE expected 'valid', got '$CFG_STATE'"
	fi
	if [ "$CFG_IS_OURS" = "true" ]; then
		pass "CFG_IS_OURS is 'true'"
	else
		fail "CFG_IS_OURS expected 'true', got '$CFG_IS_OURS'"
	fi

	cleanup_test_home
}

test_symlink_to_valid() {
	printf '\n[Test] .cfg is a symlink to valid bare repo → valid\n'
	setup_test_home "symlink-valid"

	local real_dir="$HOME/real-cfg"
	create_bare_repo_with_content "$real_dir" ".local/bin/install.sh" ".bashrc"

	ln -s "$real_dir" "$HOME/.cfg"

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "valid" ]; then
		pass "CFG_STATE is 'valid'"
	else
		fail "CFG_STATE expected 'valid', got '$CFG_STATE'"
	fi
	if [ "$CFG_IS_OURS" = "true" ]; then
		pass "CFG_IS_OURS is 'true'"
	else
		fail "CFG_IS_OURS expected 'true', got '$CFG_IS_OURS'"
	fi

	cleanup_test_home
}

test_broken_symlink() {
	printf '\n[Test] .cfg is a broken symlink → not_git\n'
	setup_test_home "broken-symlink"
	ln -s /nonexistent/path "$HOME/.cfg"

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "not_git" ]; then
		pass "CFG_STATE is 'not_git'"
	else
		fail "CFG_STATE expected 'not_git', got '$CFG_STATE'"
	fi

	cleanup_test_home
}

test_wrong_remote_url() {
	printf '\n[Test] Bare repo with wrong remote URL → foreign_repo\n'
	setup_test_home "wrong-remote"
	git init --bare "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" remote add origin "git@github.com:someone/else.git"

	# Push some content
	local temp_work
	temp_work=$(mktemp -d "/tmp/cfg-validate-work.XXXXXX")
	(cd "$temp_work" && {
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		printf 'hello\n' > readme.txt
		git add -A
		git commit -m "initial" >/dev/null 2>&1
		git remote add origin "$HOME/.cfg"
		git push origin master >/dev/null 2>&1 || git push origin main >/dev/null 2>&1
	})
	rm -rf "$temp_work"

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "foreign_repo" ]; then
		pass "CFG_STATE is 'foreign_repo'"
	else
		fail "CFG_STATE expected 'foreign_repo', got '$CFG_STATE'"
	fi
	if [ "$CFG_IS_OURS" = "false" ]; then
		pass "CFG_IS_OURS is 'false'"
	else
		fail "CFG_IS_OURS expected 'false', got '$CFG_IS_OURS'"
	fi

	cleanup_test_home
}

test_https_url_normalized() {
	printf '\n[Test] HTTPS remote URL normalized to match SSH → valid\n'
	setup_test_home "https-normalize"
	git init --bare "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" remote add origin "https://github.com/darkroam/dotfiles.git"

	# Push some content
	local temp_work
	temp_work=$(mktemp -d "/tmp/cfg-validate-work.XXXXXX")
	(cd "$temp_work" && {
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		printf 'hello\n' > readme.txt
		git add -A
		git commit -m "initial" >/dev/null 2>&1
		git remote add origin "$HOME/.cfg"
		git push origin master >/dev/null 2>&1 || git push origin main >/dev/null 2>&1
	})
	rm -rf "$temp_work"

	. "$VALIDATE_LIB"
	cfg_validate "$HOME/.cfg"

	if [ "$CFG_STATE" = "valid" ]; then
		pass "CFG_STATE is 'valid' (HTTPS URL recognized)"
	else
		fail "CFG_STATE expected 'valid', got '$CFG_STATE'"
	fi

	cleanup_test_home
}

# ── Run all tests ───────────────────────────────────────────────────────

printf '=== cfg-validate.sh Unit Tests ===\n'

test_missing
test_regular_file
test_empty_directory
test_non_bare_repo
test_bare_no_remote_no_signature
test_bare_correct_remote
test_bare_signature_no_remote
test_symlink_to_valid
test_broken_symlink
test_wrong_remote_url
test_https_url_normalized

printf '\n=== Results ===\n'
printf 'Total: %d  Passed: %d  Failed: %d\n' "$total" "$passed" "$failed"

if ((${#failed_tests[@]} > 0)); then
	printf '\nFailed tests:\n'
	for t in "${failed_tests[@]}"; do
		printf '  - %s\n' "$t"
	done
	exit 1
fi

printf '\nAll tests passed.\n'
exit 0
