#!/usr/bin/env bash
# utils/exclude.sh - Exclusion and tracking rules for fresh node backups
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

# cfg_is_path_tracked <path> [git_dir]
# Returns 0 when path is present in the dotfiles repository HEAD.
cfg_is_path_tracked() {
	local path="${1:-}"
	local git_dir="${2:-${GIT_DIR:-${DOTCFG_GIT_DIR:-$HOME/.cfg}}}"

	[ -n "$path" ] || return 1
	case "$path" in
		"$HOME"/*) path="${path#"$HOME"/}" ;;
		/*) return 1 ;;
		*) path="${path#./}" ;;
	esac
	[ -n "$path" ] && [ -d "$git_dir" ] || return 1

	git --git-dir="$git_dir/" ls-tree -r --name-only HEAD 2>/dev/null |
		grep -Fqx -- "$path"
}
