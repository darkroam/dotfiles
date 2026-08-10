#!/usr/bin/env bash
# commands/bootstrap-lib.sh - Post-clone installation steps for bootstrap mode
# Sourced by dotcfg's _bootstrap_install after cloning the repository and
# extracting the library files. Not a standalone command script.
#
# Expects: GIT_DIR, BACKUP_ROOT, DOTFILES_LIB_DIR exported by the caller;
#          cfg-validate.sh already sourced by the caller.

bootstrap_finish_install() {
	. "$DOTFILES_LIB_DIR/utils/args.sh"
	. "$DOTFILES_LIB_DIR/utils/backup.sh"
	. "$DOTFILES_LIB_DIR/utils/rollback.sh"
	. "$DOTFILES_LIB_DIR/utils/checkout.sh"
	. "$DOTFILES_LIB_DIR/utils/repo.sh"
	. "$DOTFILES_LIB_DIR/utils/categories.sh"
	. "$DOTFILES_LIB_DIR/utils/files.sh"
	. "$DOTFILES_LIB_DIR/utils/nodes.sh"
	. "$DOTFILES_LIB_DIR/utils/exclude.sh"
	. "$DOTFILES_LIB_DIR/utils/fresh.sh"

	cfg_nodes_init "$BACKUP_ROOT"

	# Step 3: create the fresh root node from the mixed-mode backup set.
	printf '\n=== Creating fresh root node (mixed-mode backup) ===\n'
	fresh_create_root_backup || {
		printf 'WARNING: fresh root backup failed, continuing\n' >&2
	}

	local root_code
	root_code=$(fresh_get_root_code 2>/dev/null) || root_code=""
	if [ -z "$root_code" ]; then
		root_code=$(cfg_node_create "fresh" "null" "${FRESH_BOOTSTRAP_VERSION:-bootstrap}" "${FRESH_ROOT_CODE:-fresh_root}") || return 1
		cfg_nodes_invalidate
	fi
	cfg_head_set "$root_code"
	cfg_deploy_status_set "deployed"
	printf '%s\n' "${FRESH_BOOTSTRAP_VERSION:-bootstrap}" > "$BACKUP_ROOT/CURRENT_CONFIG_VERSION"

	# ── Step 4: checkout configuration files ──────────────────────────
	printf '\n=== Checking out configuration files ===\n'
	local selected_version=""
	selected_version=$(cfg_config_version_latest 2>/dev/null) || selected_version=""
	if [ -n "$selected_version" ]; then
		cfg_categories_load "$selected_version"
	else
		cfg_categories_load
	fi

	local files=()
	local f
	if cfg_category_exists "min" 2>/dev/null; then
		while IFS= read -r f; do
			[ -n "$f" ] && files+=("$f")
		done < <(cfg_get_tracked_files_for_state "$GIT_DIR" "min" "$selected_version" 2>/dev/null)
	else
		while IFS= read -r f; do
			[ -n "$f" ] && files+=("$f")
		done < <(git --git-dir="$GIT_DIR/" --work-tree="$HOME" ls-tree -r --name-only HEAD 2>/dev/null)
	fi

	# Back up conflicting files before overwriting
	local conflict_dir="$BACKUP_ROOT/conflict"
	local conflict_count=0
	local md5_repo md5_local
	for f in "${files[@]}"; do
		[ -f "$HOME/$f" ] || [ -L "$HOME/$f" ] || continue
		md5_repo=$(git --git-dir="$GIT_DIR/" cat-file blob "HEAD:$f" 2>/dev/null | md5sum | cut -d' ' -f1) || md5_repo=""
		md5_local=$(cfg_path_md5 "$HOME/$f" 2>/dev/null) || md5_local=""
		if [ -n "$md5_repo" ] && [ "$md5_repo" != "$md5_local" ]; then
			mkdir -p -- "$conflict_dir/$(dirname "$f")"
			cp -a -- "$HOME/$f" "$conflict_dir/$f"
			conflict_count=$((conflict_count + 1))
		fi
	done
	if [ "$conflict_count" -gt 0 ]; then
		printf '%d conflicting file(s) backed up to %s/\n' "$conflict_count" "$conflict_dir"
	fi

	if [ ${#files[@]} -gt 0 ]; then
		local result installed failed_count
		result=$(cfg_checkout_files "$GIT_DIR" "${files[@]}") || true
		installed="${result%% *}"
		failed_count="${result##* }"
		printf 'Checked out %s files (%s failed)\n' "${installed:-0}" "${failed_count:-0}"
	fi

	git --git-dir="$GIT_DIR/" --work-tree="$HOME" config status.showUntrackedFiles no 2>/dev/null || true
	cfg_record_checkout_state_for_category "$GIT_DIR" "min" "$selected_version" 2>/dev/null || true

	# ── Step 6: done ──────────────────────────────────────────────────
	printf '\n=== Installation complete ===\n\n'
	printf 'Fresh root node: %s\n' "$root_code"
	printf 'Current state: fresh (deployed)\n\n'
	printf 'Next steps:\n'
	printf '  dotcfg switch full      Install all managed configuration\n'
	printf '  dotcfg switch min       Install command-line configuration\n'
	printf '  dotcfg switch macos     Install cross-platform core configuration\n'
	printf '  dotcfg status           Show current state\n'
	printf '  dotcfg fresh-status     Show fresh node backup details\n'
	return 0
}
