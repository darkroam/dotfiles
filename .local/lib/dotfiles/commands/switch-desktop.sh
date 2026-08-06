#!/usr/bin/env bash
# switch-desktop.sh - Forward to unified switch.sh
exec bash "$(dirname "$0")/switch.sh" --type=desktop "$@"
