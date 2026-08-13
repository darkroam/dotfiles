#!/bin/sh

# Compatibility entry point. Use `xdisplay` for new integrations.
xdisplay_bin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
exec "$xdisplay_bin_dir/xdisplay" "$@"
