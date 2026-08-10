#!/usr/bin/env bash
# utils/categories.sh - Declarative file category system for dotfiles
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_CATEGORIES_LOADED:-}" ]; then
	return 0
fi
_CFG_CATEGORIES_LOADED=1

DOTFILES_LIB_DIR="${DOTFILES_LIB_DIR:-$HOME/.local/lib/dotfiles}"

# ── Global data structures ──────────────────────────────────────────────

declare -A _CFG_CAT_INCLUDES=()
declare -A _CFG_CAT_ADDS=()
declare -A _CFG_CAT_SUBS=()
declare -A _CFG_CAT_RESOLVED=()
declare -gA CFG_CATEGORIES_TAGS=()
_CFG_CAT_NAMES=()

# ── Built-in default categories ─────────────────────────────────────────

_CFG_CATEGORIES_BUILTIN='category = server
+ .config/shell/profile
+ .config/shell/aliasrc
+ .config/shell/zshrc
+ .config/shell/tmux.conf.local
+ .bashrc
+ .zshrc
+ .profile
+ .config/tmux/tmux.conf
+ .config/tmux/tmux.conf.local
+ .tmux.conf
+ .config/git/gitconfig
+ .config/git/ignore
+ .gitconfig
+ .gitignore
+ .config/lf/lfrc
+ .config/lf/scope
+ .config/lf/cleaner
+ .config/lf/icons
+ .config/lf/shortcutrc
+ .local/share/docs/README.md
+ .local/share/docs/user/desktop-guide-zh.md

category = desktop
include = server
+ .xinitrc
+ .xprofile
+ .asoundrc
+ .gtkrc-2.0
+ .config/x11
+ .config/alsa
+ .config/mpd
+ .config/nsxiv
+ .config/zathura
'

# ── Built-in exclude protections ────────────────────────────────────────

_CFG_EXCLUDE_BUILTIN=(
	".local/lib/dotfiles/*"
	".cfg/*"
	".config-backup/*"
	".cfg-checkout-state"
	".local/share/test/*"
)

_CFG_EXCLUDE_PATTERNS=()

# ── Helper: trim whitespace ─────────────────────────────────────────────

