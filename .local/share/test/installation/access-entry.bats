#!/usr/bin/env bats
# access-entry.bats - PATH symlink resolves into the access tree and runs.
# TC-AXS01

load helpers.bash

@test "TC-AXS01: .local/bin/axs resolves to the in-tree entry and runs" {
	link=$(readlink "$DOTFILES_ROOT/.local/bin/axs")
	[ "$link" = "../lib/access/bin/axs" ]
	run "$DOTFILES_ROOT/.local/bin/axs" help
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}
