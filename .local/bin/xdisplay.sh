#!/bin/bash
# X11 display auto-config on login
# Extends to the right, scale 1, HDMI-1 auto-detected on hotplug

sleep 2  # wait for display manager

if [ -x "$HOME/.local/bin/innogpu-restore-dp1-mode-x11" ]; then
    "$HOME/.local/bin/innogpu-restore-dp1-mode-x11" &
elif command -v innogpu-restore-dp1-mode-x11 >/dev/null 2>&1; then
    innogpu-restore-dp1-mode-x11 &
fi

XRANDR_OUTPUT="HDMI-1"

# Function to apply display config
apply_display_config() {
    local ext_display="$1"

    # Get current primary and available outputs
    local primary=$(xrandr --listactivemonitors 2>/dev/null | grep '*' | awk '{print $NF}' | head -1)
    local edp_status=$(xrandr 2>/dev/null | grep '^eDP-1' | awk '{print $2}')

    # Find the rightmost monitor to extend from
    local rightmost=""
    local max_x=0

    # Check all connected monitors and find rightmost edge
    for output in $(xrandr 2>/dev/null | grep ' connected' | awk '{print $1}'); do
        if [ "$output" = "eDP-1" ] || [ "$output" = "$XRANDR_OUTPUT" ]; then
            continue
        fi
        local pos=$(xrandr 2>/dev/null | grep "^$output connected" | grep -oP '\+\d+\+\d+' | head -1)
        local x_off=$(echo "$pos" | grep -oP '\+\d+' | head -1 | tr -d '+')
        if [ -n "$x_off" ] && [ "$x_off" -gt "$max_x" ]; then
            max_x=$x_off
            rightmost="$output"
        fi
    done

    # Default: extend from eDP-1
    if [ -z "$rightmost" ]; then
        rightmost="eDP-1"
    fi

    # Apply config
    xrandr --output "$XRANDR_OUTPUT" --auto --right-of "$rightmost" --scale 1x1

    # If eDP-1 is off (lid closed), set HDMI-1 as primary
    if [ "$edp_status" = "off" ]; then
        xrandr --output eDP-1 --off 2>/dev/null
        xrandr --output "$XRANDR_OUTPUT" --primary
    fi
}

# Apply for HDMI-1 if connected
if xrandr 2>/dev/null | grep -q "^$XRANDR_OUTPUT connected"; then
    apply_display_config "$XRANDR_OUTPUT"
fi
