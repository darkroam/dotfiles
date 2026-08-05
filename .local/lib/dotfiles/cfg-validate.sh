#!/usr/bin/env bash
# cfg-validate.sh - Shared validation library for dotfiles installation scripts
# Source this file, do not execute directly.
#
# Provides:
#   cfg_validate()         - Validate .cfg repository state
#   cfg_check_updates()    - Check if updates are available
#   cfg_detect_state()     - Detect current installation state (fresh/desktop/server)
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
       grep -qx ".local/bin/install.sh"; then
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

# cfg_detect_state [git_dir]
# Detects current installation state: fresh, desktop, or server
cfg_detect_state() {
    local git_dir="${1:-$HOME/.cfg}"

    if [ ! -d "$git_dir" ] && [ ! -L "$git_dir" ]; then
        echo "fresh"
        return
    fi

    # Check for desktop-specific files
    local desktop_indicators=(.xinitrc .xprofile .config/x11)
    for indicator in "${desktop_indicators[@]}"; do
        if [ -e "$HOME/$indicator" ] || [ -L "$HOME/$indicator" ]; then
            echo "desktop"
            return
        fi
    done

    # If .cfg exists but no desktop files, assume server mode
    echo "server"
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
        local_hash=$(md5sum < "$full_path" 2>/dev/null | cut -d' ' -f1)

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
