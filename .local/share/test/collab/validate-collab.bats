#!/usr/bin/env bats
# Isolated fixtures for .local/lib/project-tools/validate-collab.

REAL_HOME=${REAL_HOME:-$HOME}
DOTFILES_ROOT=$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)
TOOL=$DOTFILES_ROOT/.local/lib/project-tools/validate-collab

setup() {
	TEST_ROOT=$(mktemp -d /tmp/dotfiles-collab-test.XXXXXX)
	COLLAB=$TEST_ROOT/collab
}

teardown() {
	[ -n "${TEST_ROOT:-}" ] || return 0
	if [ "$TEST_ROOT" = "$REAL_HOME" ]; then
		printf 'refusing to remove REAL_HOME\n' >&2
		return 1
	fi
	case $TEST_ROOT in
		/tmp/dotfiles-collab-test.*) rm -rf -- "$TEST_ROOT" ;;
		*)
			printf 'refusing to remove unsafe test path: %s\n' "$TEST_ROOT" >&2
			return 1
			;;
	esac
}

write_index() {
	mkdir -p "$COLLAB"
	{
		printf '%s\n' '| 轮次 | 日期 | 主题 | 状态 |'
		printf '%s\n' '|------|------|------|------|'
		cat
	} > "$COLLAB/INDEX.md"
}

make_templates() {
	mkdir -p "$COLLAB/templates"
	printf '# request template\n' > "$COLLAB/templates/要求.md"
	printf '# report template\n' > "$COLLAB/templates/汇报.md"
}

make_round() {
	local name=$1
	mkdir -p "$COLLAB/$name"
	printf '# request\n' > "$COLLAB/$name/要求.md"
	printf '# report\n' > "$COLLAB/$name/汇报.md"
}

seed_valid() {
	make_templates
	make_round R01-2026-08-31-topic-a
	printf '%s\n' '| R01 | 2026-08-31 | topic-a | 待开发 |' | write_index
}

assert_contains() {
	[[ $output == *"$1"* ]]
}