_cfg_trim() {
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

# ── Parser ──────────────────────────────────────────────────────────────

_cfg_categories_parse() {
	local content="$1"

	unset _CFG_CAT_INCLUDES _CFG_CAT_ADDS _CFG_CAT_SUBS _CFG_CAT_RESOLVED
	declare -gA _CFG_CAT_INCLUDES
	declare -gA _CFG_CAT_ADDS
	declare -gA _CFG_CAT_SUBS
	declare -gA _CFG_CAT_RESOLVED
	_CFG_CAT_NAMES=()

	local current_cat=""
	local section="include"
	local line trimmed key val

	while IFS= read -r line || [ -n "$line" ]; do
		trimmed=$(_cfg_trim "$line")

		[ -z "$trimmed" ] && continue
		[[ "$trimmed" == \#* ]] && continue

		if [[ "$trimmed" == category[[:space:]]*=* ]]; then
			val="${trimmed#*=}"
			current_cat=$(_cfg_trim "$val")
			section="include"
			if [[ " ${_CFG_CAT_NAMES[*]} " != *" $current_cat "* ]]; then
				_CFG_CAT_NAMES+=("$current_cat")
			fi
			_CFG_CAT_ADDS[$current_cat]=""
			_CFG_CAT_SUBS[$current_cat]=""
			continue
		fi

		[ -z "$current_cat" ] && continue

		if [[ "$trimmed" == include[[:space:]]*=* ]] && [ "$section" = "include" ]; then
			val="${trimmed#*=}"
			_CFG_CAT_INCLUDES[$current_cat]=$(_cfg_trim "$val")
			continue
		fi

		if [[ "$trimmed" == "+ "* ]] || [[ "$trimmed" == "+"$'\t'* ]]; then
			section="add"
			val="${trimmed#\+}"
			val=$(_cfg_trim "$val")
			[ -n "$val" ] && _CFG_CAT_ADDS[$current_cat]+="$val"$'\n'
			continue
		fi

		if [[ "$trimmed" == "- "* ]] || [[ "$trimmed" == "-"$'\t'* ]]; then
			section="remove"
			val="${trimmed#-}"
			val=$(_cfg_trim "$val")
			[ -n "$val" ] && _CFG_CAT_SUBS[$current_cat]+="$val"$'\n'
			continue
		fi
	done <<< "$content"
}

# ── Directory expansion ─────────────────────────────────────────────────

_cfg_expand_path() {
	printf '%s\n' "$1"
}

# ── Inheritance resolution ──────────────────────────────────────────────

_cfg_resolve_category() {
	local name="$1"
	local visiting="$2"

	if [ -n "${_CFG_CAT_RESOLVED[$name]+x}" ]; then
		return 0
	fi

	if [[ " $visiting " == *" $name "* ]]; then
		printf 'WARNING: circular category include detected at "%s"\n' "$name" >&2
		return 1
	fi

	local new_visiting="$visiting $name"

	local parent="${_CFG_CAT_INCLUDES[$name]:-}"
	local base=""

	if [ -n "$parent" ]; then
		if ! _cfg_resolve_category "$parent" "$new_visiting"; then
			return 1
		fi
		base="${_CFG_CAT_RESOLVED[$parent]}"
	fi

	local adds="${_CFG_CAT_ADDS[$name]:-}"
	local subs="${_CFG_CAT_SUBS[$name]:-}"

	local result=""
	local seen_lines=""

	if [ -n "$base" ]; then
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			if [[ "$seen_lines" != *"|$line|"* ]]; then
				result+="$line"$'\n'
				seen_lines+="|$line|"
			fi
		done <<< "$base"
	fi

	if [ -n "$adds" ]; then
		while IFS= read -r path; do
			[ -z "$path" ] && continue
			while IFS= read -r ep; do
				[ -z "$ep" ] && continue
				if [[ "$seen_lines" != *"|$ep|"* ]]; then
					result+="$ep"$'\n'
					seen_lines+="|$ep|"
				fi
			done < <(_cfg_expand_path "$path")
		done <<< "$adds"
	fi

	if [ -n "$subs" ]; then
		local filtered=""
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			local is_sub=false
			while IFS= read -r sub; do
				[ -z "$sub" ] && continue
				if [ "$line" = "$sub" ]; then
					is_sub=true
					break
				fi
			done <<< "$subs"
			if [ "$is_sub" = false ]; then
				filtered+="$line"$'\n'
			fi
		done <<< "$result"
		result="$filtered"
	fi

	_CFG_CAT_RESOLVED[$name]="$result"
	return 0
}

# ── Exclude loading ─────────────────────────────────────────────────────

_cfg_exclude_load() {
	_CFG_EXCLUDE_PATTERNS=("${_CFG_EXCLUDE_BUILTIN[@]}")

	local exclude_file="$DOTFILES_LIB_DIR/exclude.conf"
	if [ -f "$exclude_file" ]; then
		local line lineno=0
		while IFS= read -r line || [ -n "$line" ]; do
			((lineno++))
			line=$(_cfg_trim "$line")
			[ -z "$line" ] && continue
			[[ "$line" == \#* ]] && continue
			if [[ "$line" == /* ]]; then
				printf 'WARNING: exclude.conf line %d: absolute path ignored: %s\n' "$lineno" "$line" >&2
				continue
			fi
			_CFG_EXCLUDE_PATTERNS+=("$line")
		done < "$exclude_file"
	fi
}

# ── Config version management ───────────────────────────────────────────

_CFG_CONF_VERSION=""
_CFG_CONF_NAME=""
_CFG_CONF_DESCRIPTION=""
_CFG_CONF_TAG="stable"
_CFG_CONF_BODY=""

cfg_config_version_latest() {
	local versions
	versions=$(cfg_config_version_list)
	[ -z "$versions" ] && return 1
	printf '%s\n' "$versions" | tail -1
}

cfg_config_version_read() {
	local version="$1"
	local file="$DOTFILES_LIB_DIR/categories-${version}.conf"
	if [ ! -f "$file" ]; then
		file="$DOTFILES_LIB_DIR/categories-v${version}.conf"
	fi
	[ -f "$file" ] || return 1

	local content
	content=$(<"$file")

	_CFG_CONF_VERSION=""
	_CFG_CONF_NAME=""
	_CFG_CONF_DESCRIPTION=""
	_CFG_CONF_TAG="stable"

	local in_header=true
	_CFG_CONF_BODY=""
	while IFS= read -r line || [ -n "$line" ]; do
		local trimmed
		trimmed=$(_cfg_trim "$line")
		if $in_header; then
			if [ -z "$trimmed" ] || [[ "$trimmed" == \#* ]]; then
				if [[ "$trimmed" == \#[[:space:]]*VERSION[[:space:]]*=* ]]; then
					_CFG_CONF_VERSION=$(_cfg_trim "${trimmed#*=}")
					_CFG_CONF_VERSION="${_CFG_CONF_VERSION%\"}"
					_CFG_CONF_VERSION="${_CFG_CONF_VERSION#\"}"
				elif [[ "$trimmed" == \#[[:space:]]*NAME[[:space:]]*=* ]]; then
					_CFG_CONF_NAME=$(_cfg_trim "${trimmed#*=}")
					_CFG_CONF_NAME="${_CFG_CONF_NAME%\"}"
					_CFG_CONF_NAME="${_CFG_CONF_NAME#\"}"
				elif [[ "$trimmed" == \#[[:space:]]*DESCRIPTION[[:space:]]*=* ]]; then
					_CFG_CONF_DESCRIPTION=$(_cfg_trim "${trimmed#*=}")
					_CFG_CONF_DESCRIPTION="${_CFG_CONF_DESCRIPTION%\"}"
					_CFG_CONF_DESCRIPTION="${_CFG_CONF_DESCRIPTION#\"}"
				elif [[ "$trimmed" == \#[[:space:]]*TAG[[:space:]]*=* ]]; then
					_CFG_CONF_TAG=$(_cfg_trim "${trimmed#*=}")
					_CFG_CONF_TAG="${_CFG_CONF_TAG%\"}"
					_CFG_CONF_TAG="${_CFG_CONF_TAG#\"}"
					_CFG_CONF_TAG="${_CFG_CONF_TAG%\'}"
					_CFG_CONF_TAG="${_CFG_CONF_TAG#\'}"
				fi
				continue
			fi
			in_header=false
		fi
		_CFG_CONF_BODY+="$line"$'\n'
	done <<< "$content"

	case "$_CFG_CONF_TAG" in
		stable|test|experimental) ;;
		*)
			printf 'WARNING: unsupported TAG "%s" in categories-%s.conf; using stable\n' \
				"$_CFG_CONF_TAG" "$version" >&2
			_CFG_CONF_TAG="stable"
			;;
	esac
	CFG_CATEGORIES_TAGS["$version"]="$_CFG_CONF_TAG"
	if [ -n "$_CFG_CONF_VERSION" ]; then
		CFG_CATEGORIES_TAGS["${_CFG_CONF_VERSION#v}"]="$_CFG_CONF_TAG"
	fi

	printf '%s' "$_CFG_CONF_BODY"
}

cfg_config_get_tag() {
	local version="$1"
	if [ -n "${CFG_CATEGORIES_TAGS[$version]+x}" ]; then
		printf '%s' "${CFG_CATEGORIES_TAGS[$version]}"
		return 0
	fi
	cfg_config_version_read "$version" >/dev/null || return 1
	printf '%s' "$_CFG_CONF_TAG"
}

cfg_config_version_info() {
	local version="$1"
	cfg_config_version_read "$version" >/dev/null || return 1
	printf 'Version: %s\n' "${_CFG_CONF_VERSION:-$version}"
	[ -n "$_CFG_CONF_NAME" ] && printf 'Name: %s\n' "$_CFG_CONF_NAME"
	[ -n "$_CFG_CONF_DESCRIPTION" ] && printf 'Description: %s\n' "$_CFG_CONF_DESCRIPTION"
	printf 'Tag: %s\n' "$_CFG_CONF_TAG"
	return 0
}

# ── Public API ──────────────────────────────────────────────────────────

cfg_categories_load() {
	local arg="${1:-}"
	local content=""

	if [ -n "$arg" ] && [[ "$arg" == [0-9]*.[0-9]* ]]; then
		cfg_config_version_read "$arg" >/dev/null 2>&1 || {
			_cfg_categories_parse "$_CFG_CATEGORIES_BUILTIN"
			_cfg_exclude_load
			_CFG_CATEGORIES_LOADED=1
			return 1
		}
		content="$_CFG_CONF_BODY"
	elif [ -n "$arg" ] && [ -f "$arg" ]; then
		content=$(<"$arg")
	elif [ -f "$DOTFILES_LIB_DIR/categories.conf" ]; then
		local has_versioned=false
		local _vf
		for _vf in "$DOTFILES_LIB_DIR"/categories-*.conf; do
			[ -f "$_vf" ] && { has_versioned=true; break; }
		done
		if $has_versioned; then
			local latest_ver
			latest_ver=$(cfg_config_version_latest 2>/dev/null) || latest_ver=""
			if [ -n "$latest_ver" ]; then
				cfg_config_version_read "$latest_ver" >/dev/null 2>&1 || _CFG_CONF_BODY=""
				[ -n "$_CFG_CONF_BODY" ] && content="$_CFG_CONF_BODY" || content=$(<"$DOTFILES_LIB_DIR/categories.conf")
			else
				content=$(<"$DOTFILES_LIB_DIR/categories.conf")
			fi
		else
			content=$(<"$DOTFILES_LIB_DIR/categories.conf")
		fi
	fi

	if [ -n "$content" ]; then
		_cfg_categories_parse "$content"
		if [ ${#_CFG_CAT_NAMES[@]} -eq 0 ]; then
			_cfg_categories_parse "$_CFG_CATEGORIES_BUILTIN"
		fi
	else
		_cfg_categories_parse "$_CFG_CATEGORIES_BUILTIN"
	fi

	_cfg_exclude_load

	local cat
	for cat in "${_CFG_CAT_NAMES[@]}"; do
		_cfg_resolve_category "$cat" "" || true
	done

	_CFG_CATEGORIES_LOADED=1
	return 0
}

cfg_categories_list() {
	local cat
	for cat in "${_CFG_CAT_NAMES[@]}"; do
		printf '%s\n' "$cat"
	done
	printf '%s\n' "full" "empty"
}

cfg_category_exists() {
	local name="$1"
	[ "$name" = "full" ] || [ "$name" = "empty" ] && return 0
	[[ " ${_CFG_CAT_NAMES[*]} " == *" $name "* ]]
}

cfg_category_get_files() {
	local name="$1"
	local git_dir="${2:-$HOME/.cfg}"

	if [ "$name" = "empty" ]; then
		return 0
	fi

	if [ "$name" = "full" ]; then
		git --git-dir="$git_dir/" --work-tree="$HOME" ls-tree -r --name-only HEAD 2>/dev/null
		return 0
	fi

	if [ -z "${_CFG_CAT_RESOLVED[$name]+x}" ]; then
		if ! _cfg_resolve_category "$name" ""; then
			return 1
		fi
	fi

	local resolved="${_CFG_CAT_RESOLVED[$name]}"
	while IFS= read -r line; do
		[ -z "$line" ] && continue
		printf '%s\n' "$line"
	done <<< "$resolved"
}

cfg_category_diff() {
	local base="$1" overlay="$2"

	local base_files
	base_files=$(cfg_category_get_files "$base")

	local overlay_files
	overlay_files=$(cfg_category_get_files "$overlay")

	while IFS= read -r line; do
		[ -z "$line" ] && continue
		if ! printf '%s\n' "$base_files" | grep -qFx "$line"; then
			printf '%s\n' "$line"
		fi
	done <<< "$overlay_files"
}

cfg_exclude_match() {
	local path="$1"
	local pattern
	for pattern in "${_CFG_EXCLUDE_PATTERNS[@]}"; do
		# shellcheck disable=SC2254
		case "$path" in
			$pattern) return 0 ;;
		esac
	done
	return 1
}
