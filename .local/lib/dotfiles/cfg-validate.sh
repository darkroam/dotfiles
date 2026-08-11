#!/usr/bin/env bash
# cfg-validate.sh - Shared validation library for dotfiles installation scripts
# Source this file, do not execute directly.
#
# Provides:
#   cfg_validate()         - Validate .cfg repository state
#   cfg_check_updates()    - Check if updates are available
#   cfg_detect_state()     - Detect current installation state (fresh/full/min/macos)
#   cfg_should_backup_file() - Determine if a file should be backed up

# Prevent double-sourcing
if [ -n "${_CFG_VALIDATE_LOADED:-}" ]; then
    return 0
fi
_CFG_VALIDATE_LOADED=1

# Global variables set by cfg_validate
CFG_STATE=""        # missing | not_git | foreign_repo | valid
CFG_IS_OURS=""      # true | false
CFG_NEEDS_PULL=""   # true | false
CFG_REMOTE_URL=""   # Remote origin URL (if any)

# cfg_path_md5 <path>
# Hashes a symlink's stored link text, matching Git blob semantics. Regular
# files are hashed by content.
cfg_path_md5() {
    local path="$1"
    if [ -L "$path" ]; then
        readlink -n -- "$path" | md5sum | cut -d' ' -f1
    else
        md5sum < "$path" 2>/dev/null | cut -d' ' -f1
    fi
}

cfg_path_size() {
    local path="$1"
    if [ -L "$path" ]; then
        readlink -n -- "$path" | wc -c | tr -d ' '
    else
        wc -c < "$path" 2>/dev/null | tr -d ' '
    fi
}

# cfg_validate [git_dir]
# Validates the .cfg repository and sets global variables
# Returns 0 on success (check CFG_STATE for result)
cfg_validate() {
    local target="${1:-$HOME/.cfg}"

    # Initialize globals
    CFG_STATE="missing"
    CFG_IS_OURS="false"
    CFG_NEEDS_PULL="false"
    CFG_REMOTE_URL=""

    # Step 1: Check existence (handle both directory and symlink)
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        CFG_STATE="missing"
        return 0
    fi

    # Step 2: Resolve symlink if present
    local resolved="$target"
    if [ -L "$target" ]; then
        resolved=$(readlink -f "$target" 2>/dev/null) || {
            CFG_STATE="not_git"
            return 0
        }
        if [ ! -d "$resolved" ]; then
            CFG_STATE="not_git"
            return 0
        fi
    fi

    # Step 3: Check if it's a valid git repository
    if ! git --git-dir="$target/" rev-parse --git-dir >/dev/null 2>&1; then
        CFG_STATE="not_git"
        return 0
    fi

    # Step 4: Verify it's a bare repository (expected structure)
    local is_bare
    is_bare=$(git --git-dir="$target/" rev-parse --is-bare-repository 2>/dev/null)
    if [ "$is_bare" != "true" ]; then
        CFG_STATE="not_git"
        return 0
    fi

    # Step 5: Check if it has a valid HEAD
    if ! git --git-dir="$target/" rev-parse --verify HEAD >/dev/null 2>&1; then
        CFG_STATE="not_git"
        return 0
    fi

    # Step 6: Determine repository identity using dual verification
    # Method A: Check remote URL
    CFG_REMOTE_URL=$(git --git-dir="$target/" config --get remote.origin.url 2>/dev/null || true)

    # Method B: Check for signature files unique to our dotfiles repo
    local has_signature=false
    if git --git-dir="$target/" ls-tree -r --name-only HEAD 2>/dev/null | \
       grep -qx ".local/bin/dotcfg"; then
        has_signature=true
    fi

    # Method C: Normalize and compare remote URLs
    local expected_url="${DOTFILES_REPOSITORY:-git@github.com:darkroam/dotfiles.git}"

    if [ -n "$CFG_REMOTE_URL" ]; then
        # Normalize: strip .git suffix, normalize SSH/HTTPS forms
        local normalized_remote normalized_expected
        normalized_remote=$(printf '%s' "$CFG_REMOTE_URL" | sed 's/\.git$//;s|git@github.com:|https://github.com/|')
        normalized_expected=$(printf '%s' "$expected_url" | sed 's/\.git$//;s|git@github.com:|https://github.com/|')

        if [ "$normalized_remote" = "$normalized_expected" ]; then
            CFG_IS_OURS="true"
        elif [ "$has_signature" = "true" ]; then
            CFG_IS_OURS="true"
        else
            CFG_STATE="foreign_repo"
            return 0
        fi
    elif [ "$has_signature" = "true" ]; then
        # No remote but has signature files - accept as ours
        CFG_IS_OURS="true"
    else
        # No remote and no signature - likely foreign
        CFG_STATE="foreign_repo"
        return 0
    fi

    CFG_STATE="valid"
    return 0
}

