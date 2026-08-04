#!/usr/bin/env bash
# state-machine-tester.sh - State machine test executor for configuration scripts
# Tests all 9 state transitions: fresh↔desktop↔server
#
# ── 安全约束 ─────────────────────────────────────────────────────────
# 1. 禁止删除 $REAL_HOME/.cfg 或 $REAL_HOME 下的任何内容。
# 2. 禁止在 $REAL_HOME 根目录创建或修改文件。
# 3. 所有写操作（rm -rf、git init、文件创建）仅限 /tmp/ 下的临时测试目录。
# 4. cleanup 函数必须校验目标路径以 /tmp/ 开头且不等于 $REAL_HOME。
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/generate-conflicts.sh"
source "$SCRIPT_DIR/helpers.sh"

# Test configuration
TEST_TIMEOUT=300  # 5 minutes timeout
TEST_LOG_DIR=""
MIRROR_DIR=""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Save the real HOME once at startup, before any test overrides it
REAL_HOME="${REAL_HOME:-$HOME}"

# Initialize test environment
setup_test_env() {
    local test_name="$1"
    TEST_LOG_DIR=$(mktemp -d /tmp/cfg-test-log.XXXXXX)
    local test_home=$(mktemp -d /tmp/cfg-test-home.XXXXXX)

    export HOME="$test_home"

    # Isolate XDG and git config from the real environment
    export XDG_CONFIG_HOME="$test_home/.config"
    export XDG_DATA_HOME="$test_home/.local/share"
    export XDG_CACHE_HOME="$test_home/.cache"
    export GIT_CONFIG_GLOBAL="$test_home/.gitconfig"
    export GIT_CONFIG_SYSTEM=/dev/null

    # Point to the real shared library so tests exercise it, not the inline fallback
    export DOTFILES_LIB_DIR="$REAL_HOME/.local/share/dotfiles-lib"

    # Configure Git repository source
    if [ "${USE_REAL_REMOTE:-false}" = "true" ]; then
        # Use real remote repository
        export DOTFILES_REPOSITORY="${DOTFILES_REPOSITORY:-git@github.com:darkroam/dotfiles.git}"
        log_info "Using real remote repository"

        # Copy SSH keys from the REAL home (not the overridden one)
        if [ -d "$REAL_HOME/.ssh" ]; then
            cp -r "$REAL_HOME/.ssh" "$test_home/.ssh" 2>/dev/null || true
        fi
    else
        # Use local Git mirror
        setup_local_git_mirror
        log_info "Using local Git mirror: $DOTFILES_REPOSITORY"
    fi

    # Create basic shell environment
    touch "$test_home/.bashrc" "$test_home/.zshrc"

    log_info "Test environment created: $test_home"
    log_info "Log directory: $TEST_LOG_DIR"
}

# Setup local Git mirror
setup_local_git_mirror() {
    local mirror_base="/tmp/cfg-git-mirror"
    mkdir -p "$mirror_base"
    
    MIRROR_DIR="$mirror_base/dotfiles.git"
    
    # If mirror doesn't exist, clone from real repo (one-time operation)
    if [ ! -d "$MIRROR_DIR" ]; then
        log_info "Creating local Git mirror from remote..."
        git clone --bare git@github.com:darkroam/dotfiles.git "$MIRROR_DIR" 2>/dev/null || {
            log_error "Failed to create Git mirror. Check network and SSH access."
            return 1
        }
        log_info "Git mirror created successfully"
    else
        # Optionally update mirror (only when needed)
        if [ "${UPDATE_MIRROR:-false}" = "true" ]; then
            log_info "Updating local Git mirror..."
            (cd "$MIRROR_DIR" && git fetch --all 2>/dev/null) || true
        fi
    fi
    
    export DOTFILES_REPOSITORY="$MIRROR_DIR"
}

