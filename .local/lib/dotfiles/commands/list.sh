#!/usr/bin/env bash
# commands/list.sh - node list query command for dotcfg.

if [ -n "${_DOTCFG_LIST_COMMAND_LOADED:-}" ]; then
    return 0
fi
_DOTCFG_LIST_COMMAND_LOADED=1

# cmd_list
# Prints the node index in reverse creation order. Arguments: command options
# (currently ignored); returns zero when the index is absent or displayed.
cmd_list() {
    cfg_nodes_init "$BACKUP_ROOT"

    if ! cfg_nodes_read_index 2>/dev/null || [ ${#_CFG_NODE_CODES[@]} -eq 0 ]; then
        printf 'No nodes found.\n'
        printf 'Run "dotcfg switch full", "dotcfg switch min", or "dotcfg switch macos" to create nodes.\n'
        return
    fi

    local head_code
    head_code=$(cfg_head_get 2>/dev/null) || true
    local deploy_status
    deploy_status=$(cfg_deploy_status_get)

    local deploy_width=6 type_width=10 version_width=8 status_width=10 time_width=20
    local -a markers=() types=() versions=() statuses=() times=() codes=() root_marks=()
    local i
    for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
        local code="${_CFG_NODE_CODES[$i]}"
        local type="${_CFG_NODE_TYPES[$i]}"
        local ts="${_CFG_NODE_TIMESTAMPS[$i]}"
        local display_ts
        display_ts=$(printf '%s' "$ts" | sed 's/T/ /;s/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\) \([0-9]\{2\}\):\([0-9]\{2\}\):\([0-9]\{2\}\)/\1 \2:\3:\4/')

        local marker="[ ]"
        if [ "$code" = "$head_code" ] && [ "$deploy_status" = "deployed" ]; then
            marker="[*]"
        elif [ "$code" = "$head_code" ]; then
            marker="[>]"
        fi

        local node_status="${_CFG_NODE_STATUSES[$i]:-active}"
        local display_status="$node_status"
        [ "$node_status" = "marked_for_removal" ] && display_status="[REMOVED]"

        local node_version="${_CFG_NODE_CONFIG_VERSIONS[$i]:-}"
        [ -z "$node_version" ] && node_version="-"

        local root_mark=""
        if [ "$type" = "fresh" ]; then
            root_mark=" ●"
        fi

        markers[$i]="$marker"
        types[$i]="$type"
        versions[$i]="$node_version"
        statuses[$i]="$display_status"
        times[$i]="$display_ts"
        codes[$i]="$code"
        root_marks[$i]="$root_mark"

        [ ${#marker} -le $deploy_width ] || deploy_width=${#marker}
        [ ${#type} -le $type_width ] || type_width=${#type}
        [ ${#node_version} -le $version_width ] || version_width=${#node_version}
        [ ${#display_status} -le $status_width ] || status_width=${#display_status}
        [ ${#display_ts} -le $time_width ] || time_width=${#display_ts}
    done

    printf '  %-*s %-*s %-*s %-*s %-*s %s\n' \
        "$deploy_width" "DEPLOY" "$type_width" "TYPE" "$version_width" "VERSION" \
        "$status_width" "STATUS" "$time_width" "TIME" "CODE"

    for ((i = ${#codes[@]} - 1; i >= 0; i--)); do
        printf '  %-*s %-*s %-*s %-*s %-*s %s%s\n' \
            "$deploy_width" "${markers[$i]}" "$type_width" "${types[$i]}" \
            "$version_width" "${versions[$i]}" "$status_width" "${statuses[$i]}" \
            "$time_width" "${times[$i]}" "${codes[$i]}" "${root_marks[$i]}"
    done
}
