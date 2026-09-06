#!/bin/bash

# `icd` to activate an interactive way to navigate through directories
# Note: for consistency, treat all arrays as 0-indexed
icd() {
    # --- Terminology ---
    # browser:              The interactive area below the search line, displaying the
    #                       directory menu (left) and file columns (right).
    # visible row:          A single horizontal line in the browser. Each row may show a
    #                       directory entry on the left and/or file names on the right.
    # all directories:      Every subdirectory in the current working directory.
    # filtered directories: The subset of all directories matching the current search string.
    # visible directories:  The subset of filtered directories currently displayed on screen
    #                       (at most MAX_VISIBLE_DIRS, and determined by scroll position).
    # file column:          A vertical column of file names to the right of the directory menu.
    #                       The number of columns depends on terminal width.
    # file text:            The pre-computed text displaying files for one visible row (all columns combined).
    # file slot:            One cell in the file grid (one file name within one column on one row).
    #                       Total slots = num_file_cols × num_visible_rows.
    #
    # --- Notable variable naming conventions ---
    # index:                Position within the filtered_dirs array (0-based).
    # vindex:               "Visible index" — position within the visible rows on screen (0-based).
    # first_visible_dir_index: Index in filtered_dirs of the topmost visible directory,
    #                       determining the current scroll position.
    # _truncated:           Shared output variable set by truncate_name() to avoid subshells.
    # Variables prefixed with _ (e.g., _bold, _el) are pre-computed terminal escape sequences.

    local MAX_VISIBLE_DIRS=10 MAX_DIR_WIDTH=60 MAX_NAME_WIDTH=20 SEARCH_ICON="\uf422"
    local MIN_FILE_COL_WIDTH=21 DIR_COL_WIDTH=26  # MAX_NAME_WIDTH (20) + separator (1); prefix region (4) + MAX_NAME_WIDTH (20) + padding (1) + trailing space (1)
    local SEARCH_PREFIX=" $(tput bold)${SEARCH_ICON}$(tput sgr0)$(tput el) "

    local is_bash=$([[ -n $BASH ]] && echo true || echo false)
    local is_zsh=$([[ -n $ZSH_NAME ]] && echo true || echo false)

    # Pre-compute terminal escape sequences for performance
    local _bold=$(tput bold)      # bold text
    local _dim=$(tput dim)        # dim/faint text
    local _sgr0=$(tput sgr0)      # reset all attributes
    local _setab7=$(tput setab 7) # set background color to white
    local _setaf0=$(tput setaf 0) # set foreground color to black
    local _setaf3=$(tput setaf 3) # set foreground color to yellow
    local _el=$(tput el)          # clear from cursor to end of line
    local _ed=$(tput ed)          # clear from cursor to end of screen
    local _civis=$(tput civis)    # hide cursor
    local _cnorm=$(tput cnorm)    # show cursor (normal visibility)
    local _sc=$(tput sc)          # save cursor position
    local _rc=$(tput rc)          # restore cursor position
    local _cud1=$'\e[B'           # move cursor down one line (hardcoded; tput cud1 returns \n which gets stripped by $())
    local _smul=$(tput smul)      # start underline mode
    local _cuf4=$(tput cuf 4)     # move cursor forward 4 columns
    local _dir_pad=''             # blank string of DIR_COL_WIDTH spaces, used to pad file-only rows
    printf -v _dir_pad "%${DIR_COL_WIDTH}s" ''

    # Expected output layout:
    # - heading line: current directory path (fixed)
    # - instructions line: keyboard controls (fixed)
    # - search line: search icon + typed search string (fixed)
    # - browser: directory menu + file columns (num_visible_rows rows)

    ## --- Helper functions ---

    # Read a single keypress in zsh and translate it to a command name
    zsh_key_input() {
        read -sk1 key
        if [[ $key = $'\e' ]]; then
            read -sk2 -t 0.1 key
            [[ -z $key ]] && key=$'\e'  # no follow-up character means escape key was pressed
        fi
        translate_input "$key"
    }

    # Read a single keypress in bash and translate it to a command name
    bash_key_input() {
        IFS='' read -rsn1 key
        if [[ $key = $'\e' ]]; then
            read -rsn2 -t 0.1 key
            [[ -z $key ]] && key=$'\e'  # no follow-up character means escape key was pressed
        fi
        translate_input "$key"
    }

    # Read a single keypress and translate it (auto-detects shell)
    read_key() {
        if [[ $is_bash = true ]]; then
            bash_key_input
        else
            zsh_key_input
        fi
    }

    # Convert raw key input into readable command names (enter, backspace, arrow keys, etc.)
    translate_input() {
        # args: keyboard input
        case $1 in
            $'\n'|'')      echo enter;;
            $'\177'|$'\b') echo backspace;;
            $'\t')         echo tab;;
            $'\e')         echo escape;;
            "[A")          echo up;;
            "[B")          echo down;;
            "[C")          echo right;;
            "[D")          echo left;;
            *)             printf '%s\n' "$1";;
        esac
    }

    # Get element at given index from array
    # Args: index, array
    index_array() {
        local i=$1
        shift 1
        printf '%s\n' "${@:$((i+1)):1}" # only way for array indexing to work for both bash and zsh
        # ${@:0:1} will return the function name
    }

    # Find the index of an element in an array, returns -1 if not found
    # Args: element, array
    index_of() {
        local e=$1
        shift 1

        local i=0
        for s in "$@"; do
            if [[ $s = "$e" ]]; then
                echo $i
                return
            fi
            ((i++))
        done
        echo -1
    }

    # Escape special regex characters so they're treated as literal text in search
    # Args: string
    local regex_chars='$^.?+*(){}[]/'
    escape_regex() {
        local str=$1 c=''
        for ((i=0; i<${#regex_chars}; i++)); do
            c=${regex_chars:$i:1}
            str=${str//"$c"/\\$c}
        done
        printf '%s\n' "$str"  # printf, not echo: echo swallows leading '-' as an option flag
    }

    # Convert string to lowercase, used for case-insensitive search
    # Args: string
    to_lowercase() {
        local str=$1
        if [[ $is_bash = true ]]; then
            printf '%s' "$str" | tr '[:upper:]' '[:lower:]'
        else
            printf '%s\n' "${str:l}"
        fi
    }

    # Truncate a name to max width, adding … if truncated
    # Sets result in _truncated variable (avoids subshell)
    # Args: string, max_width
    truncate_name() {
        if [[ ${#1} -gt $2 ]]; then
            _truncated="${1:0:$(($2 - 1))}…"
        else
            _truncated="$1"
        fi
    }

    ## --- Rendering functions ---

    # Move cursor to the first row of the browser
    cursor_to_browser() {
        printf "${_rc}${_cud1}${_cud1}${_cud1}"
    }

    # Move cursor to a specific browser row (0-indexed)
    # Args: row_index
    cursor_to_browser_row() {
        cursor_to_browser
        local row=$1
        while [[ $row -gt 0 ]]; do printf "${_cud1}"; ((row--)); done
    }

    # Compute the file text for each visible row in the browser.
    # Populates the file_text_cache array (one entry per visible row).
    # Must be called when directory changes or hidden toggle changes.
    compute_file_text_cache() {
        file_text_cache=()

        # Determine how many file columns fit in the available terminal width
        local term_width=$(tput cols)
        local avail_width=$((term_width - DIR_COL_WIDTH))
        local num_file_cols=0
        local col_width=$MIN_FILE_COL_WIDTH
        local max_file_slots=0
        if [[ $avail_width -ge $MIN_FILE_COL_WIDTH ]]; then
            num_file_cols=$((avail_width / MIN_FILE_COL_WIDTH))
            col_width=$((avail_width / num_file_cols))
        fi
        max_file_slots=$((num_file_cols * num_visible_rows))

        local num_files=${#current_files[@]}

        # Build one text string per row, filling files column-major (down each column first)
        local row col file_index file_name file_padding_count row_text

        for ((row=0; row<num_visible_rows; row++)); do
            row_text=""
            if [[ $num_file_cols -gt 0 ]] && [[ $num_files -gt 0 ]]; then
                for ((col=0; col<num_file_cols; col++)); do
                    file_index=$((col * num_visible_rows + row))

                    # Show overflow indicator in the last slot if there are more files than slots
                    if [[ $col -eq $((num_file_cols - 1)) ]] \
                    && [[ $row -eq $((num_visible_rows - 1)) ]] \
                    && [[ $num_files -gt $max_file_slots ]]; then
                        row_text+="${_dim}(More files, hidden)${_sgr0}"

                    # Show file name if this slot has a corresponding file
                    elif [[ $file_index -lt $num_files ]]; then
                        if [[ $is_zsh = true ]]; then
                            truncate_name "${current_files[$((file_index+1))]}" $MAX_NAME_WIDTH
                        else
                            truncate_name "${current_files[$file_index]}" $MAX_NAME_WIDTH
                        fi
                        file_name=$_truncated

                        # Pad non-last columns to their computed width for alignment
                        if [[ $col -lt $((num_file_cols - 1)) ]]; then
                            file_padding_count=$((col_width - ${#file_name}))
                            local file_padding=''
                            [[ $file_padding_count -gt 0 ]] && printf -v file_padding "%${file_padding_count}s" ''
                            row_text+="${_dim}${file_name}${file_padding}${_sgr0}"
                        else
                            row_text+="${_dim}${file_name}${_sgr0}"
                        fi
                    fi
                done

            # Show placeholder text when directory has no files
            elif [[ $row -eq 0 ]] && [[ $num_files -eq 0 ]]; then
                row_text="${_dim}No files here${_sgr0}"
            fi
            file_text_cache+=("$row_text")
        done
    }

    # Renders a single directory entry in the browser at the current cursor position,
    # formatted as a fixed-width string of length DIR_COL_WIDTH.
    # Args: dir_name is_selected is_first is_last can_scroll_up can_scroll_down
    render_dir_row() {
        local dir_name=$1 is_selected=$2 is_first=$3 is_last=$4 can_scroll_up=$5 can_scroll_down=$6
        local prefix=" "
        [[ $is_first = true ]] && [[ $can_scroll_up = true ]] && prefix="↑"
        [[ $prefix = " " ]] && [[ $is_last = true ]] && [[ $can_scroll_down = true ]] && prefix="↓"

        truncate_name "$dir_name" $MAX_NAME_WIDTH; dir_name=$_truncated
        local padding_count=$((MAX_NAME_WIDTH - ${#dir_name}))
        local padding=''
        [[ $padding_count -gt 0 ]] && printf -v padding "%${padding_count}s" ''

        if [[ $is_selected = true ]]; then
            printf " %s ${_setab7}${_setaf0} %s ${_sgr0}%s " "$prefix" "$dir_name" "$padding"
        else
            printf " %s  %s%s  " "$prefix" "$dir_name" "$padding"
        fi
    }

    # Render the full browser: directory rows with file columns, plus file-only rows below.
    # Precondition: cursor is at the first browser row.
    # Args: selected_vindex first_visible_dir_index num_filtered_dirs visible_dirs...
    render_browser() {
        local selected_vindex=$1
        local first_visible_dir_index=$2
        local num_filtered_dirs=$3
        shift 3
        local visible_dirs=("$@")
        local num_visible=${#visible_dirs[@]}

        # Determine whether scroll indicators are needed
        local can_scroll_up=false can_scroll_down=false
        [[ $first_visible_dir_index -gt 0 ]] && can_scroll_up=true
        [[ $((first_visible_dir_index + num_visible)) -lt $num_filtered_dirs ]] && can_scroll_down=true

        # Render each directory row with its corresponding file text
        local i=0
        for dir in "${visible_dirs[@]}"; do
            local is_first=false is_last=false is_selected=false
            [[ $i -eq 0 ]] && is_first=true
            [[ $i -eq $((num_visible - 1)) ]] && is_last=true
            [[ $i -eq $selected_vindex ]] && is_selected=true

            # Get cached file text for this row
            local file_text="${file_text_cache[$((i+1))]}"
            [[ $is_bash = true ]] && file_text="${file_text_cache[$i]}"

            # Print directory entry followed by file text
            render_dir_row "$dir" "$is_selected" "$is_first" "$is_last" "$can_scroll_up" "$can_scroll_down"
            if [[ $i -eq $((num_visible_rows - 1)) ]]; then
                printf "%s${_el}" "$file_text"
            else
                printf "%s${_el}\n" "$file_text"
            fi
            ((i++))
        done

        # Fill remaining rows with file text only (when fewer dirs than visible rows)
        while [[ $i -lt $num_visible_rows ]]; do
            local file_text="${file_text_cache[$((i+1))]}"
            [[ $is_bash = true ]] && file_text="${file_text_cache[$i]}"
            if [[ $i -eq $((num_visible_rows - 1)) ]]; then
                printf "${_dir_pad}%s${_el}" "$file_text"
            else
                printf "${_dir_pad}%s${_el}\n" "$file_text"
            fi
            ((i++))
        done
    }

    # Re-render a single directory row in the browser (used for optimized up/down navigation).
    # Only redraws the directory column; file text is preserved since the column is fixed-width.
    # Args: row_index is_selected
    #       (also reads outer-scope: visible_dirs, first_visible_dir_index, num_filtered_dirs)
    render_browser_row() {
        local row_index=$1 is_selected=$2
        local num_visible=${#visible_dirs[@]}
        local dir_name="$(index_array $row_index "${visible_dirs[@]}")"
        local is_first=false is_last=false
        [[ $row_index -eq 0 ]] && is_first=true
        [[ $row_index -eq $((num_visible - 1)) ]] && is_last=true

        local can_scroll_up=false can_scroll_down=false
        [[ $first_visible_dir_index -gt 0 ]] && can_scroll_up=true
        [[ $((first_visible_dir_index + num_visible)) -lt $num_filtered_dirs ]] && can_scroll_down=true

        cursor_to_browser_row $row_index
        render_dir_row "$dir_name" "$is_selected" "$is_first" "$is_last" "$can_scroll_up" "$can_scroll_down"
        # Don't print file text or _el — the dir column is fixed-width so it overwrites in place,
        # and _el would erase the file text already displayed to the right
    }

    # Display the current search string with cursor
    render_search_string() {
        printf "${_rc}${_cud1}${_cud1}${_cuf4}${_setaf3}%s${_el}${_sgr0}_\n" "$search_str"
    }

    # Display the header showing current directory and keyboard controls
    render_heading() {
        printf "${_rc}"
        local pwd_str=$(pwd)
        local lim_width=$(($(tput cols) - 20 - 5))  # 20 for "Change directory to ", 5 for buffer
        [[ lim_width -gt MAX_DIR_WIDTH ]] && lim_width=$MAX_DIR_WIDTH
        [[ ${#pwd_str} -gt $lim_width ]] && pwd_str="...${pwd_str:$((${#pwd_str} - lim_width + 3))}"
        printf "${_smul}Change directory to ${_bold}%s${_sgr0}${_el}\n" "$pwd_str"
        printf "${_dim}↑↓:select ←:parent →:enter ⏎:confirm ESC:cancel TAB:hidden type:search${_sgr0}${_el}\n"
    }

    ## --- Set up ---

    # Initialize variables
    local search_str='' prev_dir='' initial_pwd=$PWD initial_oldpwd=$OLDPWD
    local show_hidden=false _truncated=''
    local current_files=()
    local file_text_cache=()
    local num_visible_rows=$(($(tput lines) - 3 - 1))  # 3 fixed lines (heading + instructions + search), 1 for buffer
    [[ $num_visible_rows -gt $MAX_VISIBLE_DIRS ]] && num_visible_rows=$MAX_VISIBLE_DIRS

    # Initialize interface
    printf "${_civis}"
    stty -echo
    printf "${_sc}"
    render_heading
    echo -e "$SEARCH_PREFIX"
    for ((i=0; i<num_visible_rows; i++)); do echo; done
    tput cuu $((num_visible_rows + 3))
    printf "${_sc}"

    # Cleanup functions
    cleanup_base() {
        printf "${_rc}${_ed}${_cnorm}"
        stty echo
        trap - INT
    }

    cleanup_confirm() {
        cleanup_base
        builtin cd $initial_pwd  # support expected `cd -` behavior after exiting
        builtin cd $OLDPWD
        printf "Working directory changed: ${_bold}%s${_el}${_sgr0}\n" "$(pwd)"
    }

    cleanup_cancel() {
        cleanup_base
        builtin cd $initial_oldpwd
        builtin cd $initial_pwd  # restore expected `cd -` behavior
        printf "Restored working directory: ${_bold}%s${_el}${_sgr0}\n" "$(pwd)"
        return
    }

    trap 'cleanup_cancel; return' INT

    ## --- Main loop ---
    # Each iteration of the outer loop represents one directory. On each iteration:
    #   1. Collect all subdirectories and files in the current directory.
    #   2. Pre-compute the file text cache (file names laid out into rows of text).
    #   3. Restore the selection to the previously-entered subdirectory if navigating back.
    #   4. Run the inner loop, which handles one keypress at a time:
    #      a. If the search string changed, re-filter directories and re-render the search line.
    #      b. If the browser needs re-rendering, update the scroll position and redraw — either
    #         the full browser (on scroll or first render) or just the two affected rows (on up/down).
    #      c. Read a keypress. Primary controls are arrow keys; see instructions line for full list.
    #   5. After the inner loop, cd to the selected directory (or parent, or toggle hidden files),
    #      then repeat the outer loop for the new directory.
    #   Pressing enter or ESC breaks out of the outer loop entirely.

    while true; do
        # Determine the subdirectories and files
        local filtered_dirs=() all_dirs=()
        current_files=()
        local ls_flags='-F'
        [[ $show_hidden = true ]] && ls_flags='-FA'
        local subdirs=$( (/bin/ls $ls_flags | grep /$ | sort -f) )
        if [[ -n $subdirs ]]; then
            [[ $is_bash = true ]] && IFS=$'\n' read -r -d '' -a all_dirs <<< "$subdirs"
            [[ $is_zsh = true ]] && all_dirs+=("${(f)subdirs}")
        fi

        # Gather files (non-directories), sorted case-sensitive
        local file_list=$( (/bin/ls $ls_flags | grep -v /$ | sort) )
        if [[ -n $file_list ]]; then
            [[ $is_bash = true ]] && IFS=$'\n' read -r -d '' -a current_files <<< "$file_list"
            [[ $is_zsh = true ]] && current_files+=("${(f)file_list}")
            # Strip classification suffixes (*, @, =, |, %) and carriage returns from file names
            local tmp_files=()
            for f in "${current_files[@]}"; do
                f="${f%\*}"; f="${f%@}"; f="${f%=}"; f="${f%|}"; f="${f%\%}"
                f="${f//$'\r'/}"
                tmp_files+=("$f")
            done
            current_files=("${tmp_files[@]}")
        fi

        # Pre-compute file text cache for this directory
        file_text_cache=()
        compute_file_text_cache

        # Select previous dir (if left arrow key was pressed)
        local selected_index=0
        local prev_dir_index=$(index_of "$prev_dir" "${all_dirs[@]}")
        [[ $prev_dir_index -ne -1 ]] && selected_index=$prev_dir_index;
        local key_pressed=''

        local first_visible_dir_index=$((selected_index - num_visible_rows + 1))
        [[ $first_visible_dir_index -lt 0 ]] && first_visible_dir_index=0
        local do_rerender_browser=true did_update_search=true
        local prev_selected_vindex=-1  # track previous selection for partial re-render

        render_heading

        # Loop while still in the same directory
        while true; do
            # Update filtered directories if search string changed
            if [[ $did_update_search = true ]]; then
                render_search_string "$search_str"

                # Filter directories by search string
                filtered_dirs=()
                if [[ -z $search_str ]]; then
                    filtered_dirs=("${all_dirs[@]}")
                else
                    for dir in "${all_dirs[@]}"; do
                        local dir_lowercase=$(to_lowercase "$dir")
                        local regex=$(to_lowercase "$search_str")
                        regex=$(escape_regex "$regex")
                        [[ "$dir_lowercase" =~ $regex ]] && filtered_dirs+=("$dir")
                    done
                fi

                # Handle special cases for empty results
                local show_message=false
                local message="" message2=""
                if [[ ${#filtered_dirs[@]} -eq 0 ]]; then
                    show_message=true
                    if [[ ${#all_dirs[@]} -eq 0 ]]; then
                        message="No subdirectories"
                        message2="(use ← to go back)"
                    else
                        message="No matches found"
                    fi
                fi

                local num_filtered_dirs=${#filtered_dirs[@]}
            else
                cursor_to_browser
            fi
            did_update_search=false

            # Rerender browser if needed
            if [[ $do_rerender_browser = true ]]; then
                # Determine scroll position
                local old_first_visible_dir_index=$first_visible_dir_index
                if [[ $selected_index -lt $first_visible_dir_index ]]; then
                    first_visible_dir_index=$selected_index
                elif [[ $selected_index -ge $((first_visible_dir_index + num_visible_rows)) ]]; then
                    first_visible_dir_index=$((selected_index - num_visible_rows + 1))
                fi

                local selected_vindex=$((selected_index - first_visible_dir_index))

                # Display message when there are no directories to show
                if [[ $show_message = true ]]; then
                    cursor_to_browser
                    # First row: message + file text
                    local first_row_file_text="${file_text_cache[1]}"
                    [[ $is_bash = true ]] && first_row_file_text="${file_text_cache[0]}"
                    printf "    ${_dim}%s${_sgr0}" "$message"
                    local message_padding=$((MAX_NAME_WIDTH - ${#message}))
                    [[ $message_padding -gt 0 ]] && printf "%${message_padding}s" ''
                    printf "  %s${_el}\n" "$first_row_file_text"
                    # Second row: secondary message (if any) + file text
                    local row_index=1
                    if [[ -n $message2 ]]; then
                        local second_row_file_text="${file_text_cache[2]}"
                        [[ $is_bash = true ]] && second_row_file_text="${file_text_cache[1]}"
                        printf "    ${_dim}%s${_sgr0}" "$message2"
                        local message2_padding=$((MAX_NAME_WIDTH - ${#message2}))
                        [[ $message2_padding -gt 0 ]] && printf "%${message2_padding}s" ''
                        printf "  %s${_el}\n" "$second_row_file_text"
                        row_index=2
                    fi
                    # Remaining rows: file text only
                    while [[ $row_index -lt $num_visible_rows ]]; do
                        local row_file_text="${file_text_cache[$((row_index+1))]}"
                        [[ $is_bash = true ]] && row_file_text="${file_text_cache[$row_index]}"
                        if [[ $row_index -eq $((num_visible_rows - 1)) ]]; then
                            printf "${_dir_pad}%s${_el}" "$row_file_text"
                        else
                            printf "${_dir_pad}%s${_el}\n" "$row_file_text"
                        fi
                        ((row_index++))
                    done
                    printf "${_ed}"
                    prev_selected_vindex=-1
                else
                    visible_dirs=( "${filtered_dirs[@]:$first_visible_dir_index:$num_visible_rows}" )

                    # Optimization: if scroll position hasn't changed, only re-render the two affected rows
                    if [[ $old_first_visible_dir_index -eq $first_visible_dir_index ]] \
                    && [[ $prev_selected_vindex -ge 0 ]] \
                    && [[ $prev_selected_vindex -ne $selected_vindex ]]; then
                        # Deselect previously highlighted row
                        render_browser_row $prev_selected_vindex false
                        # Highlight newly selected row
                        render_browser_row $selected_vindex true
                    else
                        # Full browser re-render (scroll position changed or first render)
                        cursor_to_browser
                        render_browser $selected_vindex $first_visible_dir_index $num_filtered_dirs "${visible_dirs[@]}"
                        printf "${_ed}"
                    fi
                    prev_selected_vindex=$selected_vindex
                fi
            fi
            do_rerender_browser=true

            # Process user input
            [[ $is_bash = true ]] && key_pressed=$(bash_key_input) || key_pressed=$(zsh_key_input)
            case $key_pressed in
                left)   [[ $PWD != "$HOME" ]] && break;;
                right)  [[ $num_filtered_dirs -gt 0 ]] && break;;
                escape) cleanup_cancel; return;;
                enter)  break;;
                tab)    break;;
                '\')    do_rerender_browser=false;;
                up)
                    if [[ $num_filtered_dirs -gt 0 ]]; then
                        ((selected_index--))
                        [[ $selected_index -lt 0 ]] && selected_index=$((num_filtered_dirs - 1))
                    fi;;
                down)
                    if [[ $num_filtered_dirs -gt 0 ]]; then
                        ((selected_index++))
                        [[ $selected_index -ge $num_filtered_dirs ]] && selected_index=0
                    fi;;
                backspace)
                    search_str="${search_str%?}"
                    selected_index=0
                    did_update_search=true;;
                *)
                    search_str+=$key_pressed
                    selected_index=0
                    did_update_search=true;;
            esac
        done

        # cd accordingly
        case $key_pressed in
            right)
                [[ $num_filtered_dirs -gt 0 ]] && builtin cd "$(index_array "$selected_index" "${filtered_dirs[@]}")"
                prev_dir='';;
            left)  prev_dir=$(printf '%s/' "${PWD##*/}"); builtin cd ..;;
            tab)   [[ $show_hidden = true ]] && show_hidden=false || show_hidden=true; prev_dir='';;
            enter) break;;
        esac

        search_str=''
    done

    cleanup_confirm
}