# Cleanup test environment
cleanup_test_env() {
    if [[ "${HOME:-}" == "$REAL_HOME" ]]; then
        log_error "FATAL: refusing to remove REAL_HOME: ${HOME:-unset}"
        exit 1
    elif [ -n "${HOME:-}" ] && [[ "$HOME" == /tmp/cfg-test-home.* ]]; then
        rm -rf "$HOME"
        log_info "Cleaned up test environment"
    else
        log_error "Refusing to remove non-test HOME: ${HOME:-unset}"
    fi

    # Restore real environment
    export HOME="$REAL_HOME"
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME
    unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
    unset DOTFILES_LIB_DIR

    if [ -n "$TEST_LOG_DIR" ] && [ -d "$TEST_LOG_DIR" ]; then
        rm -rf "$TEST_LOG_DIR"
    fi
}

# Verify current state
verify_state() {
    local expected_state="$1"
    local test_name="$2"
    
    case "$expected_state" in
        fresh)
            verify_fresh_state "$test_name"
            ;;
        desktop)
            verify_desktop_state "$test_name"
            ;;
        server)
            verify_server_state "$test_name"
            ;;
    esac
}

verify_fresh_state() {
    local test_name="$1"
    local errors=0
    
    # Note: .cfg may still exist after uninstall.sh (by design, for safety)
    # We check that config files are not symlinks to .cfg
    
    # Check key config files are not symlinks
    for f in .bashrc .zshrc .profile; do
        if [ -L "$HOME/$f" ]; then
            log_error "[$test_name] $f should not be a symlink in fresh state"
            ((errors++))
        fi
    done
    
    return $errors
}

verify_desktop_state() {
    local test_name="$1"
    local errors=0
    
    # Check .cfg exists
    if [ ! -d "$HOME/.cfg" ]; then
        log_error "[$test_name] .cfg directory missing"
        ((errors++))
        return $errors
    fi
    
    # Check desktop-specific files exist
    local desktop_files=(.xinitrc .xprofile .asoundrc)
    for f in "${desktop_files[@]}"; do
        if [ ! -e "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
            log_error "[$test_name] Desktop file $f missing"
            ((errors++))
        fi
    done
    
    # Check config status.showUntrackedFiles
    local show_untracked
    show_untracked=$(git --git-dir="$HOME/.cfg/" --work-tree="$HOME" config status.showUntrackedFiles 2>/dev/null || echo "all")
    if [ "$show_untracked" != "no" ]; then
        log_error "[$test_name] status.showUntrackedFiles should be 'no', got '$show_untracked'"
        ((errors++))
    fi
    
    # Check .cfg-checkout-state exists
    if [ ! -f "$HOME/.cfg-checkout-state" ]; then
        log_warn "[$test_name] .cfg-checkout-state not found (may be acceptable)"
    fi
    
    return $errors
}

verify_server_state() {
    local test_name="$1"
    local errors=0
    
    # Check .cfg exists
    if [ ! -d "$HOME/.cfg" ]; then
        log_error "[$test_name] .cfg directory missing"
        ((errors++))
        return $errors
    fi
    
    # Check desktop-specific files do NOT exist as symlinks
    local desktop_files=(.xinitrc .xprofile .asoundrc)
    for f in "${desktop_files[@]}"; do
        if [ -L "$HOME/$f" ]; then
            log_error "[$test_name] Desktop symlink $f should not exist in server mode"
            ((errors++))
        fi
    done
    
    # Check server-specific files exist
    local server_files=(.bashrc .zshrc .profile)
    for f in "${server_files[@]}"; do
        if [ ! -e "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
            log_warn "[$test_name] Server file $f missing (may be optional)"
        fi
    done
    
    # Check config status.showUntrackedFiles
    local show_untracked
    show_untracked=$(git --git-dir="$HOME/.cfg/" --work-tree="$HOME" config status.showUntrackedFiles 2>/dev/null || echo "all")
    if [ "$show_untracked" != "no" ]; then
        log_error "[$test_name] status.showUntrackedFiles should be 'no', got '$show_untracked'"
        ((errors++))
    fi
    
    return $errors
}

# Execute state transition test
run_transition_test() {
    local from_state="$1"
    local to_state="$2"
    local script="$3"
    local args="${4:-}"
    local test_name="${from_state}_to_${to_state}"
    
    log_test "=== Testing transition: $from_state → $to_state ==="
    log_test "Script: ${script:-none} ${args:-none}"
    
    # Setup test environment (creates isolated HOME)
    setup_test_env "$test_name"
    
    # Setup initial state
    setup_initial_state "$from_state" "$test_name"
    
    # Record initial file snapshot
    snapshot_files "before" "$test_name"
    
    # Execute script
    local start_time=$(date +%s)
    local exit_code=0
    
    if [ -n "$script" ]; then
        log_info "Executing: $script $args"
        yes | bash "$script" $args > "$TEST_LOG_DIR/${test_name}.stdout" 2> "$TEST_LOG_DIR/${test_name}.stderr" || exit_code=$?
        # Exit code 141 (128+13=SIGPIPE) means script succeeded but yes was interrupted
        if [ $exit_code -eq 141 ]; then
            exit_code=0
        fi
    else
        log_info "No script to execute (baseline test)"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Record final file snapshot
    snapshot_files "after" "$test_name"
    
    # Verify result state
    local verify_exit=0
    verify_state "$to_state" "$test_name" || verify_exit=$?
    
    # Generate test report
    generate_test_report "$test_name" "$exit_code" "$verify_exit" "$duration"
    
    # Cleanup
    cleanup_test_env
    
    return $((exit_code + verify_exit))
}

# Setup initial state
setup_initial_state() {
    local state="$1"
    local test_name="$2"
    
    log_info "Setting up initial state: $state"
    
    case "$state" in
        fresh)
            # Ensure clean environment
            rm -rf "$HOME/.cfg" 2>/dev/null || true
            generate_fresh_conflicts
            log_info "Generated fresh state conflicts"
            ;;
        desktop)
            # First install desktop
            run_install_2_silent
            generate_desktop_conflicts
            log_info "Installed desktop and generated conflicts"
            ;;
        server)
            # First install server
            run_install_server_silent
            generate_server_conflicts
            log_info "Installed server and generated conflicts"
            ;;
    esac
}