# cfg_check_updates [git_dir]
# Checks if updates are available from remote
# Sets CFG_NEEDS_PULL=true if remote has new commits
cfg_check_updates() {
    local target="${1:-$HOME/.cfg}"
    CFG_NEEDS_PULL="false"

    # Only check if we have a remote
    local remote_url
    remote_url=$(git --git-dir="$target/" config --get remote.origin.url 2>/dev/null) || return 0

    # Try to fetch (with timeout to avoid hanging)
    if git --git-dir="$target/" fetch --dry-run origin 2>/dev/null; then
        local local_head remote_head
        local_head=$(git --git-dir="$target/" rev-parse HEAD 2>/dev/null)
        remote_head=$(git --git-dir="$target/" rev-parse origin/HEAD 2>/dev/null || \
                      git --git-dir="$target/" rev-parse origin/master 2>/dev/null || \
                      git --git-dir="$target/" rev-parse origin/main 2>/dev/null)
        if [ -n "$local_head" ] && [ -n "$remote_head" ] && [ "$local_head" != "$remote_head" ]; then
            CFG_NEEDS_PULL="true"
        fi
    fi
}

# _cfg_load_category_state_metadata [backup_root]
# Loads the selected category version when the category library is available.
# Returns 0 when metadata was loaded or no category library is present.
_cfg_load_category_state_metadata() {
    local backup_root="$1"
    declare -F cfg_categories_load >/dev/null 2>&1 || return 0

    local version=""
    if [ -f "$backup_root/CURRENT_CONFIG_VERSION" ]; then
        version=$(<"$backup_root/CURRENT_CONFIG_VERSION")
        version="${version%%$'\n'*}"
        version="${version#"${version%%[![:space:]]*}"}"
        version="${version%"${version##*[![:space:]]}"}"
    fi

    if [ -n "$version" ]; then
        cfg_categories_load "$version" >/dev/null 2>&1 || cfg_categories_load >/dev/null 2>&1 || true
    else
        cfg_categories_load >/dev/null 2>&1 || true
    fi
}

# cfg_detect_state [git_dir]
# Detects the canonical installation state. Node metadata is authoritative;
# category metadata drives aliases and indicators when available; legacy file
# detection remains the final compatibility fallback.
cfg_detect_state() {
    local git_dir="${1:-$HOME/.cfg}"

    if [ ! -d "$git_dir" ] && [ ! -L "$git_dir" ]; then
        echo "fresh"
        return
    fi

    local backup_root="${DOTCFG_BACKUP_ROOT:-$HOME/.config-backup}"
    _cfg_load_category_state_metadata "$backup_root"

    if declare -F cfg_nodes_init >/dev/null 2>&1 && \
       [ -f "$backup_root/HEAD" ] && [ -f "$backup_root/nodes/index.json" ]; then
        cfg_nodes_init "$backup_root"
        local head_code node_type
        head_code=$(cfg_head_get 2>/dev/null) || head_code=""
        if [ -n "$head_code" ]; then
            node_type=$(cfg_node_get "$head_code" type 2>/dev/null) || node_type=""
            if [ -n "$node_type" ]; then
                if declare -F cfg_category_canonical_name >/dev/null 2>&1; then
                    cfg_category_canonical_name "$node_type"
                else
                    case "$node_type" in
                        desktop) echo "full" ;;
                        server) echo "min" ;;
                        *) echo "$node_type" ;;
                    esac
                fi
                return
            fi
        fi
    fi

    local indicator indicator_category
    if declare -p CFG_STATE_INDICATOR_PATHS >/dev/null 2>&1 && \
       [ ${#CFG_STATE_INDICATOR_PATHS[@]} -gt 0 ]; then
        for indicator in "${CFG_STATE_INDICATOR_PATHS[@]}"; do
            indicator_category=$(cfg_state_indicator_category "$indicator" 2>/dev/null) || indicator_category="full"
            if [ -e "$HOME/$indicator" ] || [ -L "$HOME/$indicator" ]; then
                echo "$indicator_category"
                return
            fi
        done
    else
        for indicator in ".xinitrc" ".xprofile" ".config/x11/xinitrc"; do
            if [ -e "$HOME/$indicator" ] || [ -L "$HOME/$indicator" ]; then
                echo "full"
                return
            fi
        done
    fi

    if declare -F cfg_state_default_category >/dev/null 2>&1; then
        cfg_state_default_category
        return
    fi

    for indicator in ".xinitrc" ".xprofile" ".config/x11/xinitrc"; do
        if [ -e "$HOME/$indicator" ] || [ -L "$HOME/$indicator" ]; then
            echo "full"
            return
        fi
    done

    echo "min"
}

# cfg_should_backup_file [git_dir] [relative_path]
# Determines if a file should be backed up before installation
# Returns 0 if should backup, 1 if should skip
cfg_should_backup_file() {
    local git_dir="$1"
    local relative_path="$2"
    local full_path="$HOME/$relative_path"

    # Check if file exists
    if [ ! -e "$full_path" ] && [ ! -L "$full_path" ]; then
        return 1  # File doesn't exist, no backup needed
    fi

    # Check if tracked in repository
    if git --git-dir="$git_dir/" --work-tree="$HOME" ls-tree -r --name-only HEAD 2>/dev/null | grep -qx "$relative_path"; then
        # File is tracked, compare content
        local repo_hash local_hash
        repo_hash=$(git --git-dir="$git_dir/" --work-tree="$HOME" show HEAD:"$relative_path" 2>/dev/null | md5sum | cut -d' ' -f1)
        local_hash=$(cfg_path_md5 "$full_path")

        if [ "$repo_hash" = "$local_hash" ]; then
            return 1  # Content identical, no backup needed
        else
            return 0  # Content differs, backup needed
        fi
    else
        return 0  # Untracked file, backup needed
    fi
}

# cfg_print_validation_result [git_dir]
# Prints human-readable validation result
cfg_print_validation_result() {
    local git_dir="${1:-$HOME/.cfg}"

    case "$CFG_STATE" in
        missing)
            printf 'No existing installation found at %s\n' "$git_dir"
            ;;
        not_git)
            printf 'ERROR: %s exists but is not a valid git repository\n' "$git_dir"
            ;;
        foreign_repo)
            printf 'ERROR: %s is a git repository but not the dotfiles repository\n' "$git_dir"
            if [ -n "$CFG_REMOTE_URL" ]; then
                printf '  Remote URL: %s\n' "$CFG_REMOTE_URL"
            fi
            ;;
        valid)
            printf 'Valid dotfiles repository found at %s\n' "$git_dir"
            if [ -n "$CFG_REMOTE_URL" ]; then
                printf '  Remote: %s\n' "$CFG_REMOTE_URL"
            else
                printf '  Remote: (not configured)\n'
            fi
            if [ "$CFG_IS_OURS" = "true" ]; then
                printf '  Identity: Verified as dotfiles repository\n'
            fi
            ;;
    esac
}
