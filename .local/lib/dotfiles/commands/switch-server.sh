#!/usr/bin/env bash
# switch-server.sh - Forward to unified switch.sh
exec bash "$(dirname "$0")/switch.sh" --type=server "$@"