# Silent install helpers
run_install_2_silent() {
    yes | "$REAL_HOME/.local/bin/install-2.sh" >/dev/null 2>&1 || true
}

run_install_server_silent() {
    yes | "$REAL_HOME/.local/bin/install-server.sh" >/dev/null 2>&1 || true
}

# File snapshots
snapshot_files() {
    local when="$1"
    local test_name="$2"
    
    find "$HOME" -maxdepth 3 \( -type f -o -type l \) 2>/dev/null | \
        sort > "$TEST_LOG_DIR/${test_name}.${when}.filelist"
    
    # Record symlinks with targets
    find "$HOME" -maxdepth 3 -type l -exec ls -la {} \; 2>/dev/null | \
        sort > "$TEST_LOG_DIR/${test_name}.${when}.symlinks"
    
    # Record backup directories if any
    find "$HOME" -maxdepth 1 -name ".config-backup-*" -type d 2>/dev/null | \
        sort > "$TEST_LOG_DIR/${test_name}.${when}.backups" || true
}

# Generate test report
generate_test_report() {
    local test_name="$1"
    local script_exit="$2"
    local verify_exit="$3"
    local duration="$4"
    
    local total_exit=$((script_exit + verify_exit))
    local result="PASS"
    if [ $total_exit -ne 0 ]; then
        result="FAIL"
    fi
    
    cat > "$TEST_LOG_DIR/${test_name}.report.txt" <<EOF
Test: $test_name
Timestamp: $(date -Iseconds)
Duration: ${duration}s
Script Exit Code: $script_exit
Verify Exit Code: $verify_exit
Result: $result

Files Before: $(wc -l < "$TEST_LOG_DIR/${test_name}.before.filelist")
Files After: $(wc -l < "$TEST_LOG_DIR/${test_name}.after.filelist")
Symlinks Before: $(wc -l < "$TEST_LOG_DIR/${test_name}.before.symlinks")
Symlinks After: $(wc -l < "$TEST_LOG_DIR/${test_name}.after.symlinks")
Backups Before: $(wc -l < "$TEST_LOG_DIR/${test_name}.before.backups" 2>/dev/null || echo "0")
Backups After: $(wc -l < "$TEST_LOG_DIR/${test_name}.after.backups" 2>/dev/null || echo "0")
EOF
    
    if [ $total_exit -eq 0 ]; then
        log_info "✓ $test_name PASSED (${duration}s)"
    else
        log_error "✗ $test_name FAILED (script=$script_exit, verify=$verify_exit)"
        log_error "  Logs: $TEST_LOG_DIR/${test_name}.{stdout,stderr,report.txt}"
    fi
}

