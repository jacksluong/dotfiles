#!/bin/zsh

# `zedkill` to pick and kill processes that AI agents in Zed left running
# Finds commands run by agents inside Zed, plus orphans left behind after their shell or Zed quit
zedkill() {
    emulate -L zsh
    setopt extended_glob

    local zed_support="$HOME/Library/Application Support/Zed"
    local zed_marker="__CFBundleIdentifier=dev.zed.Zed"  # env var inherited by everything Zed starts
    local shell_re='^(sh|bash|zsh|dash|fish)$'

    local -A ppid_of pgid_of etime_of cmd_of exe_of kids_of
    local -A skip marked_pgids cwd_of ports_of
    local -a zed_pids orphans queue roots entries
    local pid ppid pgid etime cmd exe p c line n

    ## --- Snapshot processes owned by the current user ---

    while read -r pid ppid pgid etime cmd; do
        ppid_of[$pid]=$ppid pgid_of[$pid]=$pgid etime_of[$pid]=$etime cmd_of[$pid]=$cmd
        kids_of[$ppid]+="$pid "
        [[ $cmd == */Zed*.app/Contents/MacOS/zed(| *) && $cmd != *--crash-handler* ]] && zed_pids+=($pid)
        [[ $ppid == 1 ]] && orphans+=($pid)
    done < <(ps -ww -U "$USER" -o pid=,ppid=,pgid=,etime=,command=)
    while read -r pid exe; do
        exe_of[$pid]=$exe
    done < <(ps -ww -U "$USER" -o pid=,comm=)

    # never offer this shell or anything above it
    p=$$
    while [[ -n $p && $p != 1 ]]; do skip[$p]=1; p=$ppid_of[$p]; done

    ## --- Find candidates ---

    # Under a running Zed, agent commands run in shells started by an agent (Claude Code, Codex, etc.)
    # or by Zed itself (native agent, tasks). Terminal panel shells go through /usr/bin/login, so they are left out.
    queue=($zed_pids)
    while (( $#queue )); do
        p=$queue[1]; shift queue
        for c in ${=kids_of[$p]}; do
            cmd=$cmd_of[$c]
            if [[ $cmd == *"$zed_support/external_agents/"* ]]; then
                queue+=($c)
            elif [[ ${exe_of[$c]:t} =~ $shell_re && $cmd == *" -"[a-z]#c[a-z]#" "* ]]; then
                # show what the shell runs, or the shell itself if it runs a builtin
                if [[ -n ${kids_of[$c]} ]]; then roots+=(${=kids_of[$c]}); else roots+=($c); fi
            fi
        done
    done

    # Orphans keep Zed's env var after their shell exits, unless they are Apple binaries that hide their env.
    # Those still share a process group with a marked orphan, so match on that too.
    if (( $#orphans )); then
        while read -r pid; do
            [[ $cmd_of[$pid] == */Zed*.app/* ]] && continue
            roots+=($pid)
            marked_pgids[$pgid_of[$pid]]=1
        done < <(ps -E -ww -o pid=,command= -p ${(j:,:)orphans} | awk -v m="$zed_marker" 'index($0, " " m) { print $1 }')
        for pid in $orphans; do
            [[ -n $marked_pgids[$pgid_of[$pid]] && $pgid_of[$pid] != $pid ]] && roots+=($pid)
        done
    fi

    for p in ${(u)roots}; do
        [[ -z $skip[$p] && $ppid_of[$p] != $$ && -n $cmd_of[$p] ]] && entries+=($p)
    done
    if (( ! $#entries )); then
        echo "No leftover agent processes found"
        return 0
    fi

    ## --- Helper functions ---

    # Collect a process and all of its descendants
    # Sets result in _tree array (avoids subshell)
    local -a _tree
    _zk_collect_tree() {
        local -a todo=($1)
        _tree=()
        while (( $#todo )); do
            _tree+=($todo[1])
            todo+=(${=kids_of[$todo[1]]})
            shift todo
        done
    }

    # Build a short label from a full command line, e.g. `/path/to/node /path/to/next dev` becomes `next dev`
    # Sets result in REPLY
    _zk_command_label() {
        local cmd=$cmd_of[$1] exe=$exe_of[$1] name args
        local -a words
        if [[ $cmd == *shell-snapshots/snapshot-*"eval '"* ]]; then
            # Claude Code wrapper shell: show the command it evaluates
            args=${cmd#*eval \'}
            args=${args%\' \< /dev/null*}
            REPLY=${args//\'\"\'\"\'/\'}
            return
        fi
        if [[ ${exe:t} =~ $shell_re && $cmd == *" -"[a-z]#c[a-z]#" "* ]]; then
            REPLY=${cmd#* -[a-z]#c[a-z]# }
            return
        fi
        if [[ $cmd == "$exe"(| *) ]]; then
            name=${exe:t} args=${cmd#"$exe"}
        else
            name=${${cmd%% *}:t} args=${cmd#* }
            [[ $args == $cmd ]] && args=''
        fi
        words=(${=args})
        # drop the interpreter when it runs a script, e.g. `node pnpm.cjs dev` becomes `pnpm dev`
        if [[ $name == (node|bun|deno|ruby|[Pp]ython*) && $words[1] == */* ]]; then
            name=${${words[1]:t}%.(c|m|)js}
            shift words
        fi
        REPLY="$name ${(j: :)${words//(#m)*\/*/${MATCH:t}}}"
        REPLY=${REPLY% }
    }

    # Turn ps etime ([[dd-]hh:]mm:ss) into e.g. `2d 3h`, `4h 12m`, `5m`, `30s`
    # Sets result in REPLY, and the age in seconds in _secs
    _zk_format_age() {
        local -a parts=(${(s.:.)${1/-/:}})
        local d=0 h=0 m s
        s=${parts[-1]} m=${parts[-2]}
        (( $#parts >= 3 )) && h=${parts[-3]}
        (( $#parts == 4 )) && d=${parts[1]}
        d=$((10#$d)) h=$((10#$h)) m=$((10#$m)) s=$((10#$s))
        _secs=$(( ((d * 24 + h) * 60 + m) * 60 + s ))
        if (( d )); then REPLY="${d}d ${h}h"
        elif (( h )); then REPLY="${h}h ${m}m"
        elif (( m )); then REPLY="${m}m"
        else REPLY="${s}s"
        fi
    }

    # Cut a string to a width, ending with … when it does not fit
    # Sets result in REPLY
    _zk_truncate_to() {
        if (( ${#1} > $2 )); then REPLY="${1[1,$2-1]}…"; else REPLY=$1; fi
    }

    ## --- Gather row details ---

    # newest first
    local _secs
    local -a by_age
    for p in $entries; do _zk_format_age $etime_of[$p]; by_age+=("$_secs $p"); done
    entries=(${${(n)by_age}#* })

    # working directories and listening TCP ports, one lsof call each
    local -a all_pids
    for p in $entries; do _zk_collect_tree $p; all_pids+=($_tree); done
    while read -r line; do
        case $line in
            p*) pid=${line#p};;
            n*) cwd_of[$pid]=${line#n};;
        esac
    done < <(lsof -a -d cwd -p ${(j:,:)all_pids} -Fn 2>/dev/null)
    while read -r line; do
        case $line in
            p*) pid=${line#p};;
            n*) [[ " $ports_of[$pid] " != *" :${line##*:} "* ]] && ports_of[$pid]+=":${line##*:} ";;
        esac
    done < <(lsof -nP -a -u "$USER" -iTCP -sTCP:LISTEN -Fn 2>/dev/null)

    # each row reads `command (project, age, ports)`
    local -a labels details parts
    local tree_ports
    for p in $entries; do
        _zk_command_label $p; labels+=("$REPLY")
        _zk_format_age $etime_of[$p]
        _zk_collect_tree $p
        tree_ports=''
        for c in $_tree; do tree_ports+=$ports_of[$c]; done
        parts=("${${cwd_of[$p]:t}:-?}" "$REPLY" ${(u)=tree_ports})
        details+=("(${(j:, :)parts})")
    done

    ## --- Interactive picker ---

    local _bold=$'\e[1m' _dim=$'\e[2m' _sgr0=$'\e[0m' _el=$'\e[K' _civis=$'\e[?25l' _cnorm=$'\e[?25h'
    local total=$#entries cursor=1 top=1 key i
    local visible=$(( LINES - 4 < total ? LINES - 4 : total ))
    (( visible < 1 )) && visible=1
    local -a selected
    for i in {1..$total}; do selected[i]=0; done

    _zk_draw() {
        local i mark pointer width
        (( cursor < top )) && top=$cursor
        (( cursor >= top + visible )) && top=$(( cursor - visible + 1 ))
        printf '\r%s%s\n' "${_bold}Select processes to kill${_sgr0}" "$_el"
        printf '%s%s\n' "${_dim}↑/↓ move · space toggle · a toggle all · enter kill · q quit${_sgr0}" "$_el"
        for (( i = top; i < top + visible; i++ )); do
            (( selected[i] )) && mark='◉' || mark='◯'
            (( i == cursor )) && pointer="${_bold}›" || pointer=' '
            # shorten the command, not the details, when the row is too wide
            width=$(( COLUMNS - 5 - ${#details[i]} ))
            (( width < 20 )) && width=20
            _zk_truncate_to "$labels[i]" $width
            printf '%s %s %s%s %s%s%s\n' "$pointer" "$mark" "$REPLY" "$_sgr0" "$_dim" "$details[i]" "$_sgr0$_el"
        done
        if (( total > visible )); then
            printf '%s%s' "${_dim}showing $top-$(( top + visible - 1 )) of $total${_sgr0}" "$_el"
        else
            printf '%s' "$_el"
        fi
    }

    # move the cursor back to the top of the picker before redrawing
    _zk_redraw() {
        printf '\r\e[%dA' $(( visible + 2 ))
        _zk_draw
    }

    trap 'printf "%s\n" "$_cnorm"; return 130' INT
    printf '%s' "$_civis"
    _zk_draw
    while true; do
        read -sk1 key
        if [[ $key == $'\e' ]]; then
            read -sk2 -t 0.1 key || key=$'\e'
        fi
        case $key in
            '[A'|k) (( cursor = cursor > 1 ? cursor - 1 : total ));;
            '[B'|j) (( cursor = cursor < total ? cursor + 1 : 1 ));;
            ' ') (( selected[cursor] = ! selected[cursor] ));;
            a)
                n=0
                for i in {1..$total}; do (( n += selected[i] )); done
                for i in {1..$total}; do selected[i]=$(( n < total )); done
                ;;
            $'\n'|$'\r') break;;
            q|$'\e') printf '\n%s' "$_cnorm"; echo "Cancelled"; return 0;;
        esac
        _zk_redraw
    done
    printf '\n%s' "$_cnorm"
    trap - INT

    ## --- Kill selected processes and their descendants ---

    local -a targets names
    for i in {1..$total}; do
        (( selected[i] )) || continue
        _zk_collect_tree $entries[i]
        targets+=($_tree)
        names+=("$labels[i]")
    done
    if (( ! $#targets )); then
        echo "Nothing selected"
        return 0
    fi

    kill -TERM $targets 2>/dev/null
    # give processes up to 3 seconds to exit before forcing them
    local -a alive
    for i in {1..30}; do
        alive=()
        for p in $targets; do kill -0 $p 2>/dev/null && alive+=($p); done
        (( $#alive )) || break
        sleep 0.1
    done
    (( $#alive )) && kill -KILL $alive 2>/dev/null

    for line in $names; do echo "Killed $line"; done
}
