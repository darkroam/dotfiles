#!/usr/bin/env bash
# switch-desktop.sh - Legacy alias for the full category
exec bash "$(dirname "$0")/switch.sh" --type=full "$@"