# Main test suite
run_all_tests() {
    local total=0
    local passed=0
    local failed=0
    
    echo ""
    echo "=========================================="
    echo "Configuration State Machine Test Suite"
    echo "=========================================="
    echo "Git Source: ${USE_REAL_REMOTE:-false} (false=local mirror, true=remote)"
    echo ""
    
    # Define all test cases (use $REAL_HOME, not hardcoded paths)
    declare -a tests=(
        "fresh:desktop:$REAL_HOME/.local/bin/install-2.sh:"
        "fresh:server:$REAL_HOME/.local/bin/install-server.sh:"

        "desktop:desktop:$REAL_HOME/.local/bin/install-2.sh:--reinstall"
        "desktop:server:$REAL_HOME/.local/bin/restore-server.sh:"
        "desktop:fresh:$REAL_HOME/.local/bin/uninstall.sh:"

        "server:server:$REAL_HOME/.local/bin/install-server.sh:--reinstall"
        "server:desktop:$REAL_HOME/.local/bin/restore-desktop.sh:"
        "server:fresh:$REAL_HOME/.local/bin/uninstall.sh:"

        "fresh:fresh:::"
    )
    
    for test_spec in "${tests[@]}"; do
        IFS=':' read -r from to script args <<< "$test_spec"
        total=$((total + 1))
        
        if run_transition_test "$from" "$to" "$script" "$args"; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            log_error "Test failed: $from → $to"
        fi
        
        echo ""
    done
    
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total:  $total"
    echo "Passed: $passed"
    echo "Failed: $failed"
    echo ""

    # Post-test safety check: verify real HOME was not affected
    echo "=========================================="
    echo "Environment Safety Check"
    echo "=========================================="
    local safety_ok=true
    if [ ! -d "$REAL_HOME" ]; then
        log_error "REAL_HOME ($REAL_HOME) does not exist!"
        safety_ok=false
    fi
    # Check no test artifacts leaked into real HOME
    for artifact in "$REAL_HOME/.cfg.installing."* "$REAL_HOME/.config-backup-"*; do
        if [ -e "$artifact" ] || [ -L "$artifact" ]; then
            log_error "Test artifact leaked into real HOME: $artifact"
            safety_ok=false
        fi
    done
    if [ "$safety_ok" = true ]; then
        log_info "Real HOME ($REAL_HOME) is clean — no test artifacts detected."
    else
        log_error "WARNING: Test environment isolation may have been breached!"
    fi
    echo ""
    
    if [ $failed -gt 0 ]; then
        log_error "Some tests failed. Check logs in /tmp/cfg-test-log.*/"
        return 1
    else
        log_info "All tests passed!"
        return 0
    fi
}

# Entry point
main() {
    case "${1:-all}" in
        all)
            run_all_tests
            ;;
        single)
            if [ $# -lt 4 ]; then
                echo "Usage: $0 single <from_state> <to_state> [script_args]"
                exit 1
            fi
            run_transition_test "$2" "$3" "${4:-}" "${5:-}"
            ;;
        help|--help|-h)
            echo "Usage: $0 [all|single <from> <to> [args]]"
            echo ""
            echo "States: fresh, desktop, server"
            echo ""
            echo "Environment Variables:"
            echo "  USE_REAL_REMOTE=true   Use real GitHub repo instead of local mirror"
            echo "  UPDATE_MIRROR=true     Update local mirror before testing"
            echo "  DOTFILES_REPOSITORY=<url>  Override repository URL"
            echo ""
            echo "Examples:"
            echo "  $0 all                                    # Run all tests"
            echo "  $0 single fresh desktop                   # Test fresh→desktop"
            echo "  $0 single desktop server                  # Test desktop→server"
            echo "  USE_REAL_REMOTE=true $0 all              # Test with real remote"
            ;;
        *)
            log_error "Unknown command: $1"
            main help
            exit 1
            ;;
    esac
}

main "$@"
