#!/usr/bin/env bash
# helpers.bash - Bats test helper functions for dotfiles install system
# Source this file in .bats files: load helpers.bash (or source it in setup)

# ── Safety ─────────────────────────────────────────────────────────────
# All test operations are confined to /tmp/ directories.
# REAL_HOME is saved once at load time and never modified.
REAL_HOME="${REAL_HOME:-$HOME}"

# ── Paths ──────────────────────────────────────────────────────────────
DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BATS_TEST_FILENAME:-}")/../../../.." && pwd)}"
VALIDATE_LIB="$DOTFILES_ROOT/.local/lib/dotfiles/cfg-validate.sh"
INSTALL_DESKTOP="$DOTFILES_ROOT/.local/bin/install-2.sh"
INSTALL_SERVER="$DOTFILES_ROOT/.local/bin/install-server.sh"
RESTORE_DESKTOP="$DOTFILES_ROOT/.local/bin/restore-desktop.sh"
RESTORE_SERVER="$DOTFILES_ROOT/.local/bin/restore-server.sh"
UNINSTALL="$DOTFILES_ROOT/.local/bin/uninstall.sh"
GENERATE_CONFLICTS="${BATS_TEST_FILENAME%/*}/generate-conflicts.sh"
DOTCFG="$DOTFILES_ROOT/.local/bin/dotcfg"

# ── Git mirror ─────────────────────────────────────────────────────────
GIT_MIRROR_DIR="/tmp/dotfiles-test-git-mirror"

setup_git_mirror() {
	if [ -d "$GIT_MIRROR_DIR/dotfiles.git" ]; then
		return 0
	fi
	mkdir -p "$GIT_MIRROR_DIR"
	if [ "${USE_REAL_REMOTE:-false}" = "true" ]; then
		git clone --bare git@github.com:darkroam/dotfiles.git "$GIT_MIRROR_DIR/dotfiles.git" 2>/dev/null
	else
		git --git-dir="$REAL_HOME/.cfg/" archive HEAD | \
			(cd "$(mktemp -d)" && git init >/dev/null 2>&1 && \
			 git config user.email "test@test.com" && \
			 git config user.name "Test" && \
			 git checkout -b master >/dev/null 2>&1 && \
			 git add -A && git commit -m "mirror" >/dev/null 2>&1 && \
			 git clone --bare . "$GIT_MIRROR_DIR/dotfiles.git" >/dev/null 2>&1) || \
			git init --bare "$GIT_MIRROR_DIR/dotfiles.git"
	fi
}

