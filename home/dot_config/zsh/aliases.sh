#!/bin/zsh

# `sw` aliases to `switch` (git.sh) and `cd` with no args calls `icd` (icd.sh),
# but both are resolved at call time, so load order of files doesn't matter here.

if [[ $- == *i* ]]; then
    # Never accidentally permanently delete files
    alias rm='trash'

    # `restart` to make any changes to .zshrc, .zprofile, etc. active in the current shell
    alias restart='exec zsh -l'

    # a better ls
    if command -v eza > /dev/null; then
        alias ls='eza -1 --group-directories-first --icons'
    fi

    # shorthands
    alias py='python'
    alias g='git'
    alias sw='switch'
    alias cl='claude'
    alias lg='git lg'
    alias cm='chezmoi'
    alias claued='claude'
    alias cluade='claude'

    # built-in cd unless called with no arguments, which triggers interactive navigation
    cd() {
        if [[ $# -eq 0 ]]; then
            icd
        else
            builtin cd "$@"
        fi
    }

    # built-in touch, but offers to create each missing directory in the path first
    touch() {
        local arg dir prefix part
        for arg in "$@"; do
            [[ "$arg" == -* ]] && continue
            dir="${arg:h}"
            [[ -d "$dir" ]] && continue

            prefix=""
            [[ "$dir" == /* ]] && prefix="/"
            for part in "${(s:/:)dir}"; do
                [[ -z "$part" ]] && continue
                prefix="$prefix$part"
                if [[ ! -d "$prefix" ]]; then
                    confirm "Create directory '$prefix'?" y || return 1
                    mkdir "$prefix" || return 1
                fi
                prefix="$prefix/"
            done
        done
        command touch "$@"
    }

    # `fcopy <file>` to copy the contents of a file to the clipboard
    fcopy() {
        require_args 'usage: fcopy <file>' 1 "$@" || return
        pbcopy < "$1"
    }
fi
