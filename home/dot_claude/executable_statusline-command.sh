#!/bin/bash
# Claude Code status line
# Layout: model · context · 5h/7d usage | repo · branch (+added,-removed)

input=$(cat)

# --- Colors ---
RESET='\033[0m'
DIM='\033[2m'
C_MODEL='\033[1;96m'                    # bold bright cyan
C_CTX='\033[96m'                        # bright cyan, NOT bold (model color w/o bold)
C_REPO='\033[1;38;2;89;170;228m'        # #59aae4
C_BRANCH='\033[1;38;2;239;141;52m'      # #EF8D34
C_BRANCH_DIM='\033[22;38;2;239;141;52m' # #EF8D34, bold OFF (22), not dim (line counts)

SEP_DOT="${DIM} \xc2\xb7 ${RESET}"      # dimmed middle dot
SEP_BAR="${DIM} | ${RESET}"            # dimmed vertical bar

# Color for a usage-limit percentage: green <50, yellow <70, orange <85, red >=85
limit_color() {
  local p=$1
  if   [ "$p" -lt 50 ]; then printf '\033[92m'
  elif [ "$p" -lt 70 ]; then printf '\033[93m'
  elif [ "$p" -lt 85 ]; then printf '\033[38;2;255;140;0m'
  else printf '\033[91m'
  fi
}

# --- Nerd Font icons (hex-escaped UTF-8) ---
ICON_MEM=$'\xee\x99\x8e'       # nf-seti-text U+E64E
ICON_REPO=$'\xef\x81\xbb'      # nf-fa-folder U+F07B
ICON_BRANCH=$'\xee\x9c\xa5'    # nf-dev-git_branch U+E725

# --- Model (strip trailing parenthetical, e.g. "Opus 4.8 (1M context)") ---
model=$(echo "$input" | jq -r '.model.display_name // "?"')
model=$(echo "$model" | sed -E 's/[[:space:]]*\([^)]*\)[[:space:]]*$//')

# --- Context window usage ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  bar_width=10
  filled=$(( used_int * bar_width / 100 ))
  [ "$filled" -gt "$bar_width" ] && filled=$bar_width
  empty=$(( bar_width - filled ))
  bar=""
  i=0; while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i+1)); done
  i=0; while [ "$i" -lt "$empty" ];  do bar="${bar}░"; i=$((i+1)); done
  ctx_str=$(printf "${C_CTX}${ICON_MEM} [%s] %s%%${RESET}" "$bar" "$used_int")
else
  ctx_str=$(printf "${C_CTX}${ICON_MEM} [░░░░░░░░░░]${RESET}")
fi

# --- Rate limits (5h / 7d), each colored by its own threshold ---
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
limit_str=""
if [ -n "$five" ] || [ -n "$week" ]; then
  if [ -n "$five" ]; then
    fi_int=$(printf '%.0f' "$five")
    limit_str="${limit_str}$(limit_color "$fi_int")5h:${fi_int}%${RESET}"
  fi
  if [ -n "$five" ] && [ -n "$week" ]; then
    limit_str="${limit_str} "
  fi
  if [ -n "$week" ]; then
    wk_int=$(printf '%.0f' "$week")
    limit_str="${limit_str}$(limit_color "$wk_int")7d:${wk_int}%${RESET}"
  fi
fi

# --- Repo / branch (only when cwd is inside a git repo) ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
is_git_repo=false
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  is_git_repo=true
fi

