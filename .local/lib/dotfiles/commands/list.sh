#!/usr/bin/env bash
# commands/list.sh - node list query command for dotcfg.

if [ -n "${_DOTCFG_LIST_COMMAND_LOADED:-}" ]; then
    return 0
fi
_DOTCFG_LIST_COMMAND_LOADED=1

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

    printf '  %-6s %-10s %-8s %-10s %-20s %s\n' "DEPLOY" "TYPE" "VERSION" "STATUS" "TIME" "CODE"

    local i
    for ((i = ${#_CFG_NODE_CODES[@]} - 1; i >= 0; i--)); do
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

        printf '  %-6s %-10s %-8s %-10s %-20s %s%s\n' "$marker" "$type" "$node_version" "$display_status" "$display_ts" "$code" "$root_mark"
    done
}
