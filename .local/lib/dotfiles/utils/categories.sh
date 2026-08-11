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

declare -gA _CFG_CONFIG_BODY_CACHE=()
declare -gA _CFG_CONFIG_VERSION_CACHE=()
declare -gA _CFG_CONFIG_NAME_CACHE=()
declare -gA _CFG_CONFIG_DESCRIPTION_CACHE=()
declare -gA _CFG_CONFIG_TAG_CACHE=()
declare -gA _CFG_CONFIG_VALID_TAGS_CACHE=()
declare -gA _CFG_CONFIG_ALIASES_CACHE=()
declare -gA _CFG_CONFIG_STATE_DEFAULT_CACHE=()
declare -gA _CFG_CONFIG_STATE_INDICATORS_CACHE=()
declare -gA CFG_CATEGORY_ALIASES=()
declare -gA CFG_STATE_INDICATOR_CATEGORIES=()
declare -ga CFG_STATE_INDICATOR_PATHS=()

# Compatibility metadata used only when the selected configuration omits the
# corresponding header. Versioned categories files remain the policy source.
_CFG_VALID_TAGS_DEFAULT="stable,test,experimental"
_CFG_CATEGORY_ALIASES_DEFAULT=""
_CFG_STATE_DEFAULT_DEFAULT="min"
_CFG_STATE_INDICATORS_DEFAULT="full:.xinitrc,full:.xprofile,full:.config/x11/xinitrc"
CFG_VALID_TAGS="$_CFG_VALID_TAGS_DEFAULT"
CFG_STATE_DEFAULT="$_CFG_STATE_DEFAULT_DEFAULT"

# ── Built-in compatibility categories ───────────────────────────────────

# Used only when no usable categories configuration exists. Keep this fallback
# synchronized with the stable configuration; define new policy in *.conf.
_CFG_CATEGORIES_BUILTIN='category = macos
+ .bashrc
+ .zshrc
+ .profile
+ .zprofile
+ .gitconfig
+ .gitignore
+ .npmrc
+ .config/git/ignore
+ .config/shell/aliasrc
+ .config/shell/bm-dirs
+ .config/shell/bm-files
+ .config/shell/inputrc
+ .config/shell/profile
+ .config/shell/zprofile
+ .config/zsh/.zshrc
+ .config/tmux/tmux.conf
+ .config/tmux/tmux.conf.local

category = min
include = macos
+ .custom.el
+ .fbtermrc
+ .config/lf/cleaner
+ .config/lf/icons
+ .config/lf/lfrc
+ .config/lf/scope
+ .config/wget/wgetrc
'

# ── Built-in exclude protections ────────────────────────────────────────

_CFG_EXCLUDE_BUILTIN=(
	".local/lib/dotfiles/*"
	".cfg/*"
	".config-backup/*"
	".config-backup.bak/*"
	".cfg-checkout-state"
	".local/share/test/*"
)

_CFG_EXCLUDE_PATTERNS=()

# ── Helper: trim whitespace ─────────────────────────────────────────────

