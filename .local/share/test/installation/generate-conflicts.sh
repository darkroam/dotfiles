#!/usr/bin/env bash
# generate-conflicts.sh - Generate test conflict files for different states
# This script creates realistic conflict scenarios to test backup and restoration logic

set -euo pipefail

generate_fresh_conflicts() {
    # Simulate system default configuration files that would exist on a fresh system
    
    cat > "$HOME/.bashrc" <<'EOF'
# System default .bashrc
export PS1='[\u@\h \W]\$ '
export PATH=/usr/local/bin:/usr/bin:/bin
EOF
    
    cat > "$HOME/.zshrc" <<'EOF'
# System default .zshrc
autoload -U zsh/compinit
zmodload -i zsh/compctl
EOF
    
    cat > "$HOME/.profile" <<'EOF'
# System default profile
export PATH=/usr/local/bin:/usr/bin:/bin
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi
EOF
    
    # Create some untracked config directories
    mkdir -p "$HOME/.config/system-default"
    cat > "$HOME/.config/system-default/settings.conf" <<'EOF'
# System settings
theme=default
language=en
EOF
}

generate_desktop_conflicts() {
    # Simulate user-modified files in desktop mode
    
    mkdir -p "$HOME/.config/shell"
    
    cat > "$HOME/.bashrc" <<'EOF'
# User modified .bashrc in desktop mode
export MY_CUSTOM_VAR="desktop-custom"
export EDITOR=vim
alias ll='ls -la --color=auto'
alias grep='grep --color=auto'

# Custom PATH additions
export PATH="$HOME/.local/bin:$PATH"
EOF
    
    cat > "$HOME/.gitconfig" <<'EOF'
[user]
    name = Test User
    email = test@example.com
[core]
    editor = vim
[custom]
    desktop-setting = true
    sync-enabled = false
EOF
    
    # Create user's custom tmux config (untracked)
    cat > "$HOME/.tmux.conf.local" <<'EOF'
# User's custom tmux settings
set -g mouse on
set -g history-limit 10000
bind r source-file ~/.tmux.conf \; display "Reloaded!"
EOF
    
    # Modify profile with custom exports
    cat > "$HOME/.profile" <<'EOF'
# User modified profile
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Desktop-specific environment
export DESKTOP_SESSION=custom
export GDK_SCALE=2
EOF
    
    # Create some desktop-specific untracked files
    mkdir -p "$HOME/.config/custom-desktop"
    cat > "$HOME/.config/custom-desktop/preferences.conf" <<'EOF'
# Custom desktop preferences
font_size=14
color_scheme=dark
EOF
}

generate_server_conflicts() {
    # Simulate user-modified files in server mode
    
    cat > "$HOME/.bashrc" <<'EOF'
# User modified .bashrc in server mode
export SERVER_MODE=true
export EDITOR=vim
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# Server-specific PATH
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
    
    cat > "$HOME/.gitconfig" <<'EOF'
[user]
    name = Server Admin
    email = admin@example.com
[core]
    editor = vim
    autocrlf = input
[push]
    default = simple
[pull]
    rebase = true
EOF
    
    # Create server-specific untracked files
    mkdir -p "$HOME/.config/server-tools"
    cat > "$HOME/.config/server-tools/custom.sh" <<'EOF'
#!/usr/bin/env bash
# Server custom tool
echo "Server maintenance script"
echo "Current time: $(date)"
echo "Uptime: $(uptime)"
EOF
    chmod +x "$HOME/.config/server-tools/custom.sh"
    
    # Create custom tmux config for server
    cat > "$HOME/.tmux.conf.local" <<'EOF'
# Server-specific tmux settings
set -g mouse off
set -g history-limit 50000
setw -g aggressive-resize on
EOF
    
    # Modify profile for server environment
    cat > "$HOME/.profile" <<'EOF'
# Server profile
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.UTF-8

# Server environment variables
export SERVER_ROLE=production
export LOG_LEVEL=info
EOF
    
    # Create SSH config (untracked, common in server setups)
    mkdir -p "$HOME/.ssh"
    cat > "$HOME/.ssh/config" <<'EOF'
Host *
    StrictHostKeyChecking ask
    AddKeysToAgent yes
    UseKeychain yes
EOF
    chmod 600 "$HOME/.ssh/config"
}

# Export functions for use in other scripts
export -f generate_fresh_conflicts
export -f generate_desktop_conflicts
export -f generate_server_conflicts

# If run directly, execute based on argument
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-fresh}" in
        fresh)
            generate_fresh_conflicts
            echo "Generated fresh state conflicts"
            ;;
        desktop)
            generate_desktop_conflicts
            echo "Generated desktop state conflicts"
            ;;
        server)
            generate_server_conflicts
            echo "Generated server state conflicts"
            ;;
        *)
            echo "Usage: $0 {fresh|desktop|server}"
            exit 1
            ;;
    esac
fi
