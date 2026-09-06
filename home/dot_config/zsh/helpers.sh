#!/bin/zsh

# `confirm <prompt> [default]` to prompt the user for a yes/no answer
# Enter accepts the default: `n` unless `y` is passed as the second argument
confirm() {
    local default="${2:-n}"
    local hint reply
    [[ "$default" == [Yy] ]] && hint="[Y/n]" || hint="[y/N]"
    while true; do
        echo -n "$1 $hint "
        IFS= read -r reply
        [[ -z "$reply" ]] && reply="$default"
        case "$reply" in
            [Yy]*) return 0;;
            [Nn]*) return 1;;
        esac
    done
}

# `require_args <error msg> <num args> <arg list>` to return if the sufficient number of args was supplied
require_args() {
    if [[ $(($2 + 2)) -le $# ]]; then
        return 0;
    else
        echo $1;
        return 1;
    fi
}

# `require_git_repo` to return if the current directory is not inside a git repository
require_git_repo() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "Error: not inside a git repository"
        return 1
    fi
}

# `has_remote` to return whether the current repository has a remote named 'origin'
has_remote() {
    git remote get-url origin >/dev/null 2>&1
}

# `require_git_remote` to return if the current repository is not a git repo or has no remote named 'origin'
require_git_remote() {
    require_git_repo || return 1
    has_remote || { echo "Error: no remote 'origin' configured"; return 1; }
}