_cfg_trim_into() {
	local _cfg_trim_target="$1"
	local _cfg_trim_text="$2"
	_cfg_trim_text="${_cfg_trim_text#"${_cfg_trim_text%%[![:space:]]*}"}"
	_cfg_trim_text="${_cfg_trim_text%"${_cfg_trim_text##*[![:space:]]}"}"
	printf -v "$_cfg_trim_target" '%s' "$_cfg_trim_text"
}

_cfg_trim() {
	local value
	_cfg_trim_into value "$1"
	printf '%s' "$value"
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
	local line trimmed val

	while IFS= read -r line || [ -n "$line" ]; do
		_cfg_trim_into trimmed "$line"

		[ -z "$trimmed" ] && continue
		[[ "$trimmed" == \#* ]] && continue

		if [[ "$trimmed" == category[[:space:]]*=* ]]; then
			val="${trimmed#*=}"
			_cfg_trim_into current_cat "$val"
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
			_cfg_trim_into val "$val"
			_CFG_CAT_INCLUDES[$current_cat]="$val"
			continue
		fi

		if [[ "$trimmed" == "+ "* ]] || [[ "$trimmed" == "+"$'\t'* ]]; then
			section="add"
			val="${trimmed#\+}"
			_cfg_trim_into val "$val"
			[ -n "$val" ] && _CFG_CAT_ADDS[$current_cat]+="$val"$'\n'
			continue
		fi

		if [[ "$trimmed" == "- "* ]] || [[ "$trimmed" == "-"$'\t'* ]]; then
			section="remove"
			val="${trimmed#-}"
			_cfg_trim_into val "$val"
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

# ── Category installation protections ──────────────────────────────────

_cfg_exclude_load() {
	_CFG_EXCLUDE_PATTERNS=("${_CFG_EXCLUDE_BUILTIN[@]}")
}

# ── Config version management ───────────────────────────────────────────

_CFG_CONF_VERSION=""
_CFG_CONF_NAME=""
_CFG_CONF_DESCRIPTION=""
_CFG_CONF_TAG="stable"
_CFG_CONF_VALID_TAGS="$_CFG_VALID_TAGS_DEFAULT"
_CFG_CONF_CATEGORY_ALIASES="$_CFG_CATEGORY_ALIASES_DEFAULT"
_CFG_CONF_STATE_DEFAULT="$_CFG_STATE_DEFAULT_DEFAULT"
_CFG_CONF_STATE_INDICATORS="$_CFG_STATE_INDICATORS_DEFAULT"
_CFG_CONF_BODY=""

# cfg_config_version_latest
# Prints the highest discovered semantic configuration version.
cfg_config_version_latest() {
	local versions
	versions=$(cfg_config_version_list)
	[ -z "$versions" ] && return 1
	printf '%s\n' "$versions" | tail -1
}

# cfg_config_version_read <version>
# Loads and prints a version file, populating its metadata cache; returns 1 if
# the requested version file does not exist.
cfg_config_version_read() {
	local version="$1"
	local file="$DOTFILES_LIB_DIR/categories-${version}.conf"
	if [ ! -f "$file" ]; then
		file="$DOTFILES_LIB_DIR/categories-v${version}.conf"
	fi
	[ -f "$file" ] || return 1

	if [ -n "${_CFG_CONFIG_BODY_CACHE[$file]+x}" ]; then
		_CFG_CONF_VERSION="${_CFG_CONFIG_VERSION_CACHE[$file]}"
		_CFG_CONF_NAME="${_CFG_CONFIG_NAME_CACHE[$file]}"
		_CFG_CONF_DESCRIPTION="${_CFG_CONFIG_DESCRIPTION_CACHE[$file]}"
		_CFG_CONF_TAG="${_CFG_CONFIG_TAG_CACHE[$file]}"
		_CFG_CONF_VALID_TAGS="${_CFG_CONFIG_VALID_TAGS_CACHE[$file]}"
		_CFG_CONF_CATEGORY_ALIASES="${_CFG_CONFIG_ALIASES_CACHE[$file]}"
		_CFG_CONF_STATE_DEFAULT="${_CFG_CONFIG_STATE_DEFAULT_CACHE[$file]}"
		_CFG_CONF_STATE_INDICATORS="${_CFG_CONFIG_STATE_INDICATORS_CACHE[$file]}"
		_CFG_CONF_BODY="${_CFG_CONFIG_BODY_CACHE[$file]}"
		CFG_CATEGORIES_TAGS["$version"]="$_CFG_CONF_TAG"
		[ -z "$_CFG_CONF_VERSION" ] || CFG_CATEGORIES_TAGS["${_CFG_CONF_VERSION#v}"]="$_CFG_CONF_TAG"
		printf '%s' "$_CFG_CONF_BODY"
		return 0
	fi

	local content
	content=$(<"$file")

	_CFG_CONF_VERSION=""
	_CFG_CONF_NAME=""
	_CFG_CONF_DESCRIPTION=""
	_CFG_CONF_TAG="stable"
	_CFG_CONF_VALID_TAGS="$_CFG_VALID_TAGS_DEFAULT"
	_CFG_CONF_CATEGORY_ALIASES="$_CFG_CATEGORY_ALIASES_DEFAULT"
	_CFG_CONF_STATE_DEFAULT="$_CFG_STATE_DEFAULT_DEFAULT"
	_CFG_CONF_STATE_INDICATORS="$_CFG_STATE_INDICATORS_DEFAULT"

	local in_header=true
	_CFG_CONF_BODY=""
	while IFS= read -r line || [ -n "$line" ]; do
		local trimmed
		_cfg_trim_into trimmed "$line"
		if $in_header; then
			if [ -z "$trimmed" ] || [[ "$trimmed" == \#* ]]; then
				if [[ "$trimmed" == \#[[:space:]]*VERSION[[:space:]]*=* ]]; then
					_cfg_trim_into _CFG_CONF_VERSION "${trimmed#*=}"
					_CFG_CONF_VERSION="${_CFG_CONF_VERSION%\"}"
					_CFG_CONF_VERSION="${_CFG_CONF_VERSION#\"}"
				elif [[ "$trimmed" == \#[[:space:]]*NAME[[:space:]]*=* ]]; then
					_cfg_trim_into _CFG_CONF_NAME "${trimmed#*=}"
					_CFG_CONF_NAME="${_CFG_CONF_NAME%\"}"
					_CFG_CONF_NAME="${_CFG_CONF_NAME#\"}"
				elif [[ "$trimmed" == \#[[:space:]]*DESCRIPTION[[:space:]]*=* ]]; then
					_cfg_trim_into _CFG_CONF_DESCRIPTION "${trimmed#*=}"
					_CFG_CONF_DESCRIPTION="${_CFG_CONF_DESCRIPTION%\"}"
					_CFG_CONF_DESCRIPTION="${_CFG_CONF_DESCRIPTION#\"}"
				elif [[ "$trimmed" == \#[[:space:]]*TAG[[:space:]]*=* ]]; then
					_cfg_trim_into _CFG_CONF_TAG "${trimmed#*=}"
					_CFG_CONF_TAG="${_CFG_CONF_TAG%\"}"
					_CFG_CONF_TAG="${_CFG_CONF_TAG#\"}"
					_CFG_CONF_TAG="${_CFG_CONF_TAG%\'}"
					_CFG_CONF_TAG="${_CFG_CONF_TAG#\'}"
				elif [[ "$trimmed" == \#[[:space:]]*VALID_TAGS[[:space:]]*=* ]]; then
					_cfg_trim_into _CFG_CONF_VALID_TAGS "${trimmed#*=}"
					_CFG_CONF_VALID_TAGS="${_CFG_CONF_VALID_TAGS%\"}"
					_CFG_CONF_VALID_TAGS="${_CFG_CONF_VALID_TAGS#\"}"
				elif [[ "$trimmed" == \#[[:space:]]*CATEGORY_ALIASES[[:space:]]*=* ]]; then
					_cfg_trim_into _CFG_CONF_CATEGORY_ALIASES "${trimmed#*=}"
					_CFG_CONF_CATEGORY_ALIASES="${_CFG_CONF_CATEGORY_ALIASES%\"}"
					_CFG_CONF_CATEGORY_ALIASES="${_CFG_CONF_CATEGORY_ALIASES#\"}"
				elif [[ "$trimmed" == \#[[:space:]]*STATE_DEFAULT[[:space:]]*=* ]]; then
					_cfg_trim_into _CFG_CONF_STATE_DEFAULT "${trimmed#*=}"
					_CFG_CONF_STATE_DEFAULT="${_CFG_CONF_STATE_DEFAULT%\"}"
					_CFG_CONF_STATE_DEFAULT="${_CFG_CONF_STATE_DEFAULT#\"}"
				elif [[ "$trimmed" == \#[[:space:]]*STATE_INDICATORS[[:space:]]*=* ]]; then
					_cfg_trim_into _CFG_CONF_STATE_INDICATORS "${trimmed#*=}"
					_CFG_CONF_STATE_INDICATORS="${_CFG_CONF_STATE_INDICATORS%\"}"
					_CFG_CONF_STATE_INDICATORS="${_CFG_CONF_STATE_INDICATORS#\"}"
				fi
				continue
			fi
			in_header=false
		fi
		_CFG_CONF_BODY+="$line"$'\n'
	done <<< "$content"

	[ -n "$_CFG_CONF_VALID_TAGS" ] || _CFG_CONF_VALID_TAGS="$_CFG_VALID_TAGS_DEFAULT"
	[ -n "$_CFG_CONF_CATEGORY_ALIASES" ] || _CFG_CONF_CATEGORY_ALIASES="$_CFG_CATEGORY_ALIASES_DEFAULT"
	[ -n "$_CFG_CONF_STATE_DEFAULT" ] || _CFG_CONF_STATE_DEFAULT="$_CFG_STATE_DEFAULT_DEFAULT"
	[ -n "$_CFG_CONF_STATE_INDICATORS" ] || _CFG_CONF_STATE_INDICATORS="$_CFG_STATE_INDICATORS_DEFAULT"

	local tag_is_valid=false valid_tag
	IFS=',' read -ra _cfg_valid_tags <<< "$_CFG_CONF_VALID_TAGS"
	for valid_tag in "${_cfg_valid_tags[@]}"; do
		_cfg_trim_into valid_tag "$valid_tag"
		if [ "$_CFG_CONF_TAG" = "$valid_tag" ]; then
			tag_is_valid=true
			break
		fi
	done
	if ! $tag_is_valid; then
		printf 'WARNING: unsupported TAG "%s" in categories-%s.conf; using stable\n' \
			"$_CFG_CONF_TAG" "$version" >&2
		_CFG_CONF_TAG="stable"
	fi
	CFG_CATEGORIES_TAGS["$version"]="$_CFG_CONF_TAG"
	if [ -n "$_CFG_CONF_VERSION" ]; then
		CFG_CATEGORIES_TAGS["${_CFG_CONF_VERSION#v}"]="$_CFG_CONF_TAG"
	fi
	_CFG_CONFIG_BODY_CACHE["$file"]="$_CFG_CONF_BODY"
	_CFG_CONFIG_VERSION_CACHE["$file"]="$_CFG_CONF_VERSION"
	_CFG_CONFIG_NAME_CACHE["$file"]="$_CFG_CONF_NAME"
	_CFG_CONFIG_DESCRIPTION_CACHE["$file"]="$_CFG_CONF_DESCRIPTION"
	_CFG_CONFIG_TAG_CACHE["$file"]="$_CFG_CONF_TAG"
	_CFG_CONFIG_VALID_TAGS_CACHE["$file"]="$_CFG_CONF_VALID_TAGS"
	_CFG_CONFIG_ALIASES_CACHE["$file"]="$_CFG_CONF_CATEGORY_ALIASES"
	_CFG_CONFIG_STATE_DEFAULT_CACHE["$file"]="$_CFG_CONF_STATE_DEFAULT"
	_CFG_CONFIG_STATE_INDICATORS_CACHE["$file"]="$_CFG_CONF_STATE_INDICATORS"

	printf '%s' "$_CFG_CONF_BODY"
}

# cfg_categories_invalidate
# Discards cached version metadata and parsed category state. Call after a
# categories configuration file is changed in the current process.
cfg_categories_invalidate() {
	unset _CFG_CONFIG_BODY_CACHE _CFG_CONFIG_VERSION_CACHE _CFG_CONFIG_NAME_CACHE
	unset _CFG_CONFIG_DESCRIPTION_CACHE _CFG_CONFIG_TAG_CACHE
	unset _CFG_CONFIG_VALID_TAGS_CACHE _CFG_CONFIG_ALIASES_CACHE
	unset _CFG_CONFIG_STATE_DEFAULT_CACHE _CFG_CONFIG_STATE_INDICATORS_CACHE
	unset CFG_CATEGORIES_TAGS
	declare -gA _CFG_CONFIG_BODY_CACHE=()
	declare -gA _CFG_CONFIG_VERSION_CACHE=()
	declare -gA _CFG_CONFIG_NAME_CACHE=()
	declare -gA _CFG_CONFIG_DESCRIPTION_CACHE=()
	declare -gA _CFG_CONFIG_TAG_CACHE=()
	declare -gA _CFG_CONFIG_VALID_TAGS_CACHE=()
	declare -gA _CFG_CONFIG_ALIASES_CACHE=()
	declare -gA _CFG_CONFIG_STATE_DEFAULT_CACHE=()
	declare -gA _CFG_CONFIG_STATE_INDICATORS_CACHE=()
	declare -gA CFG_CATEGORIES_TAGS=()
	_cfg_categories_parse ""
	cfg_categories_metadata_reset
}

# cfg_categories_metadata_reset
# Restores metadata defaults before loading a version or legacy config file.
cfg_categories_metadata_reset() {
	unset CFG_CATEGORY_ALIASES CFG_STATE_INDICATOR_CATEGORIES CFG_STATE_INDICATOR_PATHS
	declare -gA CFG_CATEGORY_ALIASES=()
	declare -gA CFG_STATE_INDICATOR_CATEGORIES=()
	declare -ga CFG_STATE_INDICATOR_PATHS=()
	CFG_VALID_TAGS="$_CFG_VALID_TAGS_DEFAULT"
	CFG_STATE_DEFAULT="$_CFG_STATE_DEFAULT_DEFAULT"
}

# cfg_categories_metadata_apply
# Applies optional header metadata parsed from the selected category file.
cfg_categories_metadata_apply() {
	cfg_categories_metadata_reset
	CFG_VALID_TAGS="${_CFG_CONF_VALID_TAGS:-$_CFG_VALID_TAGS_DEFAULT}"
	CFG_STATE_DEFAULT="${_CFG_CONF_STATE_DEFAULT:-$_CFG_STATE_DEFAULT_DEFAULT}"

	local entry alias target path category
	IFS=',' read -ra _cfg_aliases <<< "${_CFG_CONF_CATEGORY_ALIASES:-}"
	for entry in "${_cfg_aliases[@]}"; do
		_cfg_trim_into entry "$entry"
		[ -z "$entry" ] && continue
		alias="${entry%%:*}"
		target="${entry#*:}"
		[ "$entry" = "$alias" ] && continue
		_cfg_trim_into alias "$alias"
		_cfg_trim_into target "$target"
		[ "$alias" = "full" ] && continue
		[ -n "$alias" ] && [ -n "$target" ] && CFG_CATEGORY_ALIASES["$alias"]="$target"
	done

	IFS=',' read -ra _cfg_indicators <<< "${_CFG_CONF_STATE_INDICATORS:-}"
	for entry in "${_cfg_indicators[@]}"; do
		_cfg_trim_into entry "$entry"
		[ -z "$entry" ] && continue
		category="${entry%%:*}"
		path="${entry#*:}"
		[ "$entry" = "$category" ] && continue
		_cfg_trim_into category "$category"
		_cfg_trim_into path "$path"
		if [ -n "$category" ] && [ -n "$path" ]; then
			CFG_STATE_INDICATOR_CATEGORIES["$path"]="$category"
			CFG_STATE_INDICATOR_PATHS+=("$path")
		fi
	done
}

# cfg_category_alias_target <name>
# Prints the canonical category name for an alias, or the input name.
cfg_category_alias_target() {
	local name="${1:-}"
	if [ -n "${CFG_CATEGORY_ALIASES[$name]+x}" ]; then
		printf '%s' "${CFG_CATEGORY_ALIASES[$name]}"
		return 0
	fi
	return 1
}

# cfg_state_default_category [version]
# Prints the configured fallback category for state detection.
cfg_state_default_category() {
	printf '%s' "$CFG_STATE_DEFAULT"
}

# cfg_state_indicator_category <path> [version]
# Prints the category associated with a state indicator path.
cfg_state_indicator_category() {
	local path="${1:-}"
	if [ -n "${CFG_STATE_INDICATOR_CATEGORIES[$path]+x}" ]; then
		printf '%s' "${CFG_STATE_INDICATOR_CATEGORIES[$path]}"
		return 0
	fi
	return 1
}

# cfg_config_tag_is_valid <tag> [version]
# Returns zero when a category version accepts the supplied TAG value.
cfg_config_tag_is_valid() {
	local value="${1:-}" tag
	IFS=',' read -ra _cfg_valid_tags <<< "$CFG_VALID_TAGS"
	for tag in "${_cfg_valid_tags[@]}"; do
		_cfg_trim_into tag "$tag"
		[ "$value" = "$tag" ] && return 0
	done
	return 1
}

# cfg_config_get_tag <version>
# Prints the normalized TAG for a category version, defaulting to stable.
cfg_config_get_tag() {
	local version="$1"
	if [ -n "${CFG_CATEGORIES_TAGS[$version]+x}" ]; then
		printf '%s' "${CFG_CATEGORIES_TAGS[$version]}"
		return 0
	fi
	cfg_config_version_read "$version" >/dev/null || return 1
	printf '%s' "$_CFG_CONF_TAG"
}

# cfg_config_version_info <version>
# Prints the human-readable metadata for a category version.
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
	local selected_version=false
	cfg_categories_metadata_reset

	if [ -n "$arg" ] && [[ "$arg" == [0-9]*.[0-9]* ]]; then
		cfg_config_version_read "$arg" >/dev/null 2>&1 || {
			_cfg_categories_parse "$_CFG_CATEGORIES_BUILTIN"
			_cfg_exclude_load
			_CFG_CATEGORIES_LOADED=1
			return 1
		}
		selected_version=true
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
				if [ -n "$_CFG_CONF_BODY" ]; then
					content="$_CFG_CONF_BODY"
					selected_version=true
				else
					content=$(<"$DOTFILES_LIB_DIR/categories.conf")
				fi
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

	if $selected_version; then
		cfg_categories_metadata_apply
	fi

	_cfg_exclude_load

	local cat
	for cat in "${_CFG_CAT_NAMES[@]}"; do
		_cfg_resolve_category "$cat" "" || true
	done

	_CFG_CATEGORIES_LOADED=1
	return 0
}

# cfg_categories_list [version]
# Prints category names available in the selected version.
cfg_categories_list() {
	local cat
	for cat in "${_CFG_CAT_NAMES[@]}"; do
		[ "$cat" = "full" ] && continue
		printf '%s\n' "$cat"
	done
	printf '%s\n' "full"
}

# cfg_category_canonical_name <name>
# Maps explicitly configured aliases to category names.
cfg_category_canonical_name() {
	local alias_target
	if [ "${1:-}" = "full" ]; then
		printf 'full'
		return 0
	fi
	if alias_target=$(cfg_category_alias_target "${1:-}"); then
		printf '%s' "$alias_target"
		return 0
	fi
	printf '%s' "${1:-}"
}

# cfg_category_exists <category> [version]
# Returns zero when the category exists in the selected version.
cfg_category_exists() {
	local name
	name=$(cfg_category_canonical_name "$1")
	[ "$name" = "full" ] && return 0
	[[ " ${_CFG_CAT_NAMES[*]} " == *" $name "* ]]
}

# cfg_category_get_files <category> [git_dir]
# Prints the tracked paths resolved by a category.
cfg_category_get_files() {
	local name
	name=$(cfg_category_canonical_name "$1")
	local git_dir="${2:-$HOME/.cfg}"

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

# cfg_category_diff <left> <right> [git_dir]
# Prints paths present in one category but not the other.
cfg_category_diff() {
	local base="$1" overlay="$2"
	local git_dir="${3:-$HOME/.cfg}"

	local base_files
	base_files=$(cfg_category_get_files "$base" "$git_dir")

	local overlay_files
	overlay_files=$(cfg_category_get_files "$overlay" "$git_dir")

	while IFS= read -r line; do
		[ -z "$line" ] && continue
		if ! printf '%s\n' "$base_files" | grep -qFx "$line"; then
			printf '%s\n' "$line"
		fi
	done <<< "$overlay_files"
}

# cfg_is_installation_path <relative_path>
# Installation infrastructure is available in every state and category.
cfg_is_installation_path() {
	case "${1:-}" in
		.local/bin/dotcfg|.local/lib/dotfiles/*) return 0 ;;
		*) return 1 ;;
	esac
}

# cfg_exclude_match <relative_path>
# Returns zero when a category operation must protect the path. Fresh policy
# rules are handled separately by utils/exclude.sh.
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