# ── Source repository for integration tests ────────────────────────────
# setup_source_repo [file1 file2 ...]
# Creates a bare git repo that install scripts can clone from via DOTFILES_REPOSITORY.
# Always includes .local/bin/install.sh as the repo signature for cfg_validate.
SOURCE_REPO_DIR=""
setup_source_repo() {
	if [ -n "$SOURCE_REPO_DIR" ] && [ -d "$SOURCE_REPO_DIR" ]; then
		return 0
	fi
	SOURCE_REPO_DIR=$(mktemp -d "/tmp/dotfiles-test-source-XXXXXX")
	local files=("$@")
	if [ ${#files[@]} -eq 0 ]; then
		files=(
			".bashrc" ".zshrc" ".profile" ".zprofile"
			".xinitrc" ".xprofile" ".asoundrc"
			".gitconfig" ".gitignore"
			".gtkrc-2.0"
			".tmux.conf"
			".config/shell/profile" ".config/shell/aliasrc"
			".config/shell/zshrc" ".config/shell/zprofile"
			".config/shell/inputrc"
			".config/x11/xinitrc" ".config/x11/xprofile" ".config/x11/xresources"
			".config/x11/picom.conf"
			".config/tmux/tmux.conf" ".config/tmux/tmux.conf.local"
			".config/git/gitconfig" ".config/git/ignore"
			".config/lf/lfrc" ".config/lf/scope" ".config/lf/cleaner" ".config/lf/icons"
			".config/alsa/asoundrc"
			".local/bin/install.sh"
			".local/bin/uninstall.sh"
			".local/share/docs/README.md"
			".local/share/docs/user/desktop-guide-zh.md"
			".local/lib/dotfiles/cfg-validate.sh"
		)
	fi
	local temp_work
	temp_work=$(mktemp -d "/tmp/dotfiles-test-work.XXXXXX")
	(cd "$temp_work" && {
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		for f in "${files[@]}"; do
			mkdir -p "$(dirname "$f")"
			echo "repo content for $f" > "$f"
		done
		git add -A
		git commit -m "source repo" >/dev/null 2>&1
	})
	git clone --bare "$temp_work" "$SOURCE_REPO_DIR" >/dev/null 2>&1
	rm -rf "$temp_work"
	export DOTFILES_REPOSITORY="$SOURCE_REPO_DIR"
}

teardown_source_repo() {
	if [ -n "$SOURCE_REPO_DIR" ] && [ -d "$SOURCE_REPO_DIR" ]; then
		rm -rf "$SOURCE_REPO_DIR"
	fi
	SOURCE_REPO_DIR=""
	unset DOTFILES_REPOSITORY
}

# create_valid_existing_cfg [file1 file2 ...]
# Creates a bare repo at $HOME/.cfg that passes cfg_validate (matching remote URL + signature).
create_valid_existing_cfg() {
	local files=("$@")
	if [ ${#files[@]} -eq 0 ]; then
		files=(".bashrc" ".gitconfig" ".local/bin/install.sh")
	fi
	local bare_dir="$HOME/.cfg"
	local temp_work
	temp_work=$(mktemp -d "/tmp/dotfiles-test-work.XXXXXX")
	git init --bare "$bare_dir" >/dev/null 2>&1
	(cd "$temp_work" && {
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		for f in "${files[@]}"; do
			mkdir -p "$(dirname "$f")"
			echo "old repo content for $f" > "$f"
		done
		git add -A
		git commit -m "existing cfg" >/dev/null 2>&1
		git remote add origin "$bare_dir"
		git push origin master >/dev/null 2>&1 || git push origin main >/dev/null 2>&1
	})
	rm -rf "$temp_work"
}

# setup_installed_state
# Simulates a completed install: clones source repo as .cfg, checks out all files,
# creates checkout state and configures git. Requires setup_source_repo to be called first.
setup_installed_state() {
	git clone --bare "$SOURCE_REPO_DIR" "$HOME/.cfg" >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" checkout HEAD -- . >/dev/null 2>&1
	git --git-dir="$HOME/.cfg/" --work-tree="$HOME" config status.showUntrackedFiles no
	local state_file="$HOME/.cfg-checkout-state"
	> "$state_file"
	while IFS= read -r path; do
		local hash
		hash=$(git --git-dir="$HOME/.cfg/" --work-tree="$HOME" show HEAD:"$path" | md5sum | cut -d' ' -f1)
		echo "$path:$hash" >> "$state_file"
	done < <(git --git-dir="$HOME/.cfg/" --work-tree="$HOME" ls-tree -r --name-only HEAD)
}

# ── Test environment setup/teardown ────────────────────────────────────
setup_test_home() {
	TEST_HOME=$(mktemp -d "/tmp/dotfiles-test-XXXXXX")
	export HOME="$TEST_HOME"
	export XDG_CONFIG_HOME="$TEST_HOME/.config"
	export XDG_DATA_HOME="$TEST_HOME/.local/share"
	export XDG_CACHE_HOME="$TEST_HOME/.cache"
	export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig-test"
	export GIT_CONFIG_SYSTEM=/dev/null
	touch "$GIT_CONFIG_GLOBAL"
	export DOTFILES_LIB_DIR="$REAL_HOME/.local/lib/dotfiles"
	export DOTCFG_BIN_DIR="$DOTFILES_ROOT/.local/bin"

	mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
}

teardown_test_home() {
	if [[ "${HOME:-}" == "$REAL_HOME" ]]; then
		echo "FATAL: refusing to remove REAL_HOME: $HOME" >&2
		return 1
	fi
	if [[ "${HOME:-}" == /tmp/dotfiles-test-* ]]; then
		rm -rf "$HOME"
	fi
	export HOME="$REAL_HOME"
	unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME
	unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
	unset DOTFILES_LIB_DIR DOTCFG_BIN_DIR
}

# ── Mock repository creation ───────────────────────────────────────────
# create_mock_cfg_repo [file1 file2 ...]
# Creates a bare git repo at $HOME/.cfg with the specified files committed.
create_mock_cfg_repo() {
	local files=("$@")
	local bare_dir="$HOME/.cfg"
	local temp_work
	temp_work=$(mktemp -d "/tmp/dotfiles-test-work.XXXXXX")

	git init --bare "$bare_dir" >/dev/null 2>&1

	(cd "$temp_work" && {
		git init >/dev/null 2>&1
		git config user.email "test@test.com"
		git config user.name "Test"
		for f in "${files[@]}"; do
			mkdir -p "$(dirname "$f")"
			echo "repo content for $f" > "$f"
		done
		git add -A
		git commit -m "initial" >/dev/null 2>&1
		git remote add origin "$bare_dir"
		git push origin master >/dev/null 2>&1 || git push origin main >/dev/null 2>&1
	})

	rm -rf "$temp_work"
}

# create_mock_cfg_repo_with_remote [remote_url] [file1 file2 ...]
# Creates a bare repo with a specific remote URL set.
create_mock_cfg_repo_with_remote() {
	local remote_url="$1"
	shift
	local files=("$@")
	create_mock_cfg_repo "${files[@]}"
	git --git-dir="$HOME/.cfg/" remote set-url origin "$remote_url" 2>/dev/null || \
		git --git-dir="$HOME/.cfg/" remote add origin "$remote_url" 2>/dev/null
}

# ── Source the shared validation library ───────────────────────────────
source_validate_lib() {
	unset _CFG_VALIDATE_LOADED
	unset CFG_STATE CFG_IS_OURS CFG_NEEDS_PULL CFG_REMOTE_URL
	if [ -f "$VALIDATE_LIB" ]; then
		. "$VALIDATE_LIB"
	else
		echo "WARNING: validate library not found at $VALIDATE_LIB" >&2
		return 1
	fi
}

# ── Script execution helpers ───────────────────────────────────────────
# run_install_desktop [args...]
run_install_desktop() {
	yes | bash "$INSTALL_DESKTOP" "$@" 2>&1
}

# run_install_server [args...]
run_install_server() {
	yes | bash "$INSTALL_SERVER" "$@" 2>&1
}

# run_restore_desktop [args...]
run_restore_desktop() {
	yes | bash "$RESTORE_DESKTOP" "$@" 2>&1
}

# run_restore_server [args...]
run_restore_server() {
	yes | bash "$RESTORE_SERVER" "$@" 2>&1
}

# run_uninstall [args...]
run_uninstall() {
	yes | yes | bash "$UNINSTALL" "$@" 2>&1
}

# run_dotcfg [args...]
run_dotcfg() {
	bash "$DOTCFG" "$@" 2>&1
}

# assert_output_contains <pattern>
# Checks that $output contains the given grep pattern
assert_output_contains() {
	local expected="$1"
	echo "$output" | grep -q "$expected" || {
		echo "expected output to contain: $expected" >&2
		echo "actual output: $output" >&2
		return 1
	}
}

# ── Backup session helpers ────────────────────────────────────────────
get_latest_backup_session() {
	find "$HOME/.config-backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1
}

get_earliest_backup_session() {
	find "$HOME/.config-backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1
}

# Search across ALL backup sessions for a file
assert_any_backup_contains() {
	local relative_path="$1"
	local found=false
	for session_dir in $(find "$HOME/.config-backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort); do
		if [ -e "$session_dir/$relative_path" ]; then
			found=true
			break
		fi
	done
	$found || {
		echo "expected any backup session to contain: $relative_path" >&2
		return 1
	}
}

# ── Assertion functions ────────────────────────────────────────────────
assert_file_exists() {
	local path="$1"
	[ -e "$HOME/$path" ] || [ -L "$HOME/$path" ] || {
		echo "expected file to exist: $path" >&2
		return 1
	}
}

assert_file_not_exists() {
	local path="$1"
	[ ! -e "$HOME/$path" ] && [ ! -L "$HOME/$path" ] || {
		echo "expected file to not exist: $path" >&2
		return 1
	}
}

assert_is_symlink() {
	local path="$1"
	[ -L "$HOME/$path" ] || {
		echo "expected symlink: $path" >&2
		return 1
	}
}

assert_is_regular_file() {
	local path="$1"
	[ -f "$HOME/$path" ] || {
		echo "expected regular file: $path" >&2
		return 1
	}
}

assert_file_contains() {
	local path="$1"
	local expected="$2"
	grep -q "$expected" "$HOME/$path" || {
		echo "expected $path to contain: $expected" >&2
		return 1
	}
}

assert_cfg_exists() {
	[ -d "$HOME/.cfg" ] || {
		echo "expected .cfg directory to exist" >&2
		return 1
	}
}

assert_cfg_not_exists() {
	[ ! -d "$HOME/.cfg" ] || {
		echo "expected .cfg directory to not exist" >&2
		return 1
	}
}

assert_backup_dir_exists() {
	[ -d "$HOME/.config-backup" ] || {
		echo "expected .config-backup directory to exist" >&2
		return 1
	}
	local count
	count=$(find "$HOME/.config-backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
	(( count > 0 )) || {
		echo "expected at least one backup session directory" >&2
		return 1
	}
}

assert_backup_count() {
	local expected="$1"
	local count
	if [ -d "$HOME/.config-backup" ]; then
		count=$(find "$HOME/.config-backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
	else
		count=0
	fi
	(( count == expected )) || {
		echo "expected $expected backup session dirs, found $count" >&2
		return 1
	}
}

assert_manifest_exists() {
	local backup_dir
	backup_dir=$(find "$HOME/.config-backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)
	[ -n "$backup_dir" ] && [ -f "$backup_dir/MANIFEST.txt" ] || {
		echo "expected MANIFEST.txt in latest backup session" >&2
		return 1
	}
}

assert_checkout_state_exists() {
	[ -f "$HOME/.cfg-checkout-state" ] || {
		echo "expected .cfg-checkout-state to exist" >&2
		return 1
	}
}

assert_checkout_state_not_exists() {
	[ ! -f "$HOME/.cfg-checkout-state" ] || {
		echo "expected .cfg-checkout-state to not exist" >&2
		return 1
	}
}

assert_show_untracked_no() {
	local val
	val=$(git --git-dir="$HOME/.cfg/" --work-tree="$HOME" config status.showUntrackedFiles 2>/dev/null || echo "")
	[ "$val" = "no" ] || {
		echo "expected status.showUntrackedFiles=no, got '$val'" >&2
		return 1
	}
}

# ── Backup naming validation (from old helpers.sh) ────────────────────
assert_backup_naming() {
	local backup_name="$1"
	local pattern='^(fresh|desktop|server)-to-(fresh|desktop|server)-[0-9]{8}T[0-9]{6}$'
	[[ "$backup_name" =~ $pattern ]] || {
		echo "backup name does not match convention: $backup_name" >&2
		return 1
	}
}

# ── File count helpers ────────────────────────────────────────────────
count_home_files() {
	find "$HOME" -maxdepth 4 -type f 2>/dev/null | wc -l
}

count_home_symlinks() {
	find "$HOME" -maxdepth 4 -type l 2>/dev/null | wc -l
}

# ── Additional assertions for integration tests ───────────────────────
assert_path_exists() {
	local path="$1"
	[ -e "$path" ] || [ -L "$path" ] || {
		echo "expected path to exist: $path" >&2
		return 1
	}
}

assert_backup_contains() {
	local relative_path="$1"
	local backup_dir
	backup_dir=$(find "$HOME/.config-backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)
	[ -n "$backup_dir" ] || {
		echo "no backup session directory found" >&2
		return 1
	}
	[ -e "$backup_dir/$relative_path" ] || {
		echo "expected backup to contain: $relative_path" >&2
		return 1
	}
}

assert_state_is() {
	local expected="$1"
	source_validate_lib
	local actual
	actual=$(cfg_detect_state "$HOME/.cfg")
	[ "$actual" = "$expected" ] || {
		echo "expected state '$expected', got '$actual'" >&2
		return 1
	}
}
