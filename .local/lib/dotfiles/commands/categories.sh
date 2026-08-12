#!/usr/bin/env bash
# commands/categories.sh - configuration version command for dotcfg.

if [ -n "${_DOTCFG_CATEGORIES_COMMAND_LOADED:-}" ]; then
    return 0
fi
_DOTCFG_CATEGORIES_COMMAND_LOADED=1

# cmd_categories <list|current|show|switch|remove> [argument]
# Displays or changes versioned category metadata while preserving the CLI
# output and confirmation behavior. Returns the selected operation's status.
cmd_categories() {
    local subcmd="${1:-list}"
    shift || true

    case "$subcmd" in
        list)
            cfg_config_versions_load
            local versions
            versions=$(cfg_config_version_list 2>/dev/null) || true
            if [ -z "$versions" ]; then
                printf 'No config versions found.\n'
                printf 'Using built-in default categories.\n'
                return
            fi
            local current_ver
            current_ver=$(cfg_config_version_get_current 2>/dev/null) || current_ver=""
            [ -z "$current_ver" ] && current_ver=$(cfg_config_version_latest 2>/dev/null) || true

            printf 'Available configuration versions:\n'
            while IFS= read -r ver; do
                [ -z "$ver" ] && continue
                cfg_config_version_read "$ver" >/dev/null 2>&1 || continue
                local cats=()
                local c
                cfg_categories_load "$ver"
                for c in $(cfg_categories_list); do
                    [ "$c" = "full" ] && continue
                    cats+=("$c")
                done
                local tag marker="" tag_gap cats_text
                tag=$(cfg_config_get_tag "$ver" 2>/dev/null) || tag="stable"
                [ "$tag" = "test" ] && marker="   [TEST]"
                [ "$tag" = "experimental" ] && marker="   [EXPERIMENTAL]"
                printf -v tag_gap '%*s' "$((9 - ${#tag} > 0 ? 9 - ${#tag} : 1))" ''
                printf -v cats_text '%s, ' "${cats[@]}"
                cats_text="${cats_text%, }"
                printf '  %-7s (%s)%s%d categories: %s%s\n' \
                    "$ver" "$tag" "$tag_gap" "${#cats[@]}" "$cats_text" "$marker"
            done <<< "$versions"

            local current_tag
            if current_tag=$(cfg_config_get_tag "$current_ver" 2>/dev/null); then
                printf '\nCurrent version: %s (%s)\n' "$current_ver" "$current_tag"
            else
                printf '\nCurrent version: %s\n' "$current_ver"
            fi

            if cfg_nodes_read_index 2>/dev/null && [ ${#_CFG_NODE_CODES[@]} -gt 0 ]; then
                declare -A ver_nodes=()
                local i
                for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
                    local nv="${_CFG_NODE_CONFIG_VERSIONS[$i]:-}"
                    [ -z "$nv" ] || [ "$nv" = "unknown" ] && continue
                    if [ -n "${ver_nodes[$nv]+x}" ]; then
                        ver_nodes[$nv]="${ver_nodes[$nv]} ${_CFG_NODE_CODES[$i]}"
                    else
                        ver_nodes[$nv]="${_CFG_NODE_CODES[$i]}"
                    fi
                done
                if [ ${#ver_nodes[@]} -gt 0 ]; then
                    printf '\nNodes using each version:\n'
                    for ver in $(printf '%s\n' "${!ver_nodes[@]}" | sort); do
                        local nodes_str="${ver_nodes[$ver]}"
					local -a narr=()
					read -r -a narr <<< "$nodes_str"
                        local nodes_text
                        printf -v nodes_text '%s, ' "${narr[@]}"
                        nodes_text="${nodes_text%, }"
                        printf '  %s: %s (%d node%s)\n' "$ver" "$nodes_text" \
                            "${#narr[@]}" "$([ ${#narr[@]} -gt 1 ] && printf 's')"
                    done
                fi
            fi
            ;;
        current)
            local current_ver
            current_ver=$(cfg_config_version_get_current 2>/dev/null) || current_ver=""
            if [ -n "$current_ver" ]; then
                local cp
                cp=$(cfg_version_display_prefix "$current_ver")
                local tag
                if tag=$(cfg_config_get_tag "$current_ver" 2>/dev/null); then
                    printf 'Current version: %s%s (%s)\n' "$cp" "$current_ver" "$tag"
                else
                    printf 'Current version: %s%s\n' "$cp" "$current_ver"
                fi
                printf 'New nodes will use %s%s by default.\n' "$cp" "$current_ver"
            else
                printf 'No current version set.\n'
                printf 'Using latest available version automatically.\n'
            fi
            ;;
        show)
            local ver="${1:-}"
            if [ -z "$ver" ]; then
                ver=$(cfg_config_version_latest 2>/dev/null) || ver=""
                [ -z "$ver" ] && { printf 'No config versions found.\n'; return; }
            fi
            cfg_config_version_read "$ver" >/dev/null 2>&1 || {
                printf 'Error: config version "%s" not found\n' "$ver" >&2
                exit 1
            }
            cfg_config_version_info "$ver"
            printf '\nCategories:\n'
            cfg_categories_load "$ver"
            local cat
            for cat in $(cfg_categories_list); do
                if cfg_category_exists "$cat"; then
                    if [ "$cat" = "full" ]; then
                        printf '  %-15s %s\n' "$cat" '(dynamic, all tracked files)'
                    else
                        local count
                        count=$(cfg_category_get_files "$cat" | wc -l)
                        printf '  %-15s %d files\n' "$cat" "$count"
                    fi
                fi
            done
            ;;
        switch)
            local ver="${1:-}"
            [ -z "$ver" ] && { printf 'Error: config version is required.\n' >&2; exit 1; }
            cfg_config_version_read "$ver" >/dev/null 2>&1 || {
                printf 'Error: config version "%s" not found\n' "$ver" >&2
                exit 1
            }
            local target_tag
            target_tag=$(cfg_config_get_tag "$ver" 2>/dev/null) || target_tag="stable"
            if [ "$target_tag" = "test" ]; then
                printf 'Switching to test version %s%s. Use with caution.\n' "$(cfg_version_display_prefix "$ver")" "$ver"
            elif [ "$target_tag" = "experimental" ]; then
                printf 'Switching to experimental version %s%s. Use with caution.\n' "$(cfg_version_display_prefix "$ver")" "$ver"
            fi
            local old_ver
            old_ver=$(cfg_config_version_get_current 2>/dev/null) || old_ver=""
            [ -z "$old_ver" ] && old_ver=$(cfg_config_version_latest 2>/dev/null) || true

            if [ -n "$old_ver" ] && [ "$old_ver" != "$ver" ]; then
                local old_p new_p
                old_p=$(cfg_version_display_prefix "$old_ver")
                new_p=$(cfg_version_display_prefix "$ver")
                printf 'Switching from %s%s to %s%s...\n' "$old_p" "$old_ver" "$new_p" "$ver"
                if cfg_nodes_read_index 2>/dev/null && [ ${#_CFG_NODE_CODES[@]} -gt 0 ]; then
                    local found_old=false
                    local i
                    for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
                        if [ "${_CFG_NODE_CONFIG_VERSIONS[$i]:-}" = "$old_ver" ]; then
                            found_old=true
                            break
                        fi
                    done
                    if $found_old; then
                        printf 'Warning: Some nodes use %s%s. They will continue to use %s%s on recovery.\n' "$old_p" "$old_ver" "$old_p" "$old_ver"
                    fi
                fi
            fi

            cfg_config_version_set "$ver"
            local sw_p
            sw_p=$(cfg_version_display_prefix "$ver")
            printf 'Current version set to %s%s.\n' "$sw_p" "$ver"
            printf 'New nodes will use %s%s by default.\n' "$sw_p" "$ver"
            ;;
        remove)
            local ver="${1:-}"
            [ -z "$ver" ] && { printf 'Error: config version is required.\n' >&2; exit 1; }
            cfg_config_version_read "$ver" >/dev/null 2>&1 || {
                printf 'Error: config version "%s" not found\n' "$ver" >&2
                exit 1
            }
            local tag version_file
            tag=$(cfg_config_get_tag "$ver" 2>/dev/null) || tag="stable"
            version_file="$DOTFILES_LIB_DIR/categories-${ver}.conf"
            [ -f "$version_file" ] || version_file="$DOTFILES_LIB_DIR/categories-v${ver}.conf"
            if [ "$tag" = "test" ]; then
                printf 'Warning: This is a TEST configuration version (TAG=test).\n' >&2
            elif [ "$tag" = "experimental" ]; then
                printf 'Warning: This is an EXPERIMENTAL configuration version (TAG=experimental).\n' >&2
            fi

            local -a version_nodes=()
            if cfg_nodes_read_index 2>/dev/null; then
                local i
                for ((i = 0; i < ${#_CFG_NODE_CODES[@]}; i++)); do
                    if [ "${_CFG_NODE_CONFIG_VERSIONS[$i]:-}" = "$ver" ]; then
                        version_nodes+=("${_CFG_NODE_CODES[$i]}")
                    fi
                done
            fi
            if [ ${#version_nodes[@]} -gt 0 ]; then
                local nodes_text
                printf -v nodes_text '%s, ' "${version_nodes[@]}"
                nodes_text="${nodes_text%, }"
                printf 'Nodes using this version: %s (%d node%s)\n' \
                    "$nodes_text" "${#version_nodes[@]}" \
                    "$([ ${#version_nodes[@]} -gt 1 ] && printf 's')"
                printf 'Deleting this version may affect these nodes.\n' >&2
            else
                printf 'Nodes using this version: none\n'
            fi
            printf 'Continue? (y/N): '
            local answer
            read -r answer || answer=""
            case "$answer" in
                y|Y|yes|YES) ;;
                *) printf 'Cancelled.\n'; return 0 ;;
            esac
            rm -f -- "$version_file"
            cfg_config_versions_invalidate
            cfg_categories_invalidate
            printf 'Configuration version %s removed: %s\n' "$ver" "$version_file"
            ;;
        *)
            printf 'Error: unknown categories subcommand "%s".\n' "$subcmd" >&2
            exit 1
            ;;
    esac
}
