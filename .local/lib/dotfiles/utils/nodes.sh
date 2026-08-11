#!/usr/bin/env bash
# utils/nodes.sh - Node management for dotfiles state tracking
# Source via utils/common.sh, do not source directly.

if [ -n "${_CFG_NODES_LOADED:-}" ]; then
	return 0
fi
_CFG_NODES_LOADED=1

# ── Paths (set by cfg_nodes_init) ──────────────────────────────────────
CFG_NODES_DIR=""
CFG_NODES_INDEX=""
CFG_HEAD_FILE=""
CFG_DEPLOY_STATUS_FILE=""

# ── Arrays (populated by cfg_nodes_read_index) ─────────────────────────
_CFG_NODE_CODES=()
_CFG_NODE_TYPES=()
_CFG_NODE_TIMESTAMPS=()
_CFG_NODE_PARENTS=()
_CFG_NODE_CHILDREN=()
_CFG_NODE_CONFIG_VERSIONS=()
_CFG_NODE_STATUSES=()
declare -gA _CFG_NODE_INDEX_BY_CODE=()
_CFG_NODES_INDEX_LOADED=false

# ── Configuration version discovery cache ─────────────────────────────
_CFG_CONFIG_VERSIONS=()
declare -gA _CFG_CONFIG_VERSION_PREFIXES=()
_CFG_CONFIG_VERSIONS_LOADED=false
_CFG_CONFIG_VERSIONS_DIR=""

# ── Batch mode flag ─────────────────────────────────────────────────────
_CFG_NODES_BATCH_MODE=false

# ── Initialization ─────────────────────────────────────────────────────

_cfg_nodes_reset_cache() {
	_CFG_NODE_CODES=()
	_CFG_NODE_TYPES=()
	_CFG_NODE_TIMESTAMPS=()
	_CFG_NODE_PARENTS=()
	_CFG_NODE_CHILDREN=()
	_CFG_NODE_CONFIG_VERSIONS=()
	_CFG_NODE_STATUSES=()
	unset _CFG_NODE_INDEX_BY_CODE
	declare -gA _CFG_NODE_INDEX_BY_CODE=()
	_CFG_NODES_INDEX_LOADED=false
}

# cfg_nodes_invalidate
# Discards the process-local node index cache. Call after another process or
# direct file operation changes index.json. Takes no arguments and always
# succeeds.
cfg_nodes_invalidate() {
	_cfg_nodes_reset_cache
}

_cfg_nodes_rebuild_lookup() {
	local i
	unset _CFG_NODE_INDEX_BY_CODE
	declare -gA _CFG_NODE_INDEX_BY_CODE=()
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		_CFG_NODE_INDEX_BY_CODE["${_CFG_NODE_CODES[$i]}"]="$i"
	done
}

# cfg_nodes_init [backup_root]
# Initializes node paths and creates the nodes directory for the backup root.
cfg_nodes_init() {
	local backup_root="${1:-$HOME/.config-backup}"
	local nodes_dir="$backup_root/nodes"
	local index_file="$nodes_dir/index.json"
	if [ "${CFG_NODES_INDEX:-}" != "$index_file" ]; then
		_cfg_nodes_reset_cache
	fi
	CFG_NODES_DIR="$nodes_dir"
	CFG_NODES_INDEX="$index_file"
	CFG_HEAD_FILE="$backup_root/HEAD"
	CFG_DEPLOY_STATUS_FILE="$backup_root/DEPLOY_STATUS"

	mkdir -p "$CFG_NODES_DIR"
}

# ── Code Generation ────────────────────────────────────────────────────

cfg_generate_node_code() {
	local chars="abcdefghijklmnopqrstuvwxyz0123456789"
	local code=""
	local i idx
	for ((i = 0; i < 8; i++)); do
		idx=$((RANDOM % 36))
		code+="${chars:$idx:1}"
	done

	if cfg_node_exists "$code"; then
		cfg_generate_node_code
		return
	fi

	printf '%s' "$code"
}

# ── Index I/O ──────────────────────────────────────────────────────────

