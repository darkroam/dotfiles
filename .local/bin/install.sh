#!/usr/bin/env bash

set -euo pipefail

repository=${DOTFILES_REPOSITORY:-git@github.com:darkroam/dotfiles.git}
final_git_dir=$HOME/.cfg
backup_dir=$HOME/.config-backup
temporary_git_dir=

cleanup() {
	if [ -n "$temporary_git_dir" ] && { [ -e "$temporary_git_dir" ] || [ -L "$temporary_git_dir" ]; }; then
		rm -rf -- "$temporary_git_dir"
	fi
}
trap cleanup EXIT

for command_name in git mkdir mv dirname chmod mktemp rm; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'install.sh requires %s.\n' "$command_name" >&2
		exit 127
	fi
done

if [ -e "$final_git_dir" ] || [ -L "$final_git_dir" ]; then
	printf '%s already exists; refusing to overwrite it.\n' "$final_git_dir" >&2
	exit 1
fi

temporary_git_dir=$(mktemp -d "$HOME/.cfg.installing.XXXXXX")
git clone --bare "$repository" "$temporary_git_dir"
git_dir=$temporary_git_dir

config() {
	git --git-dir="$git_dir/" --work-tree="$HOME" "$@"
}

config rev-parse --verify HEAD >/dev/null

tracked_paths=()
while IFS= read -r -d '' path; do
	case $path in
		''|/*|..|../*|*/..|*/../*)
			printf 'Repository contains an unsafe work-tree path: %s\n' "$path" >&2
			exit 1
			;;
	esac
	tracked_paths+=("$path")
done < <(config ls-tree -r --name-only -z HEAD)

backup_paths=()

add_backup_path() {
	local candidate existing
	candidate=$1
	for existing in "${backup_paths[@]}"; do
		[ "$existing" = "$candidate" ] && return
	done
	backup_paths+=("$candidate")
}

# A non-directory or symlink ancestor would make checkout fail or escape HOME.
for path in "${tracked_paths[@]}"; do
	remainder=$path
	ancestor=
	blocked=false
	while [[ $remainder == */* ]]; do
		component=${remainder%%/*}
		remainder=${remainder#*/}
		ancestor=${ancestor:+$ancestor/}$component
		source_path=$HOME/$ancestor
		if [ -L "$source_path" ] || { [ -e "$source_path" ] && [ ! -d "$source_path" ]; }; then
			add_backup_path "$ancestor"
			blocked=true
			break
		fi
	done
	if [ "$blocked" = false ]; then
		source_path=$HOME/$path
		if [ -e "$source_path" ] || [ -L "$source_path" ]; then
			add_backup_path "$path"
		fi
	fi
done

if ((${#backup_paths[@]})); then
	if [ -L "$backup_dir" ] || { [ -e "$backup_dir" ] && [ ! -d "$backup_dir" ]; }; then
		printf 'Backup root must be a real directory: %s\n' "$backup_dir" >&2
		exit 1
	fi

	# Refuse before moving anything if a previous backup or unsafe parent owns a target.
	for path in "${backup_paths[@]}"; do
		remainder=$path
		ancestor=
		while [[ $remainder == */* ]]; do
			component=${remainder%%/*}
			remainder=${remainder#*/}
			ancestor=${ancestor:+$ancestor/}$component
			backup_parent=$backup_dir/$ancestor
			if [ -L "$backup_parent" ] || { [ -e "$backup_parent" ] && [ ! -d "$backup_parent" ]; }; then
				printf 'Backup parent blocks target: %s\n' "$backup_parent" >&2
				exit 1
			fi
		done

		backup_path=$backup_dir/$path
		if [ -e "$backup_path" ] || [ -L "$backup_path" ]; then
			printf 'Backup target already exists: %s\n' "$backup_path" >&2
			exit 1
		fi
	done

	mkdir -p -- "$backup_dir"
	chmod 700 "$backup_dir"
fi

moved_paths=()

rollback_moves() {
	local index moved_path source_path backup_path
	for ((index=${#moved_paths[@]} - 1; index >= 0; index--)); do
		moved_path=${moved_paths[index]}
		source_path=$HOME/$moved_path
		backup_path=$backup_dir/$moved_path
		if [ -e "$source_path" ] || [ -L "$source_path" ]; then
			printf 'Could not restore %s because the original path is occupied.\n' "$moved_path" >&2
			continue
		fi
		mkdir -p -- "$(dirname "$source_path")"
		if ! mv -- "$backup_path" "$source_path"; then
			printf 'Could not restore %s from %s.\n' "$moved_path" "$backup_path" >&2
		fi
	done
}

for path in "${backup_paths[@]}"; do
	source_path=$HOME/$path
	backup_path=$backup_dir/$path
	if ! mkdir -p -- "$(dirname "$backup_path")" || ! mv -- "$source_path" "$backup_path"; then
		printf 'Failed to back up %s; restoring earlier moves.\n' "$path" >&2
		rollback_moves
		exit 1
	fi
	moved_paths+=("$path")
	printf 'Backed up %s\n' "$path"
done

if ! mv -- "$temporary_git_dir" "$final_git_dir"; then
	printf 'Failed to activate %s; restoring backups.\n' "$final_git_dir" >&2
	rollback_moves
	exit 1
fi
temporary_git_dir=
git_dir=$final_git_dir

if ! config checkout; then
	printf 'Checkout failed. The repository remains at %s and original conflicts remain in %s.\n' \
		"$final_git_dir" "$backup_dir" >&2
	exit 1
fi
config config status.showUntrackedFiles no
printf 'Checked out configuration into %s.\n' "$HOME"
