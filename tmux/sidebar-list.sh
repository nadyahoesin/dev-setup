#!/usr/bin/env bash
# Emits the sidebar rows: "<target>\t<display>" per line (ANSI allowed).
#   target = "@<window_id>"      a tab in the main session
#          = ""                  a group header (not clickable)
# Tabs are grouped by project folder — the first path component under
# ~/Workspace, "~" for the home dir, else the folder's basename. Only the
# main session's tabs are rows; orchestrator worker sessions (pi-wt-* /
# codex-wt-*) are shown as indented children of the tab that started them
# (parent_window in ~/.orchestrate-subagents/<session>.env).
#   target = "s:<session>"     a worker session
# Shared by sidebar.sh (initial list + reload), sidebar-click.sh (row → target)
# and sidebar-pos.sh (cursor row), so all three always agree.
# Runs on macOS' stock bash 3.2.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export LC_ALL=en_US.UTF-8   # printf pads by characters, not bytes
unset TMUX
exec 2>/dev/null   # never let a stray error reach tmux/fzf output
# the sidebar pane's real width (it can be dragged narrower than the default 51)
read -r PW PH < <(tmux -L ui display -p -t ui:.0 '#{pane_width} #{pane_height}' 2>/dev/null)
W=${SIDEBAR_WIDTH:-$PW}
[[ $W =~ ^[0-9]+$ ]] && (( W >= 24 )) || W=51
[[ $PH =~ ^[0-9]+$ ]] && (( PH >= 5 )) || PH=40
echo "$W $PH" > "${TMPDIR:-/tmp}/tmux-sidebar-$UID.size"
PAD=$((W - 7))          # fzf left margin 2 + "  " indent + marker + " " + name, one col spare
DIM=$'\e[2m'; RST=$'\e[0m'
CLOSE=$'\e[38;2;221;221;221m'   # the tab's ✕, same light grey as the file viewer's
fit() {  # fit <text> <max columns> → $REPLY_F, cut with … only when it doesn't fit
  local t=$1 m=$2
  (( m < 1 )) && m=1
  if (( ${#t} > m )); then REPLY_F="${t:0:$((m - 1))}…"; else REPLY_F=$t; fi
}
# columns a row's text gets inside its card (width - margins/scrollbar - "│ " … "│")
room() { REPLY_ROOM=$(( W - 4 - 3 )); }

# This runs up to ten times a second while agents animate their titles, so no
# subprocesses per row: pure bash string ops only, one tmux call, one sort.

group_of() {  # path → group name, in $REPLY
  local p=$1 ws="$HOME/Workspace/"
  if [[ $p == "$ws"* ]]; then p=${p#"$ws"}; REPLY=${p%%/*}
  elif [[ $p == "$HOME" ]]; then REPLY="~"
  else REPLY=${p##*/}; fi
}

is_braille() {  # Claude Code's title spinner: U+2800–U+28FF = bytes E2 A0..A3 xx
  local LC_ALL=C
  [[ $1 == $'\xe2'[$'\xa0'-$'\xa3']* ]]
}

# worker session → parent tab, and which session the client is looking at now
STATE="$HOME/.orchestrate-subagents"
declare -a W_SESS=() W_PARENT=()
while IFS=$'\t' read -r sess; do
  f="$STATE/$sess.env"; parent=""
  if [[ -f $f ]]; then
    while IFS='=' read -r k v; do [[ $k == parent_window ]] && parent=$v; done < "$f"
  fi
  W_SESS+=("$sess"); W_PARENT+=("$parent")
done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -E '^(pi|codex)-wt-')
CUR=$(tmux list-clients -F '#{client_session}' 2>/dev/null | head -1)

# activity per tab: waiting (agent needs you) > working (agent mid-turn) >
# running (a non-shell command in a plain terminal pane)
GRN=$'\e[32m' YEL=$'\e[33m' RED=$'\e[31m'
ACT=" "
# which agent owns a tab: claude / pi (set by the Claude hook and pi's
# tmux-agent-state extension). Only the name's colour differs.
KIND=" "
CC=$'\e[1;97m'                 # Claude Code: bold white
PI=$'\e[1;38;2;226;210;255m'   # pi: bold pale violet
NRST=$'\e[22;39m'
# Pane shells whose Claude Code still has a shell running after its turn ended —
# typically a run_in_background `agent-session.sh wait` on subagents. Claude runs
# every Bash call as `zsh -c source …/.claude/shell-snapshots/…` under its own pid.
# A full process scan is half the cost of drawing the sidebar, and this is the
# one thing in it that cannot change between two consecutive frames in a way
# anyone would notice — so it is cached for a second. Redrawing on a tab switch
# is what has to feel instant.
NOW=$(date +%s)   # bash 3.2 has no EPOCHSECONDS
BG_CACHE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.bgshell"
BGSHELL=""
if [[ -f $BG_CACHE ]]; then
  bg_age=$(( NOW - $(stat -f %m "$BG_CACHE" 2>/dev/null || echo 0) ))
  (( bg_age >= 0 && bg_age <= 1 )) && read -r BGSHELL < "$BG_CACHE"
fi
if [[ -z $BGSHELL ]]; then
  BGSHELL=" $(ps -Ao pid=,ppid=,command= 2>/dev/null | awk '
    $3 ~ /\/claude$/ || $3 ~ /\/\.local\/bin\/claude/ { parent[$1] = $2 }
    /\.claude\/shell-snapshots\// { busy[$2] = 1 }
    END { for (c in busy) if (c in parent) printf "%s ", parent[c] }') "
  printf '%s\n' "$BGSHELL" > "$BG_CACHE.tmp" && mv -f "$BG_CACHE.tmp" "$BG_CACHE"
fi
while IFS='|' read -r wid st cmd ppid kind; do   # '|' not tab: tabs are IFS whitespace and an empty @agent_state would collapse
  [[ -n $kind ]] && case "$KIND" in *" $wid="*) ;; *) KIND="$KIND$wid=$kind " ;; esac
  a=""
  [[ -z $st && $BGSHELL == *" $ppid "* ]] && st=working
  case "$st" in
    waiting) a=3 ;;
    working) a=2 ;;
    idle) a=0 ;;   # said explicitly by the agent; its pane command (`node`) would otherwise read as "running"
    *) case "$cmd" in
         zsh|bash|sh|fish|-zsh|login|tmux|uv|glow|less|python3|[0-9]*.[0-9]*.[0-9]*) ;;   # shells, idle agents (version-named), md sidebar
         *) a=1 ;;
       esac ;;
  esac
  [[ -z $a ]] && continue
  case "$ACT" in *" $wid="*) prev=${ACT#*" $wid="}; prev=${prev%% *}; (( a <= prev )) && continue; ACT=${ACT/" $wid=$prev "/ } ;; esac
  ACT="$ACT$wid=$a "
done < <(tmux list-panes -s -t main -F '#{window_id}|#{@agent_state}|#{pane_current_command}|#{pane_pid}|#{@agent_kind}' 2>/dev/null)

activity() {  # indicator for tab $1 in $REPLY_A (visible width 2)
  local v=""
  case "$ACT" in *" $1="*) v=${ACT#*" $1="}; v=${v%% *} ;; esac
  case "$v" in
    3) REPLY_A="${RED}!${RST} " ;;
    2) REPLY_A="${YEL}●${RST} " ;;
    1) REPLY_A="${GRN}●${RST} " ;;
    0) REPLY_A="${DIM}•${RST} " ;;   # an agent sitting at its prompt: small and grey
    *) REPLY_A="  " ;;
  esac
}

