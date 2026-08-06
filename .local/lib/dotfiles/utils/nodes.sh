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

# ── Initialization ─────────────────────────────────────────────────────

cfg_nodes_init() {
	local backup_root="${1:-$HOME/.config-backup}"
	CFG_NODES_DIR="$backup_root/nodes"
	CFG_NODES_INDEX="$CFG_NODES_DIR/index.json"
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
	_CFG_NODE_CODES=()
	_CFG_NODE_TYPES=()
	_CFG_NODE_TIMESTAMPS=()
	_CFG_NODE_PARENTS=()
	_CFG_NODE_CHILDREN=()

	if [ ! -f "$CFG_NODES_INDEX" ]; then
		return 1
	fi

	local parsed
	parsed=$(awk '
		BEGIN { depth=0; in_node=0; code=""; type=""; ts=""; parent="null"; children="" }
		/\{/ {
			depth++
			if (depth == 2) {
				in_node=1; code=""; type=""; ts=""; parent="null"; children=""
			}
			next
		}
		/\}/ {
			if (depth == 2 && in_node) {
				if (code != "") {
					gsub(/"/, "", children)
					print code "\t" type "\t" ts "\t" parent "\t" children
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
	' "$CFG_NODES_INDEX")

	if [ -z "$parsed" ]; then
		return 0
	fi

	while IFS=$'\t' read -r _nr_code _nr_type _nr_ts _nr_parent _nr_children; do
		_CFG_NODE_CODES+=("$_nr_code")
		_CFG_NODE_TYPES+=("$_nr_type")
		_CFG_NODE_TIMESTAMPS+=("$_nr_ts")
		_CFG_NODE_PARENTS+=("$_nr_parent")
		_CFG_NODE_CHILDREN+=("$_nr_children")
	done <<< "$parsed"
}

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
		printf '      "timestamp": "%s",\n' "$ts" >> "$tmp"
		printf '      "parent": %s,\n' "$parent_json" >> "$tmp"
		printf '      "children": %s\n' "$children_json" >> "$tmp"

		if (( i < count - 1 )); then
			printf '    },\n' >> "$tmp"
		else
			printf '    }\n' >> "$tmp"
		fi
	done

	printf '  ]\n}\n' >> "$tmp"
	mv -- "$tmp" "$CFG_NODES_INDEX"
}

# ── Node CRUD ──────────────────────────────────────────────────────────

cfg_node_create() {
	local type="$1"
	local parent_code="${2:-null}"

	local code
	code=$(cfg_generate_node_code) || return 1

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

cfg_node_get() {
	local code="$1"
	local field="$2"

	cfg_nodes_read_index 2>/dev/null || return 1

	local i
	for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
		if [ "${_CFG_NODE_CODES[$i]}" = "$code" ]; then
			case "$field" in
				type)      printf '%s' "${_CFG_NODE_TYPES[$i]}" ;;
				timestamp) printf '%s' "${_CFG_NODE_TIMESTAMPS[$i]}" ;;
				parent)    printf '%s' "${_CFG_NODE_PARENTS[$i]}" ;;
				children)  printf '%s' "${_CFG_NODE_CHILDREN[$i]}" ;;
				*)         return 1 ;;
			esac
			return 0
		fi
	done
	return 1
}

cfg_node_exists() {
	local code="$1"

	if [ ${#_CFG_NODE_CODES[@]} -gt 0 ]; then
		local c
		for c in "${_CFG_NODE_CODES[@]}"; do
			[ "$c" = "$code" ] && return 0
		done
		return 1
	fi

	if [ ! -f "$CFG_NODES_INDEX" ]; then
		return 1
	fi

	grep -q "\"code\"[[:space:]]*:[[:space:]]*\"$code\"" "$CFG_NODES_INDEX" 2>/dev/null
}

# ── HEAD Management ────────────────────────────────────────────────────

cfg_head_set() {
	local code="$1"
	printf '%s\n' "$code" > "$CFG_HEAD_FILE"
}

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
