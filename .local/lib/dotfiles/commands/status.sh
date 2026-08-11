#!/usr/bin/env bash
# commands/status.sh - status query command for dotcfg.

if [ -n "${_DOTCFG_STATUS_COMMAND_LOADED:-}" ]; then
    return 0
fi
_DOTCFG_STATUS_COMMAND_LOADED=1

# cmd_status
# Validates the repository and prints the current node, deployment state and
# available operations. Arguments: command options (currently ignored).
cmd_status() {
    cfg_validate "$GIT_DIR"
    cfg_print_validation_result "$GIT_DIR"

    local current_state
    current_state=$(cfg_detect_state "$GIT_DIR")

    cfg_nodes_init "$BACKUP_ROOT"

    local head_code=""
    head_code=$(cfg_head_get 2>/dev/null) || true

    if [ -n "$head_code" ] && cfg_nodes_read_index 2>/dev/null; then
        local i node_type="" node_ts=""
        for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
            if [ "${_CFG_NODE_CODES[$i]}" = "$head_code" ]; then
                node_type="${_CFG_NODE_TYPES[$i]}"
                node_ts="${_CFG_NODE_TIMESTAMPS[$i]}"
                break
            fi
        done

        local deploy_status
        deploy_status=$(cfg_deploy_status_get)

        printf '\nCurrent node: %s (%s)\n' "$head_code" "${node_type:-unknown}"
        if [ -n "$node_ts" ]; then
            printf 'Created: %s\n' "$node_ts"
        fi
        printf 'Deploy status: %s\n' "$deploy_status"

        local node_version node_status
        node_version=$(cfg_node_get "$head_code" "config_version" 2>/dev/null) || node_version=""
        node_status=$(cfg_node_get "$head_code" "status" 2>/dev/null) || node_status="active"
        if [ -n "$node_version" ] && [ "$node_version" != "unknown" ]; then
            printf 'Config version: %s\n' "$node_version"
        fi
        printf 'Node status: %s\n' "$node_status"

        local ancestors
        ancestors=$(cfg_nodes_ancestors "$head_code" 2>/dev/null) || true
        if [ -n "$ancestors" ]; then
            local chain=""
            local first=true
            while IFS= read -r code; do
                [ -z "$code" ] && continue
                local atype=""
                for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
                    if [ "${_CFG_NODE_CODES[$i]}" = "$code" ]; then
                        atype="${_CFG_NODE_TYPES[$i]}"
                        break
                    fi
                done
                if $first; then
                    chain="$atype"
                    first=false
                else
                    chain="$atype -> $chain"
                fi
            done <<< "$ancestors"
            printf 'Chain: %s\n' "$chain"
        fi
    else
        printf '\nCurrent state: %s\n' "$current_state"
        printf 'No nodes found. Run "dotcfg switch full", "dotcfg switch min", or "dotcfg switch macos".\n'
    fi

    printf '\nAvailable operations:\n'
    printf '  dotcfg switch full       Install all managed configuration\n'
    printf '  dotcfg switch min        Install command-line configuration\n'
    printf '  dotcfg switch macos      Install cross-platform core configuration\n'
    printf '  dotcfg deploy            Deploy current node\n'
    printf '  dotcfg undeploy          Undeploy current node\n'
    printf '  dotcfg uninstall         Return to fresh state\n'
    printf '  dotcfg list              List all nodes\n'
    printf '  dotcfg history           Show node tree\n'
}
