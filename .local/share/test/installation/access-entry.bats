#!/usr/bin/env bats
# access-entry.bats - PATH symlink, min exclusion, unit text.
# TC-AXS01

load helpers.bash

@test "TC-AXS01: .local/bin/axs resolves to the in-tree entry" {
	link=$(readlink "$DOTFILES_ROOT/.local/bin/axs")
	[ "$link" = "../lib/access/bin/axs" ]
	[ -e "$DOTFILES_ROOT/.local/bin/axs" ]
	[ -x "$DOTFILES_ROOT/.local/bin/axs" ]
}

@test "TC-AXS02: min excludes the access entry and tree" {
	# dotfiles 当前无 category 清单命令，出现后再换判据。
	! grep -qF '.local/bin/axs' "$DOTFILES_ROOT/.local/lib/installation/categories-1.0.0.conf"
	! grep -qF '.local/lib/access' "$DOTFILES_ROOT/.local/lib/installation/categories-1.0.0.conf"
}

@test "TC-AXS03: unit templates stay in the library and do not enable themselves" {
	units=$DOTFILES_ROOT/.local/lib/access/units
	grep -qF '%h/.local/lib/access/bin/mihomo-run' "$units/axs.service"
	grep -qF '%h/.local/lib/access/bin/axs subscription refresh' "$units/axs-refresh.service"
	grep -qF 'WantedBy=timers.target' "$units/axs-refresh.timer"
	! grep -R -q 'systemctl' "$units"
}
