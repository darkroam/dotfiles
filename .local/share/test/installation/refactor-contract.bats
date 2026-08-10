#!/usr/bin/env bats
# refactor-contract.bats - User-visible contracts preserved during refactoring
# TC-R01 through TC-R05

load helpers.bash

setup() {
	setup_test_home
}

teardown() {
	teardown_test_home
}

@test "TC-R01: help output remains byte-for-byte stable" {
	run run_dotcfg help
	[ "$status" -eq 0 ]
	local expected
	expected=$(cat <<'EOF'
Usage: dotcfg <subcommand> [options]

Dotfiles state management CLI (node-based)

Subcommands:
  status              Show current node and deploy status (default)
  list                List all nodes (DEPLOY, TYPE, VERSION, STATUS, TIME, CODE)
  history             Show node tree (git log --graph style)
  switch <target>     Switch to state (full|min|macos|fresh) or node CODE
  deploy              Deploy current node configuration
  undeploy            Undeploy current node, restore original files
  uninstall           Return to root fresh node
  migrate             Migrate old backup sessions to node system
  remove <CODE>       Mark a node for removal
  unremove <CODE>     Unmark a node from removal
  autoclean           Permanently delete marked nodes
  categories          Manage config versions
  validate            Show detailed repository validation
  track <file>        Add a file to the fresh root backup
  untrack <file>      Remove a file from the fresh root backup
  fresh-status        Show fresh root node backup statistics
  fresh-diff [path]   Compare $HOME against the fresh root backup
  fresh-update        Rebuild the fresh root backup from current $HOME
  fresh-adopt-legacy <path> [--dry-run] [--config-version VERSION]
                      Reconstruct Fresh from a pre-dotcfg backup
  doctor              Check system integrity
  repair              Attempt automatic repairs
  check-exclude <p>   Show why a path is excluded from fresh backup
  help                Show this help message
  version             Show version

Switch options:
  --dry-run           Preview changes without applying
  --force             Force operation (replace existing repos, etc.)
  --reinstall         Reinstall the current category
  --auto-stash        Auto-backup conflicting files

Examples:
  dotcfg                          # show current status
  dotcfg list                     # list all nodes
  dotcfg history                  # show node tree
  dotcfg switch full              # deploy all managed configuration
  dotcfg switch min               # deploy command-line configuration
  dotcfg switch macos             # deploy cross-platform core configuration
  dotcfg fresh-adopt-legacy ~/.config-backup --dry-run
  dotcfg switch xk7f9a2m          # switch to historical node
  dotcfg deploy                   # deploy current node
  dotcfg undeploy                 # undeploy current node
  dotcfg uninstall                # return to fresh root node
EOF
)
	[ "$output" = "$expected" ]
}

@test "TC-R02: check-exclude preserves the hardcoded compatibility label" {
	run run_dotcfg check-exclude Downloads/foo.tar.gz
	[ "$status" -eq 0 ]
	[ "$output" = "Path is excluded by hardcoded rule: ~/Downloads/" ]
}

@test "TC-R03: categories show preserves the dynamic full marker" {
	create_mock_cfg_repo ".bashrc" ".local/bin/dotcfg"
	run run_dotcfg categories show 1.0.0
	[ "$status" -eq 0 ]
	[[ "$output" == *"full            (dynamic, all tracked files)"* ]]
}

@test "TC-R04: unknown switch target keeps its error contract" {
	run run_dotcfg switch unknown-target
	[ "$status" -eq 1 ]
	[[ "$output" == *'Error: unknown target "unknown-target"'* ]]
	[[ "$output" == *"Valid targets: full, min, macos, fresh, or an 8-char node CODE"* ]]
}

@test "TC-R05: help does not load business libraries" {
	local test_lib="$HOME/dotfiles-lib"
	local marker="$HOME/business-library-loaded"
	cp -r "$REAL_HOME/.local/lib/dotfiles" "$test_lib"
	printf '\nprintf "loaded" > %q\n' "$marker" >> "$test_lib/utils/nodes.sh"

	run env DOTFILES_LIB_DIR="$test_lib" bash "$DOTCFG" help
	[ "$status" -eq 0 ]
	[ ! -e "$marker" ]
}