busy_children() {  # busy worker count under tab $1 in $REPLY_B
  local i pid; REPLY_B=0
  for i in "${!W_SESS[@]}"; do
    [[ ${W_PARENT[$i]} == "$1" ]] || continue
    pid=""; [[ -f $STATE/pi/${W_SESS[$i]}/busy ]] && read -r pid < "$STATE/pi/${W_SESS[$i]}/busy"
    [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && REPLY_B=$((REPLY_B + 1))
  done
}
# Tabs whose worker list is collapsed (toggled by clicking ▾/▸).
# A tab lists the workers still running, the way Claude Code shows subagents:
# one that finished folds away by itself and comes back the moment it is given
# another turn, and clicking ▾ hides the running ones too. The session itself is
# untouched — tearing it down deletes a worktree, so that stays
# `agent-session.sh stop`.
COLLAPSED_FILE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.collapsed"
COLLAPSED=" "; [[ -f $COLLAPSED_FILE ]] && COLLAPSED=" $(<"$COLLAPSED_FILE") "
COLLAPSED=${COLLAPSED//$'\n'/ }

child_count() {  # number of workers under tab $1, in $REPLY_N; 1 if one is being viewed
  local i; REPLY_N=0; VIEWING=0
  for i in "${!W_SESS[@]}"; do
    [[ ${W_PARENT[$i]} == "$1" ]] || continue
    REPLY_N=$((REPLY_N + 1)); [[ ${W_SESS[$i]} == "$CUR" || $CUR == "pisub-${W_SESS[$i]}--"* ]] && VIEWING=1
  done
}

# worker sessions whose nested `pi -p` runs are unfolded (toggled by clicking ▸/▾);
# folded by default, so a worker only shows a dim (+n)
EXPANDED_FILE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.expanded"
EXPANDED=" "; [[ -f $EXPANDED_FILE ]] && EXPANDED=" $(<"$EXPANDED_FILE") "
EXPANDED=${EXPANDED//$'\n'/ }

children() {  # print child rows for tab $1 (group $2, index $3); $4=1 hides them all
  local want=$1 i sess m busy label pid sub d nsub bsub fold tail view open collapsed=${4:-0}
  (( collapsed )) && return 0
  for i in "${!W_SESS[@]}"; do
    [[ ${W_PARENT[$i]} == "$want" ]] || continue
    sess=${W_SESS[$i]}
    m=" "; [[ $sess == "$CUR" ]] && m="▶"
    busy=""
    pid=""; [[ -f $STATE/pi/$sess/busy ]] && read -r pid < "$STATE/pi/$sess/busy"
    [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && busy="${YEL}●${RST}"
    # a worker that finished is folded away; the one you are looking at stays
    [[ -z $busy && $sess != "$CUR" && $CUR != "pisub-$sess--"* ]] && continue
    # nested `pi -p` runs this worker started (recorded by the skill's shim/pi)
    sub=$STATE/pi/$sess/sub nsub=0 bsub=0 fold="" tail="" open=0
    for d in "$sub"/*/; do
      [[ -f ${d}label ]] || continue
      nsub=$((nsub + 1)); pid=""
      [[ -f ${d}pid ]] && read -r pid < "${d}pid"
      [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && bsub=$((bsub + 1))
    done
    if (( nsub > 0 )); then
      view="pisub-$sess--"
      if [[ $EXPANDED == *" $sess "* || $CUR == "$view"* ]]; then fold="▾ " open=1; else fold="▸ "; fi
      tail=" ${DIM}(+$nsub)${RST}"
      (( bsub > 0 )) && tail="$tail ${YEL}⋯$bsub${RST}"
      (( open == 0 )) && [[ $CUR == "$view"* ]] && m="▶"
    fi
    room; vis "$tail"
    fit "${sess#*-wt-}" $(( REPLY_ROOM - 5 - ${#fold} - 2 - ${#REPLY_V} )); label=$REPLY_F
    cm=""; [[ $m == "▶" ]] && cm=$'\t▶'
    printf '%s\t%04d\t%s\t   %s└%s %s%s %s%s%s\n' "$2" "$3" "s:$sess" "$DIM" "$RST" "$fold" "$label" "$busy" "$tail" "$cm"
    (( open )) || continue
    for d in "$sub"/*/; do
      [[ -f ${d}label ]] || continue
      n=${d%/}; n=${n##*/}
      m=" "; [[ $CUR == "pisub-$sess--$n" ]] && m="▶"
      busy=""; pid=""
      [[ -f ${d}pid ]] && read -r pid < "${d}pid"
      if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then busy="${YEL}●${RST}"
      elif [[ -f ${d}exit && $(<"${d}exit") != 0 ]]; then busy="${RED}✗${RST}"; fi
      read -r label < "${d}label"; room; fit "$label" $(( REPLY_ROOM - 10 )); label=$REPLY_F
      cm=""; [[ $m == "▶" ]] && cm=$'\t▶'
      printf '%s\t%04d\t%s\t      %s└ %s%s %s%s\n' "$2" "$3" "v:pisub-$sess--$n" "$DIM" "$label" "$RST" "$busy" "$cm"
    done
  done
}

# ── layout ────────────────────────────────────────────────────────────────
# SIDEBAR_STYLE (or the style file, set by sidebar-style.sh): how tabs are separated
#   spaced    blank line between tabs
#   dividers  faint rule between tabs
#   cards     each tab (with its workers) in its own rounded box
#   sections  one box per project folder, dotted rules between its tabs
STYLE_FILE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.style"
STYLE=${SIDEBAR_STYLE:-}
[[ -z $STYLE && -f $STYLE_FILE ]] && read -r STYLE < "$STYLE_FILE"
STYLE=${STYLE:-cards}
CW=$((W - 4))                  # usable columns: fzf margin 1 + gutter 1, a gap, and the scrollbar column
BOR=$'\e[38;2;42;74;80m'       # faint teal, same as the md viewer's rules
shopt -s extglob
rep() { local out="" i; for ((i = 0; i < $2; i++)); do out+=$1; done; REPLY_R=$out; }
vis() { REPLY_V=${1//$'\e['*([0-9;])m/}; }
row() {  # row <target> <display[\x01right-aligned part][\t▶]>
  local t=$1 d=$2 cm="" hl="" n dr="" wl wr
  [[ $d == *$'\t▶' ]] && { cm=$'\t▶'; d=${d%$'\t▶'}; }
  # anything after \x01 is pushed to the right edge of the row (the ✕)
  [[ $d == *$'\x01'* ]] && { dr=${d#*$'\x01'}; d=${d%%$'\x01'*}; }
  # The active tab is highlighted in the row itself, not by fzf's cursor: fzf's
  # cursor can't leave the screen, so it stuck to the top when you scrolled the
  # active tab away. A scrolled-off row simply takes its highlight with it.
  if [[ -n $cm ]]; then
    hl=$'\e[48;2;7;53;59m'
    d="${d//$'\e[0m'/$'\e[0m'$hl}"
    d="${d//$'\e[39m'/$'\e[39m'$hl}"
    d="${d//$'\e[22;39m'/$'\e[22;39m'$hl}"
    dr="${dr//$'\e[0m'/$'\e[0m'$hl}"
  fi
  case "$STYLE" in
    cards|sections)
      vis "$d"; wl=${#REPLY_V}; vis "$dr"; wr=${#REPLY_V}
      n=$(( CW - 3 - wl - wr )); (( n < 0 )) && n=0
      if [[ -n $cm ]]; then
        printf '%s\t%s┃%s%s %s%*s%s%s%s│%s%s\n' "$t" $'\e[38;2;64;212;231m' "$RST" "$hl" "$d" "$n" '' "$dr" "$RST" "$BOR" "$RST" "$cm"
      else
        printf '%s\t%s│%s %s%*s%s%s│%s%s\n' "$t" "$BOR" "$RST" "$d" "$n" '' "$dr" "$BOR" "$RST" "$cm"
      fi ;;
    *) vis "$d"; wl=${#REPLY_V}; vis "$dr"; wr=${#REPLY_V}
       n=$(( CW - wl - wr )); (( n < 0 )) && n=0
       [[ -n $cm ]] && printf '%s\t%s%s%*s%s%s%s\n' "$t" "$hl" "$d" "$n" '' "$dr" "$RST" "$cm" || printf '%s\t%s%*s%s\n' "$t" "$d" "$n" '' "$dr" ;;
  esac
}
rule() {  # rule <left> <fill> <right> [title]
  local title=${4:-} fillw
  if [[ -n $title ]]; then
    fillw=$(( CW - 2 - ${#title} - 3 )); rep "$2" "$fillw"
    printf '\t%s%s%s %s%s%s %s%s%s\n' "$BOR" "$1" "$2" "$RST$DIM" "$title" "$RST" "$BOR" "$REPLY_R$3" "$RST"
  else
    rep "$2" $(( CW - 2 )); printf '\t%s%s%s%s%s\n' "$BOR" "$1" "$REPLY_R" "$3" "$RST"
  fi
}
render() {
  local g idx target display prev="" inblock=0 ingroup=0
  close_block() { (( inblock )) || return 0; [[ $STYLE == cards ]] && rule "╰" "─" "╯"; inblock=0; }
  close_group() {
    close_block
    (( ingroup )) || return 0
    [[ $STYLE == sections ]] && rule "╰" "─" "╯"
    ingroup=0
  }
  while IFS=$'\t' read -r g idx target display; do
    if [[ $g != "$prev" ]]; then
      local had=$ingroup; close_group
      (( had )) && printf '\t \n'
      case "$STYLE" in
        sections) rule "╭" "─" "╮" "$g" ;;
        dividers) printf '\t%s%s%s\n' "$DIM" "$g" "$RST"; rule "" "─" "" ;;
        cards)    printf '\t%s%s%s\n' "$DIM" "$g" "$RST" ;;
        *)        printf '\t%s%s%s\n\t \n' "$DIM" "$g" "$RST" ;;
      esac
      prev=$g ingroup=1 first=1
    fi
    if [[ $target == @* || $first == 1 ]]; then   # a tab starts a new block
      if (( ! first )); then
        close_block
        case "$STYLE" in
          spaced)   printf '\t \n' ;;
          dividers) rule "" "─" "" ;;
          sections) rule "│" "┄" "│" ;;
        esac
      fi
      [[ $STYLE == cards ]] && rule "╭" "─" "╮"
      inblock=1 first=0
    fi
    row "$target" "$display"
  done
  close_group
  [[ $STYLE == dividers ]] && rule "" "─" ""
  return 0
}

# group \t window-index \t target \t display  → stable sort by group keeps tab order
prev=""
while IFS=$'\t' read -r id idx active act path name; do
  m=" "; if [[ $active == 1 && ( -z $CUR || $CUR == main ) ]]; then m="▶"; elif [[ $act == 1 ]]; then m="•"; fi
  # show one steady glyph instead of the spinner so the sidebar isn't redrawn per frame
  if is_braille "$name"; then name="⋯${name:1}"; fi
  group_of "$path"
  child_count "$id"
  busy_children "$id"
  fold=" " collapsed=0
  if (( REPLY_N > 0 )); then
    [[ $COLLAPSED == *" $id "* ]] && collapsed=1
    # a fold glyph only where there is something to fold: workers still running
    # (or the one being viewed). Once they are all finished the tab shows
    # nothing at all — no glyph, no count — until one gets another turn.
    if (( REPLY_B > 0 || VIEWING )); then (( collapsed )) && fold="▸" || fold="▾"; fi
  fi
  activity "$id"
  # the ⋯ spinner glyph is now shown as the activity dot instead
  name=${name#⋯ }; name=${name#✳ }
  tail=""; tw=0
  if (( REPLY_N > 0 )); then
    # nothing marks a finished worker: a tab with none running reads as a plain
    # tab again, and its workers reappear by themselves if one is given a turn
    if (( REPLY_B > 0 )); then tail="$tail ${YEL}⋯${REPLY_B}${RST}"; tw=$((tw + 2 + ${#REPLY_B})); fi
  fi
  room; fit "$name" $(( REPLY_ROOM - 4 - tw - 3 )); name=$REPLY_F   # -3: the ✕ column and a gap before it
  nc=$CC; case "$KIND" in *" $id=pi "*) nc=$PI ;; esac
  # no activity dot but unseen output: a dim dot in the same column
  [[ $REPLY_A == "  " && $act == 1 ]] && REPLY_A="${DIM}•${RST} "
  cm=""; [[ $m == "▶" ]] && cm=$'\t▶'
  # tab names stand out from the terminal text: bold, bright white (terminals have one font size)
  # ✕ at the right edge closes the tab, the same as ⌘W
  printf '%s\t%04d\t%s\t%s %s%s%s%s%s%s%s%s\n' "$REPLY" "$idx" "$id" "$fold" "$REPLY_A" "$nc" "$name" "$NRST" "$tail" $'\x01'"${CLOSE}✕${RST} " "$cm"
  children "$id" "$REPLY" "$idx" "$collapsed"
done < <(tmux list-windows -t main -F $'#{window_id}\t#{window_index}\t#{window_active}\t#{window_activity_flag}\t#{pane_current_path}\t#{window_name}' 2>/dev/null) |
{ sort -t$'\t' -s -k1,1 -k2,2; children "" workers 9999; } |
render
exit 0