cfg_nodes_read_index() {
	if [ ! -f "$CFG_NODES_INDEX" ]; then
		_cfg_nodes_reset_cache
		return 1
	fi
	[ "$_CFG_NODES_INDEX_LOADED" = true ] && return 0

	_CFG_NODE_CODES=()
	_CFG_NODE_TYPES=()
	_CFG_NODE_TIMESTAMPS=()
	_CFG_NODE_PARENTS=()
	_CFG_NODE_CHILDREN=()
	_CFG_NODE_CONFIG_VERSIONS=()
	_CFG_NODE_STATUSES=()
	unset _CFG_NODE_INDEX_BY_CODE
	declare -gA _CFG_NODE_INDEX_BY_CODE=()

	local parsed
	parsed=$(awk '
		BEGIN { depth=0; in_node=0; code=""; type=""; ts=""; parent="null"; children=""; cver=""; nstatus="" }
		/\{/ {
			depth++
			if (depth == 2) {
				in_node=1; code=""; type=""; ts=""; parent="null"; children=""; cver=""; nstatus=""
			}
			next
		}
		/\}/ {
			if (depth == 2 && in_node) {
				if (code != "") {
					gsub(/"/, "", children)
					if (cver == "") cver=""
					if (nstatus == "") nstatus="active"
					print code "|" type "|" ts "|" parent "|" children "|" cver "|" nstatus
				}
				in_node=0
			}
			depth--
			next
		}
		in_node && /"code"/ {
			gsub(/.*"code"[[:space:]]*:[[:space:]]*"/, "")
			gsub(/".*/, "")
			code=$0
		}
		in_node && /"type"/ {
			gsub(/.*"type"[[:space:]]*:[[:space:]]*"/, "")
			gsub(/".*/, "")
			type=$0
		}
		in_node && /"timestamp"/ {
			gsub(/.*"timestamp"[[:space:]]*:[[:space:]]*"/, "")
			gsub(/".*/, "")
			ts=$0
		}
		in_node && /"parent"/ {
			gsub(/.*"parent"[[:space:]]*:[[:space:]]*/, "")
			gsub(/["\[\],]/, "")
			gsub(/[[:space:]]/, "")
			if ($0 == "null" || $0 == "") parent="null"
			else parent=$0
		}
		in_node && /"children"/ {
			gsub(/.*"children"[[:space:]]*:[[:space:]]*\[/, "")
			gsub(/\].*/, "")
			gsub(/[" ]/, "")
			children=$0
		}
		in_node && /"config_version"/ {
			gsub(/.*"config_version"[[:space:]]*:[[:space:]]*"/, "")
			gsub(/".*/, "")
			cver=$0
		}
		in_node && /"status"/ {
			gsub(/.*"status"[[:space:]]*:[[:space:]]*"/, "")
			gsub(/".*/, "")
			nstatus=$0
		}
	' "$CFG_NODES_INDEX")

	if [ -z "$parsed" ]; then
		_CFG_NODES_INDEX_LOADED=true
		return 0
	fi

	while IFS='|' read -r _nr_code _nr_type _nr_ts _nr_parent _nr_children _nr_cver _nr_status; do
		local _nr_index=${#_CFG_NODE_CODES[@]}
		_CFG_NODE_CODES+=("$_nr_code")
		_CFG_NODE_TYPES+=("$_nr_type")
		_CFG_NODE_TIMESTAMPS+=("$_nr_ts")
		_CFG_NODE_PARENTS+=("$_nr_parent")
		_CFG_NODE_CHILDREN+=("$_nr_children")
		_CFG_NODE_CONFIG_VERSIONS+=("${_nr_cver:-}")
		_CFG_NODE_STATUSES+=("${_nr_status:-active}")
		_CFG_NODE_INDEX_BY_CODE["$_nr_code"]="$_nr_index"
	done <<< "$parsed"
	_CFG_NODES_INDEX_LOADED=true
}

# cfg_nodes_write_index
# Serializes the in-memory node arrays to index.json and refreshes the lookup.
cfg_nodes_write_index() {
	local tmp="${CFG_NODES_INDEX}.tmp"

	printf '{\n  "nodes": [\n' > "$tmp"

	local i count=${#_CFG_NODE_CODES[@]}
	for ((i = 0; i < count; i++)); do
		local code="${_CFG_NODE_CODES[$i]}"
		local type="${_CFG_NODE_TYPES[$i]}"
		local ts="${_CFG_NODE_TIMESTAMPS[$i]}"
		local parent="${_CFG_NODE_PARENTS[$i]}"
		local children="${_CFG_NODE_CHILDREN[$i]}"
		local cver="${_CFG_NODE_CONFIG_VERSIONS[$i]:-}"
		local nstatus="${_CFG_NODE_STATUSES[$i]:-active}"

		local parent_json
		if [ "$parent" = "null" ] || [ -z "$parent" ]; then
			parent_json="null"
		else
			parent_json="\"$parent\""
		fi

		local children_json="[]"
		if [ -n "$children" ]; then
			children_json="["
			local first=true
			IFS=',' read -ra child_arr <<< "$children"
			for child in "${child_arr[@]}"; do
				child="${child// /}"
				[ -z "$child" ] && continue
				if $first; then
					children_json+="\"$child\""
					first=false
				else
					children_json+=", \"$child\""
				fi
			done
			children_json+="]"
		fi

		printf '    {\n' >> "$tmp"
		printf '      "code": "%s",\n' "$code" >> "$tmp"
		printf '      "type": "%s",\n' "$type" >> "$tmp"
		printf '      "config_version": "%s",\n' "$cver" >> "$tmp"
		printf '      "timestamp": "%s",\n' "$ts" >> "$tmp"
		printf '      "parent": %s,\n' "$parent_json" >> "$tmp"
		printf '      "children": %s,\n' "$children_json" >> "$tmp"
		printf '      "status": "%s"\n' "$nstatus" >> "$tmp"

		if (( i < count - 1 )); then
			printf '    },\n' >> "$tmp"
		else
			printf '    }\n' >> "$tmp"
		fi
	done

	printf '  ]\n}\n' >> "$tmp"
	mv -- "$tmp" "$CFG_NODES_INDEX"
	_cfg_nodes_rebuild_lookup
	_CFG_NODES_INDEX_LOADED=true
}

# ── Node CRUD ──────────────────────────────────────────────────────────

cfg_node_create() {
	local type="$1"
	local parent_code="${2:-null}"
	local config_version="${3:-}"
	local fixed_code="${4:-}"

	cfg_nodes_read_index 2>/dev/null || true

	if [ "$parent_code" = "null" ]; then
		local existing_root
		existing_root=$(cfg_nodes_get_root 2>/dev/null) || existing_root=""
		if [ -n "$existing_root" ]; then
			printf 'Error: Root node already exists. Cannot create another root.\n' >&2
			return 1
		fi
	fi

	local code
	if [ -n "$fixed_code" ]; then
		code="$fixed_code"
		if cfg_node_exists "$code" 2>/dev/null; then
			printf 'Error: Code already exists: %s\n' "$code" >&2
			return 1
		fi
	else
		code=$(cfg_generate_node_code) || return 1
	fi

	local timestamp
	timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S')

	local node_dir="$CFG_NODES_DIR/$code"
	mkdir -p "$node_dir/backup" "$node_dir/files"

	cfg_nodes_read_index 2>/dev/null || true

	_CFG_NODE_CODES+=("$code")
	_CFG_NODE_TYPES+=("$type")
	_CFG_NODE_TIMESTAMPS+=("$timestamp")
	_CFG_NODE_PARENTS+=("$parent_code")
	_CFG_NODE_CHILDREN+=("")
	_CFG_NODE_CONFIG_VERSIONS+=("$config_version")
	_CFG_NODE_STATUSES+=("active")

	if [ "$parent_code" != "null" ] && [ -n "$parent_code" ]; then
		local i
		for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
			if [ "${_CFG_NODE_CODES[$i]}" = "$parent_code" ]; then
				local existing="${_CFG_NODE_CHILDREN[$i]}"
				if [ -n "$existing" ]; then
					_CFG_NODE_CHILDREN[$i]="$existing,$code"
				else
					_CFG_NODE_CHILDREN[$i]="$code"
				fi
				break
			fi
		done
	fi

	cfg_nodes_write_index
	printf '%s' "$code"
}

# cfg_node_get <code> <field>
# Prints one stored node field; returns 1 when the code or field is unknown.
cfg_node_get() {
	local code="$1"
	local field="$2"

	cfg_nodes_read_index 2>/dev/null || return 1

	local i
	if [ -n "${_CFG_NODE_INDEX_BY_CODE[$code]+x}" ]; then
		i="${_CFG_NODE_INDEX_BY_CODE[$code]}"
	else
		return 1
	fi
	case "$field" in
		type)           printf '%s' "${_CFG_NODE_TYPES[$i]}" ;;
		timestamp)      printf '%s' "${_CFG_NODE_TIMESTAMPS[$i]}" ;;
		parent)         printf '%s' "${_CFG_NODE_PARENTS[$i]}" ;;
		children)       printf '%s' "${_CFG_NODE_CHILDREN[$i]}" ;;
		config_version) printf '%s' "${_CFG_NODE_CONFIG_VERSIONS[$i]:-}" ;;
		status)         printf '%s' "${_CFG_NODE_STATUSES[$i]:-active}" ;;
		*)              return 1 ;;
	esac
	return 0
}

# cfg_node_exists <code>
# Returns zero when a node code is present in the loaded index.
cfg_node_exists() {
	local code="$1"
	cfg_nodes_read_index 2>/dev/null || return 1
	[ -n "${_CFG_NODE_INDEX_BY_CODE[$code]+x}" ]
}

# ── HEAD Management ────────────────────────────────────────────────────

cfg_head_set() {
	local code="$1"
	printf '%s\n' "$code" > "$CFG_HEAD_FILE"
}

# cfg_head_get
# Prints the current HEAD node code, returning 1 when no valid HEAD exists.
cfg_head_get() {
	if [ ! -f "$CFG_HEAD_FILE" ]; then
		return 1
	fi
	local code
	code=$(<"$CFG_HEAD_FILE")
	code="${code%%$'\n'*}"
	code="${code#"${code%%[![:space:]]*}"}"
	code="${code%"${code##*[![:space:]]}"}"
	if [ -z "$code" ]; then
		return 1
	fi
	printf '%s' "$code"
}

# ── Deploy Status ──────────────────────────────────────────────────────

cfg_deploy_status_set() {
	local status="$1"
	printf '%s\n' "$status" > "$CFG_DEPLOY_STATUS_FILE"
}

# cfg_deploy_status_get
# Prints the deployment status, defaulting to uninstalled when absent.
cfg_deploy_status_get() {
	if [ ! -f "$CFG_DEPLOY_STATUS_FILE" ]; then
		printf 'uninstalled'
		return 0
	fi
	local status
	status=$(<"$CFG_DEPLOY_STATUS_FILE")
	status="${status%%$'\n'*}"
	status="${status#"${status%%[![:space:]]*}"}"
	status="${status%"${status##*[![:space:]]}"}"
	if [ -z "$status" ]; then
		printf 'uninstalled'
	else
		printf '%s' "$status"
	fi
}

# ── Tree Operations ────────────────────────────────────────────────────

cfg_nodes_get_root() {
	cfg_nodes_read_index 2>/dev/null || return 1

	local i
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		if [ "${_CFG_NODE_PARENTS[$i]}" = "null" ] || [ -z "${_CFG_NODE_PARENTS[$i]}" ]; then
			printf '%s' "${_CFG_NODE_CODES[$i]}"
			return 0
		fi
	done
	return 1
}

# cfg_nodes_ancestors <code>
# Prints the node's ancestor chain from the supplied code toward the root.
cfg_nodes_ancestors() {
	local code="$1"
	cfg_nodes_read_index 2>/dev/null || return 1

	local current="$code"
	while [ "$current" != "null" ] && [ -n "$current" ]; do
		printf '%s\n' "$current"
		local i found=false
		for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
			if [ "${_CFG_NODE_CODES[$i]}" = "$current" ]; then
				current="${_CFG_NODE_PARENTS[$i]}"
				found=true
				break
			fi
		done
		$found || break
	done
}

# cfg_nodes_count
# Prints the number of indexed nodes.
cfg_nodes_count() {
	cfg_nodes_read_index 2>/dev/null || { printf '0'; return; }
	printf '%d' "${#_CFG_NODE_CODES[@]}"
}

# ── Migration Detection ────────────────────────────────────────────────

cfg_nodes_needs_migration() {
	local backup_root="${1:-$HOME/.config-backup}"

	if [ -f "$backup_root/nodes/index.json" ]; then
		return 1
	fi

	local has_sessions=false
	local dir
	for dir in "$backup_root"/*/; do
		[ -d "$dir" ] || continue
		local basename="${dir%/}"
		basename="${basename##*/}"
		if [[ "$basename" =~ ^(fresh|desktop|server)-to-(fresh|desktop|server)- ]]; then
			has_sessions=true
			break
		fi
	done

	$has_sessions
}

# ── Node Status Management ─────────────────────────────────────────────

cfg_node_set_status() {
	local code="$1" status="$2"
	cfg_nodes_read_index 2>/dev/null || return 1
	local i
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		if [ "${_CFG_NODE_CODES[$i]}" = "$code" ]; then
			_CFG_NODE_STATUSES[$i]="$status"
			cfg_nodes_write_index
			return 0
		fi
	done
	return 1
}

# cfg_node_set_config_version <code> <version>
# Updates the configuration version stored on a node.
cfg_node_set_config_version() {
	local code="$1" version="$2"
	cfg_nodes_read_index 2>/dev/null || return 1
	local i
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		if [ "${_CFG_NODE_CODES[$i]}" = "$code" ]; then
			_CFG_NODE_CONFIG_VERSIONS[$i]="$version"
			cfg_nodes_write_index
			return 0
		fi
	done
	return 1
}

# cfg_node_set_parent <code> <parent_code>
# Changes a node parent and synchronizes both children lists.
cfg_node_set_parent() {
	local code="$1" new_parent="$2"
	local i
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		if [ "${_CFG_NODE_CODES[$i]}" = "$code" ]; then
			local old_parent="${_CFG_NODE_PARENTS[$i]}"
			if [ "$old_parent" != "null" ] && [ -n "$old_parent" ]; then
				local j
				for ((j = 0; j < ${#_CFG_NODE_CODES[@]}; j++)); do
					if [ "${_CFG_NODE_CODES[$j]}" = "$old_parent" ]; then
						local old_ch="${_CFG_NODE_CHILDREN[$j]}"
						local new_ch="" first=true
						if [ -n "$old_ch" ]; then
							IFS=',' read -ra carr <<< "$old_ch"
							for ch in "${carr[@]}"; do
								ch="${ch// /}"
								[ "$ch" = "$code" ] && continue
								if $first; then new_ch="$ch"; first=false
								else new_ch+=",$ch"; fi
							done
						fi
						_CFG_NODE_CHILDREN[$j]="$new_ch"
						break
					fi
				done
			fi
			_CFG_NODE_PARENTS[$i]="$new_parent"
			if [ "$new_parent" != "null" ] && [ -n "$new_parent" ]; then
				for ((j = 0; j < ${#_CFG_NODE_CODES[@]}; j++)); do
					if [ "${_CFG_NODE_CODES[$j]}" = "$new_parent" ]; then
						local existing="${_CFG_NODE_CHILDREN[$j]}"
						if [ -n "$existing" ]; then
							_CFG_NODE_CHILDREN[$j]="$existing,$code"
						else
							_CFG_NODE_CHILDREN[$j]="$code"
						fi
						break
					fi
				done
			fi
			return 0
		fi
	done
	return 1
}

# cfg_nodes_list_marked
# Prints codes for nodes marked for removal.
cfg_nodes_list_marked() {
	cfg_nodes_read_index 2>/dev/null || return 1
	local i
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		if [ "${_CFG_NODE_STATUSES[$i]}" = "marked_for_removal" ]; then
			printf '%s\n' "${_CFG_NODE_CODES[$i]}"
		fi
	done
}

# cfg_nodes_delete <code>
# Permanently deletes a non-root node and updates its parent/index metadata.
cfg_nodes_delete() {
	local code="$1"
	cfg_nodes_read_index 2>/dev/null || return 1
	local i
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		if [ "${_CFG_NODE_CODES[$i]}" = "$code" ]; then
			local parent="${_CFG_NODE_PARENTS[$i]}"
			unset '_CFG_NODE_CODES[$i]' '_CFG_NODE_TYPES[$i]' \
				  '_CFG_NODE_TIMESTAMPS[$i]' '_CFG_NODE_PARENTS[$i]' \
				  '_CFG_NODE_CHILDREN[$i]' '_CFG_NODE_CONFIG_VERSIONS[$i]' \
				  '_CFG_NODE_STATUSES[$i]'
			_CFG_NODE_CODES=("${_CFG_NODE_CODES[@]}")
			_CFG_NODE_TYPES=("${_CFG_NODE_TYPES[@]}")
			_CFG_NODE_TIMESTAMPS=("${_CFG_NODE_TIMESTAMPS[@]}")
			_CFG_NODE_PARENTS=("${_CFG_NODE_PARENTS[@]}")
			_CFG_NODE_CHILDREN=("${_CFG_NODE_CHILDREN[@]}")
			_CFG_NODE_CONFIG_VERSIONS=("${_CFG_NODE_CONFIG_VERSIONS[@]}")
			_CFG_NODE_STATUSES=("${_CFG_NODE_STATUSES[@]}")
			if [ "$parent" != "null" ] && [ -n "$parent" ]; then
				local j
				for ((j = 0; j < ${#_CFG_NODE_CODES[@]}; j++)); do
					if [ "${_CFG_NODE_CODES[$j]}" = "$parent" ]; then
						local old_children="${_CFG_NODE_CHILDREN[$j]}"
						local new_children=""
						if [ -n "$old_children" ]; then
							IFS=',' read -ra carr <<< "$old_children"
							local first=true
							for ch in "${carr[@]}"; do
								ch="${ch// /}"
								[ "$ch" = "$code" ] && continue
								if $first; then
									new_children="$ch"
									first=false
								else
									new_children+=",$ch"
								fi
							done
						fi
						_CFG_NODE_CHILDREN[$j]="$new_children"
						break
					fi
				done
			fi
			if [ "$_CFG_NODES_BATCH_MODE" != "true" ]; then
				cfg_nodes_write_index
			fi
			return 0
		fi
	done
	return 1
}

# cfg_nodes_orphaned_children <code>
# Prints active children that would be orphaned by deleting a node.
cfg_nodes_orphaned_children() {
	local code="$1"
	cfg_nodes_read_index 2>/dev/null || return 1
	local children
	children=$(cfg_node_get "$code" "children" 2>/dev/null) || return
	[ -z "$children" ] && return
	IFS=',' read -ra carr <<< "$children"
	local ch
	for ch in "${carr[@]}"; do
		ch="${ch// /}"
		[ -z "$ch" ] && continue
		printf '%s\n' "$ch"
	done
}

# ── Config Version Management ──────────────────────────────────────────

cfg_config_version_get_current() {
	local version_file="$HOME/.config-backup/CURRENT_CONFIG_VERSION"
	if [ ! -f "$version_file" ]; then
		return 1
	fi
	local ver
	ver=$(<"$version_file")
	ver="${ver%%$'\n'*}"
	ver="${ver#"${ver%%[![:space:]]*}"}"
	ver="${ver%"${ver##*[![:space:]]}"}"
	[ -z "$ver" ] && return 1
	printf '%s' "$ver"
}

# cfg_config_version_set <version>
# Stores the default category version used for new nodes.
cfg_config_version_set() {
	local version="$1"
	local version_file="$HOME/.config-backup/CURRENT_CONFIG_VERSION"
	mkdir -p "$(dirname "$version_file")"
	printf '%s\n' "$version" > "$version_file"
}

# cfg_config_versions_invalidate
# Discards cached categories-*.conf discovery data. Call after configuration
# version files are added, removed or renamed. Takes no arguments.
cfg_config_versions_invalidate() {
	_CFG_CONFIG_VERSIONS=()
	unset _CFG_CONFIG_VERSION_PREFIXES
	declare -gA _CFG_CONFIG_VERSION_PREFIXES=()
	_CFG_CONFIG_VERSIONS_LOADED=false
	_CFG_CONFIG_VERSIONS_DIR=""
}

# cfg_config_versions_load
# Scans categories-*.conf once per process and caches sorted version names and
# their legacy display prefixes. Takes no arguments; returns 0 even if empty.
cfg_config_versions_load() {
	local dir="$DOTFILES_LIB_DIR"
	if [ "$_CFG_CONFIG_VERSIONS_LOADED" = true ] && [ "$_CFG_CONFIG_VERSIONS_DIR" = "$dir" ]; then
		return 0
	fi

	local versions=()
	unset _CFG_CONFIG_VERSION_PREFIXES
	declare -gA _CFG_CONFIG_VERSION_PREFIXES=()

	local f
	for f in "$dir"/categories-*.conf; do
		[ -f "$f" ] || continue
		local base="${f##*/categories-}"
		local has_v=false
		[[ "$base" == v* ]] && has_v=true
		base="${base%.conf}"
		local file_version=""
		local lineno=0
		while IFS= read -r line && (( lineno < 10 )); do
			((++lineno))
			local trimmed="${line#"${line%%[![:space:]]*}"}"
			if [[ "$trimmed" == \#[[:space:]]*VERSION[[:space:]]*=* ]]; then
				file_version="${trimmed#*=}"
				file_version="${file_version#"${file_version%%[![:space:]]*}"}"
				file_version="${file_version%\"}"
				file_version="${file_version#\"}"
				break
			fi
			[ -n "$trimmed" ] && [[ "$trimmed" != \#* ]] && break
		done < "$f"
		local effective
		if [ -n "$file_version" ]; then
			effective="${file_version#v}"
		else
			effective="${base#v}"
		fi
		versions+=("$effective")
		if [ -z "${_CFG_CONFIG_VERSION_PREFIXES[$effective]+x}" ]; then
			if $has_v; then
				_CFG_CONFIG_VERSION_PREFIXES["$effective"]="v"
			else
				_CFG_CONFIG_VERSION_PREFIXES["$effective"]=""
			fi
		fi
	done
	if [ ${#versions[@]} -gt 0 ]; then
		mapfile -t _CFG_CONFIG_VERSIONS < <(printf '%s\n' "${versions[@]}" | sort -t. -k1,1n -k2,2n -k3,3n)
	else
		_CFG_CONFIG_VERSIONS=()
	fi
	_CFG_CONFIG_VERSIONS_LOADED=true
	_CFG_CONFIG_VERSIONS_DIR="$dir"
}

# cfg_config_version_list
# Prints discovered category version identifiers in semantic order.
cfg_config_version_list() {
	cfg_config_versions_load
	if [ ${#_CFG_CONFIG_VERSIONS[@]} -gt 0 ]; then
		printf '%s\n' "${_CFG_CONFIG_VERSIONS[@]}"
	fi
	return 0
}

# cfg_version_display_prefix <version>
# Prints the compatibility display prefix for a version identifier.
cfg_version_display_prefix() {
	local ver="$1"
	cfg_config_versions_load
	[ -n "${_CFG_CONFIG_VERSION_PREFIXES[$ver]+x}" ] || return 0
	printf '%s' "${_CFG_CONFIG_VERSION_PREFIXES[$ver]}"
}
