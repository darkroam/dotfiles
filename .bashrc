#!/bin/bash
stty -ixon # Disable ctrl-s and ctrl-q.
shopt -s autocd #Allows you to cd into directory merely by typing the directory name.
HISTSIZE=-1 # Infinite in-memory history.
HISTFILESIZE=-1 # Do not truncate the history file.
shopt -s histappend # Preserve history written by concurrent Bash sessions.
export PS1="\[$(tput bold)\]\[$(tput setaf 1)\][\[$(tput setaf 3)\]\u\[$(tput setaf 2)\]@\[$(tput setaf 4)\]\h \[$(tput setaf 5)\]\W\[$(tput setaf 1)\]]\[$(tput setaf 7)\]\\$ \[$(tput sgr0)\]"

[ -f "$HOME/.config/shell/shortcutrc" ] && source "$HOME/.config/shell/shortcutrc" # Load shortcut aliases
[ -f "$HOME/.config/shell/aliasrc" ] && source "$HOME/.config/shell/aliasrc"


[ -r /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
if [ -r /usr/share/bash-completion/completions/git ]; then
	. /usr/share/bash-completion/completions/git
	_c_git_complete() {
		local -a saved_words=("${COMP_WORDS[@]}")
		local current_word=${COMP_WORDS[COMP_CWORD]}
		local saved_cword=$COMP_CWORD
		local saved_line=$COMP_LINE
		local saved_point=$COMP_POINT
		local GIT_DIR="$HOME/.cfg/"
		local GIT_WORK_TREE="$HOME"
		export GIT_DIR GIT_WORK_TREE
		if [[ ${saved_words[1]} == diff ]]; then
			local -a changed_files
			mapfile -t changed_files < <(git diff --name-only --no-color)
			COMPREPLY=()
			for file in "${changed_files[@]}"; do
				[[ $file == "$current_word"* ]] && COMPREPLY+=("$file")
			done
			return
		fi
		COMP_WORDS=(git "${saved_words[@]:1}")
		COMP_LINE="git${saved_line#c}"
		COMP_POINT=$(( saved_point + 2 ))
		__git_wrap__git_main
		local status=$?
		COMP_WORDS=("${saved_words[@]}")
		COMP_CWORD=$saved_cword
		COMP_LINE=$saved_line
		COMP_POINT=$saved_point
		return $status
	}
	complete -o bashdefault -o default -o nospace -F _c_git_complete c
fi

[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# Non-login Bash sessions do not read the shared profile.
case ":$PATH:" in
	*:"$HOME/.local/bin":*) ;;
	*) export PATH="$HOME/.local/bin:$PATH" ;;
esac
alias groff='groff -P-e'