@test "valid archive passes without output" {
	seed_valid
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "missing collab directory passes without output" {
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "default path resolves below HOME" {
	seed_valid
	mkdir -p "$TEST_ROOT/.local/share"
	mv "$COLLAB" "$TEST_ROOT/.local/share/collab"
	run env HOME="$TEST_ROOT" "$TOOL"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "too many arguments return usage status 2" {
	run "$TOOL" "$COLLAB" extra
	[ "$status" -eq 2 ]
	assert_contains "Usage:"
}

@test "empty explicit path returns usage status 2" {
	run "$TOOL" ""
	[ "$status" -eq 2 ]
	assert_contains "Usage:"
}

@test "stray root file is rejected" {
	seed_valid
	printf 'stray\n' > "$COLLAB/stray.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "collab root allows only"
}

@test "round missing 汇报.md is rejected" {
	seed_valid
	rm "$COLLAB/R01-2026-08-31-topic-a/汇报.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "missing ordinary file 汇报.md"
}

@test "round non-Markdown file is rejected" {
	seed_valid
	printf 'data\n' > "$COLLAB/R01-2026-08-31-topic-a/data.bin"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "only Markdown"
}

@test "nested round directory is rejected" {
	seed_valid
	mkdir "$COLLAB/R01-2026-08-31-topic-a/nested"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "nested directories"
}

@test "symbolic link anywhere is rejected" {
	seed_valid
	ln -s 要求.md "$COLLAB/R01-2026-08-31-topic-a/link.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "symbolic links are not allowed"
}

@test "collab root symbolic link is rejected" {
	seed_valid
	mv "$COLLAB" "$TEST_ROOT/archive"
	ln -s "$TEST_ROOT/archive" "$COLLAB"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "collab root must not be a symbolic link"
}

@test "missing INDEX is rejected" {
	seed_valid
	rm "$COLLAB/INDEX.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "INDEX.md is missing"
}

@test "duplicate INDEX row is rejected" {
	seed_valid
	printf '%s\n' '| R01 | 2026-08-31 | topic-a | 待开发 |' >> "$COLLAB/INDEX.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "duplicate round id: R01"
}

@test "orphan INDEX row is rejected" {
	seed_valid
	printf '%s\n' '| R02 | 2026-08-31 | topic-b | 待开发 |' >> "$COLLAB/INDEX.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "without a directory: R02"
}

@test "orphan round directory is rejected" {
	seed_valid
	make_round R02-2026-08-31-topic-b
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "not registered in collab/INDEX.md: R02"
}

@test "R01 and R010 match by exact identifiers" {
	seed_valid
	make_round R010-2026-08-31-topic-b
	printf '%s\n' '| R010 | 2026-08-31 | topic-b | 待审查 |' >> "$COLLAB/INDEX.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "R010 does not satisfy an R01 INDEX row" {
	make_templates
	make_round R010-2026-08-31-topic-a
	printf '%s\n' '| R01 | 2026-08-31 | topic-a | 待开发 |' | write_index
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "without a directory: R01"
	assert_contains "not registered in collab/INDEX.md: R010"
}

@test "invalid status is rejected" {
	seed_valid
	sed -i 's/待开发/已完成/' "$COLLAB/INDEX.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "status outside the whitelist"
}

@test "invalid round directory name is rejected" {
	seed_valid
	mkdir "$COLLAB/notes"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "invalid round directory name"
}

@test "invalid calendar date is rejected" {
	seed_valid
	mv "$COLLAB/R01-2026-08-31-topic-a" "$COLLAB/R01-2026-02-30-topic-a"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "invalid round directory name"
}

@test "INDEX date must exactly match the directory" {
	seed_valid
	sed -i 's/2026-08-31/2026-08-30/' "$COLLAB/INDEX.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "date differs between directory and INDEX"
}

@test "INDEX topic must exactly match the directory" {
	seed_valid
	sed -i 's/topic-a/topic-b/' "$COLLAB/INDEX.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "topic differs between directory and INDEX"
}

@test "hidden Markdown credential assignment is rejected" {
	seed_valid
	printf 'api_key = %s\n' 'example-sensitive-value' > "$COLLAB/R01-2026-08-31-topic-a/.private.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains ".private.md:1"
	assert_contains "credential assignment"
}

@test "runtime username is rejected without embedding it in fixtures" {
	seed_valid
	printf 'identity: %s\n' "$(id -un)" > "$COLLAB/R01-2026-08-31-topic-a/identity.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "runtime username"
}

@test "runtime hostname is rejected without embedding it in fixtures" {
	seed_valid
	printf 'identity: %s\n' "$(hostname)" > "$COLLAB/R01-2026-08-31-topic-a/identity.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "runtime hostname"
}

@test "credential assignment matching is case-insensitive" {
	seed_valid
	printf 'ToKeN: %s\n' 'example-sensitive-value' > "$COLLAB/R01-2026-08-31-topic-a/private.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "credential assignment"
}

@test "single-quoted credential assignment is rejected" {
	seed_valid
	printf "secret='%s'\n" 'example-sensitive-value' > "$COLLAB/R01-2026-08-31-topic-a/private.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "credential assignment"
}

@test "privacy policy words without values do not cause false positives" {
	seed_valid
	printf 'Never record token, password, API key, or secret values.\n' > "$COLLAB/R01-2026-08-31-topic-a/policy.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "private IPv4 address is rejected" {
	seed_valid
	printf 'endpoint 192.168.50.12\n' > "$COLLAB/R01-2026-08-31-topic-a/private.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "private IPv4 address"
}

@test "MAC address is rejected" {
	seed_valid
	printf 'adapter aa:bb:cc:dd:ee:ff\n' > "$COLLAB/R01-2026-08-31-topic-a/private.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "MAC address"
}

@test "UUID is rejected" {
	seed_valid
	printf 'id 12345678-1234-5678-9abc-123456789abc\n' > "$COLLAB/R01-2026-08-31-topic-a/private.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "UUID"
}

@test "absolute home path is rejected" {
	seed_valid
	printf '/home/example-user/private\n' > "$COLLAB/R01-2026-08-31-topic-a/private.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "absolute home path"
}

@test "templates allow exactly two required files" {
	seed_valid
	printf '# extra\n' > "$COLLAB/templates/extra.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "templates may contain only"
}

@test "wrong INDEX header is rejected" {
	seed_valid
	sed -i 's/轮次/编号/' "$COLLAB/INDEX.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "table header must be"
}

@test "missing INDEX separator is rejected" {
	seed_valid
	sed -i '2d' "$COLLAB/INDEX.md"
	run "$TOOL" "$COLLAB"
	[ "$status" -eq 1 ]
	assert_contains "not followed by a valid separator"
}
