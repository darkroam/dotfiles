#!/usr/bin/env bash
# commands/history.sh - graph-style node history command for dotcfg.
# shellcheck disable=SC2034  # nameref output arrays are consumed by renderers.

if [ -n "${_DOTCFG_HISTORY_COMMAND_LOADED:-}" ]; then
    return 0
fi
_DOTCFG_HISTORY_COMMAND_LOADED=1

# cmd_history
# Renders the node transition tree using the current HEAD and deploy state.
# Arguments: command options (currently ignored); returns the renderer status.
cmd_history() {
    cfg_nodes_init "$BACKUP_ROOT"

    if ! cfg_nodes_read_index 2>/dev/null || [ ${#_CFG_NODE_CODES[@]} -eq 0 ]; then
        printf 'No history found.\n'
        return
    fi

    local head_code=""
    head_code=$(cfg_head_get 2>/dev/null) || true
    local deploy_status
    deploy_status=$(cfg_deploy_status_get)

    _history_init_colors

    local -a main_line=()
    _history_compute_main_line main_line

	# shellcheck disable=SC2034  # Arrays are populated through nameref arguments.
	local -A on_main_line=()
    local c
    for c in "${main_line[@]}"; do on_main_line["$c"]=1; done

	# shellcheck disable=SC2034  # Arrays are populated through nameref arguments.
	local -a disp_codes=() disp_lanes=() disp_types=()
    _history_build_display main_line on_main_line disp_codes disp_lanes disp_types

    _history_render disp_codes disp_lanes disp_types "$head_code" "$deploy_status"
}

_history_init_colors() {
    _C_GREEN="" _C_YELLOW="" _C_GRAY="" _C_BLUE="" _C_RESET=""
    if [ -t 1 ] && tput colors >/dev/null 2>&1; then
        local ncolors
        ncolors=$(tput colors 2>/dev/null) || ncolors=0
        if (( ncolors >= 8 )); then
            _C_GREEN=$'\033[32m'
            _C_YELLOW=$'\033[33m'
            _C_GRAY=$'\033[90m'
            _C_BLUE=$'\033[34m'
            _C_RESET=$'\033[0m'
        fi
    fi
}

_history_compute_main_line() {
    local -n _ml_ref=$1
    local newest_code="" newest_ts=""
    local i
    for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
        local code="${_CFG_NODE_CODES[$i]}"
        local children="${_CFG_NODE_CHILDREN[$i]}"
        local ts="${_CFG_NODE_TIMESTAMPS[$i]}"
        if [ -z "$children" ]; then
            if [ -z "$newest_ts" ] || [[ "$ts" > "$newest_ts" ]]; then
                newest_code="$code"
                newest_ts="$ts"
            fi
        fi
    done

    if [ -z "$newest_code" ]; then
        newest_code=$(cfg_head_get 2>/dev/null) || newest_code="${_CFG_NODE_CODES[${#_CFG_NODE_CODES[@]}-1]}"
    fi

    local -a chain=()
    local current="$newest_code"
    while [ -n "$current" ] && [ "$current" != "null" ]; do
        chain+=("$current")
        current=$(cfg_node_get "$current" "parent" 2>/dev/null) || break
    done

    local j
    for ((j = ${#chain[@]} - 1; j >= 0; j--)); do
        _ml_ref+=("${chain[$j]}")
    done
}

_history_collect_descendants() {
    local root_code="$1"
    local -n _desc_ref=$2
    local -a stack=("$root_code")
    local -a all=()

    while ((${#stack[@]} > 0)); do
        local node="${stack[-1]}"
        unset 'stack[-1]'
        stack=("${stack[@]+"${stack[@]}"}")
        all+=("$node")
        local children
        children=$(cfg_node_get "$node" "children" 2>/dev/null) || true
        if [ -n "$children" ]; then
            IFS=',' read -ra carr <<< "$children"
            local ch
            for ch in "${carr[@]}"; do
                ch="${ch// /}"
                [ -z "$ch" ] && continue
                stack+=("$ch")
            done
        fi
    done

	local i j
    for ((i = 0; i < ${#all[@]}; i++)); do
        for ((j = i + 1; j < ${#all[@]}; j++)); do
            local ts_i ts_j
            ts_i=$(cfg_node_get "${all[$i]}" "timestamp" 2>/dev/null) || true
            ts_j=$(cfg_node_get "${all[$j]}" "timestamp" 2>/dev/null) || true
            if [[ "$ts_j" > "$ts_i" ]]; then
                local tmp="${all[$i]}"
                all[$i]="${all[$j]}"
                all[$j]="$tmp"
            fi
        done
    done

    for i in "${all[@]}"; do _desc_ref+=("$i"); done
}

_history_build_display() {
    local -n _ml=$1
    local -n _oml=$2
    local -n _dc=$3
    local -n _dl=$4
    local -n _dt=$5

    local main_count=${#_ml[@]}
	local mi

    for ((mi = main_count - 1; mi >= 0; mi--)); do
        local code="${_ml[$mi]}"
        _dc+=("$code")
        _dl+=(0)
        _dt+=("node")

        local children
        children=$(cfg_node_get "$code" "children" 2>/dev/null) || true

        local -a side_roots=()
        if [ -n "$children" ]; then
            IFS=',' read -ra carr <<< "$children"
            local ch
            for ch in "${carr[@]}"; do
                ch="${ch// /}"
                [ -z "$ch" ] && continue
                if [ -z "${_oml[$ch]+x}" ]; then
                    side_roots+=("$ch")
                fi
            done
        fi

        local had_side_branches=false

        if ((${#side_roots[@]} > 0)); then
            had_side_branches=true
            local sr
            for sr in "${side_roots[@]}"; do
                _dc+=("__fork__")
                _dl+=(0)
                _dt+=("fork")

                local -a descendants=()
                _history_collect_descendants "$sr" descendants

                local di
                for ((di = 0; di < ${#descendants[@]}; di++)); do
                    _dc+=("${descendants[$di]}")
                    _dl+=(1)
                    _dt+=("node")

                    if ((di < ${#descendants[@]} - 1)); then
                        _dc+=("__connect__")
                        _dl+=(1)
                        _dt+=("side_connect")
                    fi
                done

                _dc+=("__merge__")
                _dl+=(0)
                _dt+=("merge")
            done
        fi

        if ((mi > 0)) && ! $had_side_branches; then
            _dc+=("__connect__")
            _dl+=(0)
            _dt+=("connect")
        fi
    done
}

_history_render() {
    local -n _rc=$1
    local -n _rl=$2
    local -n _rt=$3
    local head_code="$4"
    local deploy_status="$5"

    local count=${#_rc[@]}
    local i

    for ((i = 0; i < count; i++)); do
        local code="${_rc[$i]}"
        local lane="${_rl[$i]}"
        local ltype="${_rt[$i]}"

        case "$ltype" in
            node)
                local type ts display_ts
                type=$(cfg_node_get "$code" "type" 2>/dev/null) || continue
                ts=$(cfg_node_get "$code" "timestamp" 2>/dev/null) || continue
                display_ts="${ts/T/ }"

                local marker="o"
                local head_label=""
				if [ "$code" = "$head_code" ]; then
					marker="*"
					if [ "$deploy_status" = "deployed" ]; then
                        head_label="  ${_C_GREEN}<- HEAD${_C_RESET}"
                    else
                        head_label="  ${_C_GREEN}<- HEAD${_C_RESET} ${_C_GRAY}[uninstalled]${_C_RESET}"
                    fi
                fi

                local root_tag=""
                if [ "$type" = "fresh" ]; then
                    root_tag=" ${_C_GRAY}[root]${_C_RESET}"
                    if [ "$code" != "$head_code" ]; then
						marker="●"
                    fi
                fi

                local status_str=""
                if [ "$code" = "$head_code" ]; then
                    if [ "$deploy_status" = "deployed" ]; then
                        status_str=" ${_C_YELLOW}[deployed]${_C_RESET}"
                    fi
                fi

                local version_tag=""
                local ver
                ver=$(cfg_node_get "$code" "config_version" 2>/dev/null) || ver=""
                if [ -n "$ver" ] && [ "$ver" != "unknown" ]; then
                    local version_prefix
                    version_prefix=$(cfg_version_display_prefix "$ver")
                    version_tag=" ${version_prefix}${ver}"
                fi

                local removed_tag=""
                local nstatus
                nstatus=$(cfg_node_get "$code" "status" 2>/dev/null) || nstatus="active"
                if [ "$nstatus" = "marked_for_removal" ]; then
                    removed_tag=" ${_C_YELLOW}[REMOVED]${_C_RESET}"
                fi

                local prefix
                prefix=$(_history_graph_prefix "$lane" "node" "$ltype" "$marker")

                printf '%s%s%s %s  %-7s  %s%s%s%s%s%s\n' \
                    "$_C_BLUE" "$prefix" "$_C_RESET" \
                    "$code" "$type" "$display_ts" "$status_str" "$version_tag" "$removed_tag" "$root_tag" "$head_label"
                ;;
            connect)
                local prefix
                prefix=$(_history_graph_prefix 0 "connect" "$ltype")
                printf '%s%s%s\n' "$_C_BLUE" "$prefix" "$_C_RESET"
                ;;
            fork)
                local prefix
                prefix=$(_history_graph_prefix "$lane" "fork" "$ltype")
                printf '%s%s%s\n' "$_C_BLUE" "$prefix" "$_C_RESET"
                ;;
            merge)
                local prefix
                prefix=$(_history_graph_prefix "$lane" "merge" "$ltype")
                printf '%s%s%s\n' "$_C_BLUE" "$prefix" "$_C_RESET"
                ;;
            side_connect)
                local prefix
                prefix=$(_history_graph_prefix "$lane" "side_connect" "$ltype")
                printf '%s%s%s\n' "$_C_BLUE" "$prefix" "$_C_RESET"
                ;;
        esac
    done
}

_history_graph_prefix() {
    local node_lane="$1"
	local line_type="$3"
    local marker="${4:-*}"

    local prefix=""
    local lane

    case "$line_type" in
        node)
            for ((lane = 0; lane < node_lane; lane++)); do
                prefix+="| "
            done
            prefix+="${marker} "
            ;;
        connect)
            for ((lane = 0; lane <= 0; lane++)); do
                prefix+="| "
            done
            ;;
        fork)
            for ((lane = 0; lane < node_lane; lane++)); do
                prefix+="| "
            done
            prefix+="|\\"
            ;;
        merge)
            for ((lane = 0; lane < node_lane; lane++)); do
                prefix+="| "
            done
            prefix+="|/"
            ;;
        side_connect)
            for ((lane = 0; lane <= node_lane; lane++)); do
                prefix+="| "
            done
            ;;
    esac

    printf '%s' "$prefix"
}
