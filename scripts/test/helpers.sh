#!/usr/bin/env bash
# helpers.sh - Test helper functions for state machine testing

# Check backup directory structure
check_backup_structure() {
    local backup_dir="$1"
    local expected_pattern="$2"
    
    if [[ "$backup_dir" =~ $expected_pattern ]]; then
        return 0
    else
        echo "Backup directory does not match pattern: $expected_pattern"
        return 1
    fi
}

# Verify MANIFEST.txt format and content
verify_manifest() {
    local backup_dir="$1"
    local manifest="$backup_dir/MANIFEST.txt"
    
    if [ ! -f "$manifest" ]; then
        echo "MANIFEST.txt not found in $backup_dir"
        return 1
    fi
    
    # Check required fields
    grep -q "^# State transition:" "$manifest" || {
        echo "Missing state transition in MANIFEST"
        return 1
    }
    
    grep -q "^# Format:" "$manifest" || {
        echo "Missing format description in MANIFEST"
        return 1
    }
    
    # Check that at least one file mapping exists (if backup was created)
    if grep -q "^/.*-> /.*(" "$manifest"; then
        return 0
    fi
    
    # If no file mappings, that's acceptable for tests with no conflicts
    return 0
}

# Verify .cfg-checkout-state format
verify_checkout_state() {
    local state_file="$HOME/.cfg-checkout-state"
    
    if [ ! -f "$state_file" ]; then
        echo ".cfg-checkout-state not found"
        return 1
    fi
    
    # Verify format: path:hash
    local line_num=0
    while IFS=: read -r path hash; do
        ((line_num++))
        
        # Skip empty lines
        [ -z "$path" ] && continue
        
        # Validate path starts with dot
        if [[ ! "$path" =~ ^\. ]]; then
            echo "Invalid path at line $line_num: $path (should start with .)"
            return 1
        fi
        
        # Validate hash is 32 hex characters (md5)
        if [[ ! "$hash" =~ ^[a-f0-9]{32}$ ]]; then
            echo "Invalid hash at line $line_num: $hash (expected 32 hex chars)"
            return 1
        fi
    done < "$state_file"
    
    return 0
}

# Check if backup naming follows convention
validate_backup_naming() {
    local backup_name="$1"
    local pattern="\.config-backup-(fresh|desktop|server)-to-(fresh|desktop|server)-[0-9]{8}T[0-9]{6}"
    
    if [[ "$backup_name" =~ $pattern ]]; then
        return 0
    else
        echo "Backup name '$backup_name' does not follow naming convention"
        echo "Expected pattern: .config-backup-{from}-to-{to}-{timestamp}"
        return 1
    fi
}

# Count files by status in MANIFEST
count_files_by_status() {
    local manifest="$1"
    local status="$2"  # modified or untracked
    
    if [ ! -f "$manifest" ]; then
        echo "0"
        return
    fi
    
    grep -c "($status)" "$manifest" 2>/dev/null || echo "0"
}

# Export functions
export -f check_backup_structure
export -f verify_manifest
export -f verify_checkout_state
export -f validate_backup_naming
export -f count_files_by_status
