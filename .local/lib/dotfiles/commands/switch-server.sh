#!/usr/bin/env bash
# switch-server.sh - Legacy direct-script wrapper for the min category
exec bash "$(dirname "$0")/switch.sh" --type=min "$@"