dir_str=""
branch_str=""
if [ "$is_git_repo" = true ]; then
  # repo name = basename of the git top-level dir
  toplevel=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
  repo=$(basename "${toplevel:-$cwd}")
  dir_str=$(printf "${C_REPO}${ICON_REPO} %s${RESET}" "$repo")

  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  if [ -n "$branch" ]; then
    # Lines added/removed: prefer Claude session totals, else uncommitted git diff
    added=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
    removed=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')
    if [ -z "$added" ] && [ -z "$removed" ]; then
      diff_out=$(git -C "$cwd" --no-optional-locks diff HEAD --numstat 2>/dev/null)
      added=$(echo "$diff_out"  | awk '$1 ~ /^[0-9]+$/ {s+=$1} END{print s+0}')
      removed=$(echo "$diff_out" | awk '$2 ~ /^[0-9]+$/ {s+=$2} END{print s+0}')
    fi
    added=${added:-0}; removed=${removed:-0}
    branch_str=$(printf "${C_BRANCH}${ICON_BRANCH} %s ${C_BRANCH_DIM}(+%s,-%s)${RESET}" "$branch" "$added" "$removed")
  fi
fi

# --- Terminal width (robust; Claude runs the hook with stdin/stdout piped) ---
# stderr stays attached to the tty, so stty on fd 2 gives the true width.
# Fall back through COLUMNS, tput via /dev/tty, then a conservative default.
# Conservative because over-estimating width over-pads and gets Claude-truncated.
cols=""
if sz=$(stty size <&2 2>/dev/null); then cols=${sz##* }; fi
case "$cols" in ''|*[!0-9]*) cols="" ;; esac
if [ -z "$cols" ]; then
  case "$COLUMNS" in ''|*[!0-9]*) : ;; *) [ "$COLUMNS" -gt 0 ] && cols=$COLUMNS ;; esac
fi
if [ -z "$cols" ]; then
  cols=$(tput cols </dev/tty 2>/dev/null)
  case "$cols" in ''|*[!0-9]*) cols="" ;; esac
fi
[ -z "$cols" ] && cols=80
# Claude renders the status line in a slightly narrower area than the full tty
# (stty reports ~4 cols more than Claude's usable width) and truncates by char
# count, treating each Nerd Font glyph as 1 col. Reserve a margin so the worst
# case (fewest icons = longest char count) still fits and never gets truncated.
usable=$(( cols - 4 ))
[ "$usable" -lt 1 ] && usable=1

# Visible width of a string: strip ANSI, count characters.
strip='s/\x1b\[[0-9;]*m//g'
vwidth() { local s; s=$(printf '%b' "$1" | sed -E "$strip"); printf '%s' "${#s}"; }

# --- Assemble ---
# left:  model · context | repo · branch (+A,-R)
# right: 5h/7d usage limits, pushed to the far right edge.
# Widths are pure character counts (matching how Claude measures the line for
# truncation, and how the Nerd Font glyphs render: 1 col each). This keeps the
# right segment anchored at the same column regardless of how many icons the
# left carries, so its position doesn't shift between git and non-git dirs.
# Drop trailing segments if the right segment would otherwise not fit, so the
# usage text is never truncated. Model always kept.
segs=(
  "${C_MODEL}${model}${RESET}"
  "${SEP_DOT}${ctx_str}"
)
[ -n "$dir_str" ]    && segs+=( "${SEP_BAR}${dir_str}" )
[ -n "$branch_str" ] && segs+=( "${SEP_DOT}${branch_str}" )

rvis=0
right=""
if [ -n "$limit_str" ]; then
  right=$(printf "%b" "$limit_str")
  rvis=$(vwidth "$limit_str")
fi
avail_left=$(( usable - rvis - 1 ))   # room for left, leaving a >=1 gap before right

left=""; lvis=0
for txt in "${segs[@]}"; do
  vis=$(vwidth "$txt")
  if [ -z "$left" ]; then
    left="$txt"; lvis=$vis
  elif [ -n "$right" ] && [ $(( lvis + vis )) -gt "$avail_left" ]; then
    break
  else
    left="${left}${txt}"; lvis=$(( lvis + vis ))
  fi
done

line=$(printf "%b" "$left")
if [ -n "$right" ]; then
  pad=$(( usable - lvis - rvis ))
  [ "$pad" -lt 1 ] && pad=1
  spaces=$(printf '%*s' "$pad" '')
  printf '%s%s%s' "$line" "$spaces" "$right"
else
  printf '%s' "$line"
fi
