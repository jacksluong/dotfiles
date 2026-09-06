#!/bin/zsh

# `pull` to git pull
pull() {
    require_git_remote || return 1
    git pull --all "$@"
}

# `pullall [-v] [dir]` to git pull from the default branch of all repositories in the current directory
pullall() {
    emulate -L zsh
    setopt pipefail
    unsetopt monitor notify

    function pullall_count_behind() {
        local repo_dir="$1"
        local local_ref="$2"
        local remote_ref="$3"

        if [[ -n "$local_ref" ]]; then
            git -C "$repo_dir" rev-list --count "${local_ref}..${remote_ref}" 2>/dev/null
        else
            git -C "$repo_dir" rev-list --count "$remote_ref" 2>/dev/null
        fi
    }

    function pullall_write_result() {
        local result_file="$1"
        local result_kind="$2"
        local repo_name="$3"
        local message="$4"

        {
            print -- "$result_kind"
            print -- "$repo_name"
            print -- "$message"
        } > "$result_file"
    }

    function pullall_process_repo() {
        local dir="$1"
        local result_file="$2"
        local repo_name default_branch remote_ref checked_out_path current_worktree local_ref behind_count

        repo_name="${dir:t}"

        default_branch="$(
            git -C "$dir" ls-remote --symref origin HEAD 2>/dev/null |
                awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }'
        )"

        if [[ -z "$default_branch" ]]; then
            pullall_write_result "$result_file" "skipped" "$repo_name" "could not determine default branch, skipping."
            return
        fi

        if ! git -C "$dir" fetch --quiet origin "$default_branch"; then
            pullall_write_result "$result_file" "failed" "$repo_name" "fetch failed."
            return
        fi

        remote_ref="$(git -C "$dir" rev-parse --verify "refs/remotes/origin/$default_branch" 2>/dev/null)"
        if [[ -z "$remote_ref" ]]; then
            pullall_write_result "$result_file" "failed" "$repo_name" "remote ref not found after fetch."
            return
        fi

        checked_out_path=""
        current_worktree=""

        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                current_worktree=""
                continue
            fi

            if [[ "$line" == worktree\ * ]]; then
                current_worktree="${line#worktree }"
                continue
            fi

            if [[ "$line" == "branch refs/heads/$default_branch" ]]; then
                checked_out_path="$current_worktree"
                break
            fi
        done < <(git -C "$dir" worktree list --porcelain 2>/dev/null)

        local_ref="$(git -C "$dir" rev-parse --verify "refs/heads/$default_branch" 2>/dev/null)"
        behind_count="$(pullall_count_behind "$dir" "$local_ref" "$remote_ref")"

        if [[ -n "$checked_out_path" ]]; then
            if [[ -n "$local_ref" ]] && [[ "$local_ref" == "$remote_ref" ]]; then
                pullall_write_result "$result_file" "current" "$repo_name" "Already up-to-date."
                return
            fi

            if ! git -C "$checked_out_path" merge --ff-only "refs/remotes/origin/$default_branch" >/dev/null 2>&1; then
                pullall_write_result "$result_file" "skipped" "$repo_name" "fast-forward failed. The worktree may be dirty or the branch may have diverged."
                return
            fi

            pullall_write_result "$result_file" "success" "$repo_name" "Pulled ${behind_count} commits."
            return
        fi

        if [[ -z "$local_ref" ]]; then
            if git -C "$dir" update-ref "refs/heads/$default_branch" "$remote_ref" >/dev/null 2>&1; then
                pullall_write_result "$result_file" "success" "$repo_name" "Pulled ${behind_count} commits (worktree untouched)."
            else
                pullall_write_result "$result_file" "failed" "$repo_name" "could not create local branch ref."
            fi
            return
        fi

        if [[ "$local_ref" == "$remote_ref" ]]; then
            pullall_write_result "$result_file" "current" "$repo_name" "Already up-to-date."
            return
        fi

        if ! git -C "$dir" merge-base --is-ancestor "$local_ref" "$remote_ref" >/dev/null 2>&1; then
            pullall_write_result "$result_file" "skipped" "$repo_name" "local branch has diverged from origin, skipping."
            return
        fi

        if git -C "$dir" update-ref "refs/heads/$default_branch" "$remote_ref" "$local_ref" >/dev/null 2>&1; then
            pullall_write_result "$result_file" "success" "$repo_name" "Pulled ${behind_count} commits (worktree untouched)."
        else
            pullall_write_result "$result_file" "failed" "$repo_name" "could not update branch ref."
        fi
    }

    local GREEN=$'%F{green}'
    local YELLOW=$'%F{yellow}'
    local RED=$'%F{red}'
    local CYAN=$'%F{cyan}'
    local RESET=$'%f'

    local verbose=0
    local parent_dir="."
    local arg

    for arg in "$@"; do
        case "$arg" in
            -v|--verbose)
                verbose=1
                ;;
            -*)
                print -P "${RED}Unknown flag: ${arg}${RESET}"
                return 1
                ;;
            *)
                if [[ "$parent_dir" != "." ]]; then
                    print -P "${RED}Usage: pullall [-v] [dir]${RESET}"
                    return 1
                fi
                parent_dir="$arg"
                ;;
        esac
    done

    local parent_abs
    parent_abs="$(builtin cd "$parent_dir" 2>/dev/null && pwd -P)"

    if [[ -z "$parent_abs" ]]; then
        print -P "${RED}Parent directory does not exist or is not accessible: ${parent_dir}${RESET}"
        return 1
    fi

    local max_jobs="${PULL_ALL_JOBS:-8}"
    local success=0
    local current=0
    local skipped=0
    local failed=0
    local results_dir
    local -a repos result_files running_pids active_pids
    local dir result_file pid result_kind repo_name message

    results_dir="$(mktemp -d "${TMPDIR:-/tmp}/pull-all.XXXXXX")" || return 1

    print -P "${CYAN}Scanning for git repositories in: ${parent_abs}${RESET}"
    print

    for dir in "$parent_abs"/*(/N); do
        if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            continue
        fi

        if [[ "$(git -C "$dir" rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
            continue
        fi

        repos+=("$dir")
    done

    for dir in "${repos[@]}"; do
        result_file="$results_dir/${#result_files[@]}.result"
        result_files+=("$result_file")

        while (( ${#running_pids[@]} >= max_jobs )); do
            active_pids=()
            for pid in "${running_pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    active_pids+=("$pid")
                fi
            done
            running_pids=("${active_pids[@]}")
            (( ${#running_pids[@]} < max_jobs )) && break
            sleep 0.05
        done

        pullall_process_repo "$dir" "$result_file" &
        running_pids+=("$!")
    done

    for pid in "${running_pids[@]}"; do
        wait "$pid"
    done

    for result_file in "${result_files[@]}"; do
        if [[ ! -f "$result_file" ]]; then
            continue
        fi

        exec 3< "$result_file"
        IFS= read -r result_kind <&3
        IFS= read -r repo_name <&3
        IFS= read -r message <&3
        exec 3<&-

        case "$result_kind" in
            success)
                print -P "${GREEN}${repo_name}${RESET} - ${message}"
                (( success++ ))
                ;;
            current)
                (( current++ ))
                if (( verbose )); then
                    print -P "${GREEN}${repo_name}${RESET} - ${message}"
                fi
                ;;
            skipped)
                print -P "${YELLOW}${repo_name}${RESET} - ${message}"
                (( skipped++ ))
                ;;
            failed)
                print -P "${RED}${repo_name}${RESET} - ${message}"
                (( failed++ ))
                ;;
        esac
    done

    command rm -rf "$results_dir"
    unfunction pullall_count_behind pullall_write_result pullall_process_repo

    print
    print -P "${CYAN}Done.${RESET} ${GREEN}${success} updated${RESET} · ${GREEN}${current} current${RESET} · ${YELLOW}${skipped} skipped${RESET} · ${RED}${failed} failed${RESET}"
}

# `get_default_branch` returns the name of the default branch (without `origin/` prefix)
# Tries local remote HEAD ref first, then queries the remote, then falls back to local branch detection
get_default_branch() {
    # Fast path: local symbolic ref set by git (requires `git remote set-head origin --auto` or initial clone)
    local branch
    branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if [[ -n "$branch" ]]; then
        echo "$branch"
        return 0
    fi

    # Network path: ask the remote directly
    branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
    if [[ -n "$branch" ]] && [[ "$branch" != "(unknown)" ]]; then
        echo "$branch"
        return 0
    fi

    # No remote: check common default branch names locally
    if git show-ref --verify --quiet refs/heads/main; then
        echo "main"
    elif git show-ref --verify --quiet refs/heads/master; then
        echo "master"
    fi
}

# `commit [--amend] [msg]` to make a commit, quotes optional, amend optional
# commit "some" "message here" -> creates commit with title "some", description "message here"
# commit some message -> creates commit with title "some message"
# commit --amend "fix bug" -> amends commit with "fix bug"
# commit --amend fix bug -> amends commit with "fix bug"
# commit --amend -> runs `git commit --amend --no-edit``
commit() {
    require_git_repo || return
    require_args 'usage: commit [--amend] [msg]' 1 "$@" || return

    # Check if on default branch
    local current_branch=$(git branch --show-current)
    local default_branch=$(get_default_branch)

    if [[ "$current_branch" == "$default_branch" ]]; then
        if ! confirm "Warning: You are on the default branch '$default_branch'. Continue with commit?"; then
            return 1
        fi
    fi

    # Check if remote branch exists (only relevant if the repo has a remote at all)
    if has_remote && ! git rev-parse --verify "origin/$current_branch" &>/dev/null; then
        if ! confirm "No remote branch 'origin/$current_branch' exists (may have been merged). Continue with commit?" y; then
            return 1
        fi
    fi

    git add -A

    local amend=0
    local no_verify=0
    local args=()
    local single_message=-1

    # process arguments
    for arg in "$@"; do
        if [[ "$arg" == "--amend" ]]; then
            amend=1
        elif [[ "$arg" == "--no-verify" ]]; then
            no_verify=1
        elif [[ "$arg" == -* ]]; then
            # Skip unrecognized flags to prevent them from being included in the commit message
            echo "Warning: ignoring unrecognized flag '$arg'"
        else
            args+=("$arg")

            # overwrite single_message on the first non-`--amend` argument
            if (( single_message == -1 )); then
                if [[ "$arg" != "${(q)arg}" ]]; then
                    # first arg starts with a ' or "
                    single_message=0
                else
                    single_message=1
                fi
            fi
        fi
    done

    # construct git_commit_args
    local git_commit_args=()

    if (( no_verify )); then
        git_commit_args+=("--no-verify")
    fi

    if (( amend )); then
        if (( ${#args[@]} == 0 )); then
            # no additional args; early exit
            git commit --amend --no-edit "${git_commit_args[@]}"
            return
        fi

        git_commit_args+=("--amend")
    fi

    if (( single_message )); then
        git_commit_args+=("-m" "${args[*]}")
    else
        for arg in "${args[@]}"; do
            git_commit_args+=("-m" "$arg")
        done
    fi

    # execute git commit
    git commit "${git_commit_args[@]}"
}

# `push [<msg>] [-f]` to push to remote repo (after committing if <msg> is given)
push() {
    require_git_remote || return 1

    local force_flag=""
    local args=()

    # Parse arguments to extract -f flag; drop other unrecognized flags
    for arg in "$@"; do
        if [[ "$arg" == "-f" ]]; then
            force_flag="--force-with-lease"
        elif [[ "$arg" == -* ]]; then
            # Skip unrecognized flags to prevent them from being included in the commit message
            echo "Warning: ignoring unrecognized flag '$arg'"
        else
            args+=("$arg")
        fi
    done

    # If force push is requested, check for divergence
    if [[ -n "$force_flag" ]]; then
        # Get current branch name
        local current_branch=$(git rev-parse --abbrev-ref HEAD)

        # Check if local and remote have diverged
        git fetch --quiet 2>/dev/null
        local local_commit=$(git rev-parse HEAD 2>/dev/null)
        local remote_commit=$(git rev-parse origin/$current_branch 2>/dev/null)

        if [[ -n "$remote_commit" && "$local_commit" != "$remote_commit" ]]; then
            local merge_base=$(git merge-base HEAD origin/$current_branch 2>/dev/null) # get common ancestor
            if [[ "$merge_base" != "$local_commit" && "$merge_base" != "$remote_commit" ]]; then
                if ! confirm "Local and remote branches have diverged. Force push to '$current_branch'?"; then
                    return 1
                fi
            fi
        fi
    fi

    # If there are non-flag arguments, commit first
    if [[ ${#args[@]} -gt 0 ]]; then
        commit "${args[@]}" && git push $force_flag
    else
        git push $force_flag
    fi
}

# `switch [<name>]` to switch to branch <name>, creating it if it doesn't exist
# if <name> is "-", switch to previous branch
# if <name> is omitted, switch to default branch
switch() {
    require_git_repo || return

    local branch="$1"

    if [ -z "$branch" ]; then
        local default_branch=$(get_default_branch)
        if [[ -z "$default_branch" ]]; then
            echo "Error: Could not determine default branch"
            return 1
        fi
        git checkout "$default_branch"
        return 0
    fi

    # Handle switch to previous branch
    if [ "$branch" = "-" ]; then
        git switch -
        return 0
    fi

    # Check whether this repo has a remote named 'origin'
    local has_remote=false
    if has_remote; then
        has_remote=true
    fi

    # Fetch latest remote info
    if [ "$has_remote" = true ]; then
        git fetch --quiet
    fi

    # Check if branch exists locally
    if git show-ref --verify --quiet refs/heads/"$branch"; then
        git switch "$branch"
        return 0
    fi

    # Check if branch exists on remote
    if [ "$has_remote" = true ] && git show-ref --verify --quiet refs/remotes/origin/"$branch"; then
        git switch -c "$branch" origin/"$branch"
        return 0
    fi

    # Check for substring match in local branches
    local local_matches
    local_matches=$(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -F "$branch")

    # Check for substring match in remote branches
    local remote_matches=""
    if [ "$has_remote" = true ]; then
        remote_matches=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin/ | grep -F "$branch" | grep -v '/HEAD$' | sed 's|^origin/||')
    fi

    # Merge, deduplicate, preserving local-first order
    local matching_branches
    matching_branches=$(printf '%s\n' $local_matches $remote_matches | awk '!seen[$0]++')

    if [ -n "$matching_branches" ]; then
        local match_count
        match_count=$(echo "$matching_branches" | wc -l | tr -d '[:space:]')

        if [ "$match_count" -eq 1 ]; then
            branch=$(echo "$matching_branches" | tr -d '[:space:]')
            git switch "$branch" 2>/dev/null || git switch -c "$branch" --track origin/"$branch"
            return 0
        else
            # Map local branches to whether they track a live upstream
            local -A branch_is_local branch_has_upstream
            local refname upstream track
            while IFS=$'\t' read -r refname upstream track; do
                branch_is_local[$refname]=1
                [[ -n "$upstream" && "$track" != *gone* ]] && branch_has_upstream[$refname]=1
            done < <(git for-each-ref --format='%(refname:short)%09%(upstream)%09%(upstream:track)' refs/heads/)

            echo "Multiple branches match '$branch':"
            local i=1
            while IFS= read -r candidate; do
                if (( ${+branch_is_local[$candidate]} )) && (( ! ${+branch_has_upstream[$candidate]} )); then
                    print -P -- "$i) %F{8}${candidate//\%/%%}%f"
                else
                    echo "$i) $candidate"
                fi
                i=$((i + 1))
            done <<< "$matching_branches"

            local selection selected_branch
            while true; do
                echo -n "Select branch number (or q to cancel): "
                IFS= read -r selection

                if [ "$selection" = "q" ] || [ "$selection" = "Q" ]; then
                    return 1
                fi

                if ! echo "$selection" | grep -Eq '^[0-9]+$'; then
                    echo "Invalid selection. Enter a number between 1 and $match_count, or q to cancel."
                    continue
                fi

                if [ "$selection" -lt 1 ] || [ "$selection" -gt "$match_count" ]; then
                    echo "Selection out of range. Enter a number between 1 and $match_count, or q to cancel."
                    continue
                fi

                selected_branch=$(echo "$matching_branches" | sed -n "${selection}p")
                git switch "$selected_branch" 2>/dev/null || git switch -c "$selected_branch" --track origin/"$selected_branch"
                return 0
            done
        fi
    fi

    # Branch doesn't exist locally (or remotely, if applicable)
    echo "Branch '$branch' doesn't exist."

    if [ "$has_remote" = true ]; then
        confirm "Create branch '$branch' remotely and locally?" y || return 1
        git switch -c "$branch"
        git push -u origin "$branch"
    else
        confirm "Create branch '$branch' locally?" y || return 1
        git switch -c "$branch"
    fi
}

# `reset_to_origin` to hard reset the current branch to origin/<current_branch>
reset_to_origin() {
    require_git_remote || return 1

    local current_branch
    current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)

    if [[ -z "$current_branch" ]]; then
        echo "Error: not on a branch"
        return 1
    fi

    if ! git rev-parse --verify "origin/$current_branch" &>/dev/null; then
        echo "Error: remote branch 'origin/$current_branch' does not exist"
        return 1
    fi

    if [[ -n "$(git status --porcelain)" ]]; then
        if ! confirm "Uncommitted changes detected. Discard all local changes and reset '$current_branch' to 'origin/$current_branch'?"; then
            return 1
        fi
    fi

    git reset --hard "origin/$current_branch"
}

# `stash [<msg>]` to stash all current changes with optional message
stash() {
    require_git_repo || return

    git add -A
    if [[ $# -gt 0 ]]; then
        git stash push -m "$*"
    else
        git stash
    fi
}

# `unstash` to stash pop
unstash() {
    require_git_repo || return
    git stash pop
}

# `clone [flags] <git URL | user/repo> [<dirname>]` to clone a repo into ~/Developer and cd into it,
# regardless of the current directory
# <dirname> defaults to the repo name. Flags are passed to `git clone`.
clone() {
    local usage='usage: clone [flags] git_url|user/repo [dirname]'
    require_args "$usage" 1 "$@" || return

    local dev_dir="$HOME/Developer"
    local url="" name="" arg target
    local -a flags

    for arg in "$@"; do
        if [[ "$arg" == -* ]]; then
            flags+=("$arg")
        elif [[ -z "$url" ]]; then
            url="$arg"
        elif [[ -z "$name" ]]; then
            name="$arg"
        else
            echo "$usage"
            return 1
        fi
    done

    if [[ -z "$url" ]]; then
        echo "$usage"
        return 1
    fi

    # Expand the `user/repo` shorthand into a GitHub SSH URL
    if [[ "$url" != *://* && "$url" != *@*:* && "$url" =~ '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' ]]; then
        url="git@github.com:${url%.git}.git"
    fi

    # Derive the directory name from the URL
    if [[ -z "$name" ]]; then
        name="${url%/}"
        name="${name:t}"
        name="${name##*:}"
        name="${name%.git}"
    fi

    if [[ -z "$name" ]]; then
        echo "Error: could not determine a directory name from '$url'"
        return 1
    fi

    [[ "$name" == /* ]] && target="$name" || target="$dev_dir/$name"

    if [[ -d "$target" ]]; then
        echo "Directory already exists: $target"
        confirm "cd into it instead of cloning?" y || return 1
        cd "$target"
        return
    fi

    mkdir -p "${target:h}" || return
    git clone "${flags[@]}" "$url" "$target" || return
    cd "$target"
}

# `merge <src> <dst>` to merge branch `src` into branch `dst`
merge() {
    require_git_repo || return
    require_args 'usage: merge src dst' 2 "$@" || return

    local src=$1
    local dst=$2

    # Fetch latest remote info
    git fetch --quiet

    # Check if src branch is behind remote
    if git show-ref --verify --quiet refs/remotes/origin/"$src"; then
        local src_local=$(git rev-parse "$src" 2>/dev/null)
        local src_remote=$(git rev-parse origin/"$src" 2>/dev/null)

        if [[ -n "$src_local" && -n "$src_remote" ]]; then
            local src_merge_base=$(git merge-base "$src" origin/"$src" 2>/dev/null)
            if [[ "$src_merge_base" == "$src_local" && "$src_local" != "$src_remote" ]]; then
                if confirm "Local branch '$src' is behind remote. Pull latest changes? (Ctrl+C to cancel entire operation)" y; then
                    git switch "$src" && git pull || return
                fi
            fi
        fi
    fi

    # Check if dst branch is behind remote
    if git show-ref --verify --quiet refs/remotes/origin/"$dst"; then
        local dst_local=$(git rev-parse "$dst" 2>/dev/null)
        local dst_remote=$(git rev-parse origin/"$dst" 2>/dev/null)

        if [[ -n "$dst_local" && -n "$dst_remote" ]]; then
            local dst_merge_base=$(git merge-base "$dst" origin/"$dst" 2>/dev/null)
            if [[ "$dst_merge_base" == "$dst_local" && "$dst_local" != "$dst_remote" ]]; then
                if confirm "Local branch '$dst' is behind remote. Pull latest changes? (Ctrl+C to cancel entire operation)" y; then
                    git switch "$dst" && git pull || return
                fi
            fi
        fi
    fi

    # Confirm the merge
    if ! confirm "About to merge '$src' into '$dst'. Proceed?" y; then
        return 1
    fi

    git switch "$dst" && git merge "$src"
}

# `giturl [-o]` to print the web address where I can find the current repository
# -o flag: open the URL in the browser instead of copying to clipboard
giturl() {
    require_git_repo || return

    local open_in_browser=0

    # Check for -o flag
    if [[ "$1" == "-o" ]]; then
        open_in_browser=1
    fi

    # Run git remote -v, extract the first upstream URL, and convert it to a valid web address
    local upstream_url=$(git remote -v | awk '{print $2}' | grep -E '^https?|^git' | head -n 1) 2> /dev/null

    # Print the converted URL
    if [[ -n "$upstream_url" ]]; then
        if [[ "$upstream_url" == git* ]]; then
            # Convert git URL to HTTPS
            upstream_url=$(echo "$upstream_url" | sed -E 's|^git@([^:]+):(.+)(\.git)?$|https://\1/\2|')
        fi

        # Remove the ".git"
        upstream_url=$(echo "$upstream_url" | sed -E 's/\.git$//')

        if [[ $open_in_browser -eq 1 ]]; then
            open "$upstream_url"
            echo "Opened in browser:\n$upstream_url"
        else
            echo "$upstream_url" | pbcopy
            echo "Copied to clipboard:\n$upstream_url"
        fi
    else
        echo "No Git upstream URL found."
    fi
}
