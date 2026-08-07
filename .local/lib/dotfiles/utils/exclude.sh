#!/usr/bin/env bash
# utils/exclude.sh - Exclusion rules for full $HOME scans (fresh node backups)
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_EXCLUDE_LOADED:-}" ]; then
	return 0
fi
_CFG_EXCLUDE_LOADED=1

# ── Hardcoded exclusions (always active) ───────────────────────────────

_FRESH_EXCLUDE_HARDCODED=(
	# System itself
	".cfg/*"
	".config-backup/*"
	".cfg-checkout-state"
	".local/bin/dotcfg"
	".local/lib/dotfiles/*"
	".local/share/test/*"
	# User data directories
	"Downloads/*"
	"Desktop/*"
	"Documents/*"
	"Videos/*"
	"Music/*"
	"Pictures/*"
	".cache/*"
	".local/share/Trash/*"
	".thumbnails/*"
	".npm/*"
	".cargo/*"
	# Temp files and logs
	".bash_history"
	".zsh_history"
	".lesshst"
	".viminfo"
	"*.log"
	"*.tmp"
	"*.swp"
	"core.*"
)

# Directories pruned during $HOME scans (derived from patterns ending in /*)
_FRESH_EXCLUDE_PRUNE_DIRS=(
	".cfg" ".config-backup" ".local/lib/dotfiles" ".local/share/test"
	"Downloads" "Desktop" "Documents" "Videos" "Music" "Pictures"
	".cache" ".local/share/Trash" ".thumbnails" ".npm" ".cargo"
)

_FRESH_EXCLUDE_CONF_PATTERNS=()
_FRESH_EXCLUDE_CONF_LOADED=false

_fresh_exclude_load_conf() {
	$_FRESH_EXCLUDE_CONF_LOADED && return 0
	_FRESH_EXCLUDE_CONF_LOADED=true
	_FRESH_EXCLUDE_CONF_PATTERNS=()

	local conf="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}/exclude.conf"
	[ -f "$conf" ] || return 0

	local line trimmed
	while IFS= read -r line || [ -n "$line" ]; do
		trimmed="${line#"${line%%[![:space:]]*}"}"
		trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
		[ -z "$trimmed" ] && continue
		[[ "$trimmed" == \#* ]] && continue
		if [[ "$trimmed" == /* ]]; then
			printf 'WARNING: absolute path in exclude.conf ignored: %s\n' "$trimmed" >&2
			continue
		fi
		_FRESH_EXCLUDE_CONF_PATTERNS+=("$trimmed")
	done < "$conf"
}

# fresh_exclude_is_excluded <relpath>
# Returns 0 if the path matches any hardcoded or exclude.conf pattern.
fresh_exclude_is_excluded() {
	local path="$1"
	path="${path#./}"

	local p
	for p in "${_FRESH_EXCLUDE_HARDCODED[@]}"; do
		# shellcheck disable=SC2254
		case "$path" in
			$p) return 0 ;;
		esac
	done

	_fresh_exclude_load_conf
	for p in "${_FRESH_EXCLUDE_CONF_PATTERNS[@]}"; do
		# shellcheck disable=SC2254
		case "$path" in
			$p) return 0 ;;
		esac
	done
	return 1
}

# fresh_exclude_reason <relpath>
# Prints which rule excluded the path: "hardcoded: <pattern>" or "exclude.conf: <pattern>".
# Returns 1 if not excluded.
fresh_exclude_reason() {
	local path="$1"
	path="${path#./}"

	local p
	for p in "${_FRESH_EXCLUDE_HARDCODED[@]}"; do
		# shellcheck disable=SC2254
		case "$path" in
			$p) printf 'hardcoded: %s\n' "$p"; return 0 ;;
		esac
	done

	_fresh_exclude_load_conf
	for p in "${_FRESH_EXCLUDE_CONF_PATTERNS[@]}"; do
		# shellcheck disable=SC2254
		case "$path" in
			$p) printf 'exclude.conf: %s\n' "$p"; return 0 ;;
		esac
	done
	return 1
}

# fresh_scan_home
# Scans $HOME for regular files, pruning excluded directories and skipping
# excluded file patterns. Prints relative paths (sorted).
fresh_scan_home() {
	local prune_args=()
	local d
	for d in "${_FRESH_EXCLUDE_PRUNE_DIRS[@]}"; do
		prune_args+=( -path "$HOME/$d" -o )
	done

	local f rel
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		rel="${f#"$HOME"/}"
		if fresh_exclude_is_excluded "$rel"; then
			continue
		fi
		printf '%s\n' "$rel"
	done < <(find "$HOME" "${prune_args[@]}" -type f -print 2>/dev/null | LC_ALL=C sort)
}
