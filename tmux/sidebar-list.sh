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
W=${SIDEBAR_WIDTH:-51}
PAD=$((W - 7))          # fzf left margin 2 + "  " indent + marker + " " + name, one col spare
DIM=$'\e[2m'; RST=$'\e[0m'

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
# Pane shells whose Claude Code still has a shell running after its turn ended —
# typically a run_in_background `agent-session.sh wait` on subagents. Claude runs
# every Bash call as `zsh -c source …/.claude/shell-snapshots/…` under its own pid.
BGSHELL=" $(ps -Ao pid=,ppid=,command= 2>/dev/null | awk '
  $3 ~ /\/claude$/ || $3 ~ /\/\.local\/bin\/claude/ { parent[$1] = $2 }
  /\.claude\/shell-snapshots\// { busy[$2] = 1 }
  END { for (c in busy) if (c in parent) printf "%s ", parent[c] }') "
while IFS='|' read -r wid st cmd ppid; do   # '|' not tab: tabs are IFS whitespace and an empty @agent_state would collapse
  a=""
  [[ -z $st && $BGSHELL == *" $ppid "* ]] && st=working
  case "$st" in
    waiting) a=3 ;;
    working) a=2 ;;
    *) case "$cmd" in
         zsh|bash|sh|fish|-zsh|login|tmux|uv|glow|less|python3|[0-9]*.[0-9]*.[0-9]*) ;;   # shells, idle agents (version-named), md sidebar
         *) a=1 ;;
       esac ;;
  esac
  [[ -z $a ]] && continue
  case "$ACT" in *" $wid="*) prev=${ACT#*" $wid="}; prev=${prev%% *}; (( a <= prev )) && continue; ACT=${ACT/" $wid=$prev "/ } ;; esac
  ACT="$ACT$wid=$a "
done < <(tmux list-panes -s -t main -F '#{window_id}|#{@agent_state}|#{pane_current_command}|#{pane_pid}' 2>/dev/null)

activity() {  # indicator for tab $1 in $REPLY_A (visible width 2)
  local v=""
  case "$ACT" in *" $1="*) v=${ACT#*" $1="}; v=${v%% *} ;; esac
  case "$v" in
    3) REPLY_A="${RED}!${RST} " ;;
    2) REPLY_A="${YEL}●${RST} " ;;
    1) REPLY_A="${GRN}●${RST} " ;;
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
# tabs whose worker children are folded away (toggled by clicking ▾/▸)
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

children() {  # print child rows for tab $1 (group $2, index $3); orphans go under "workers"
  local want=$1 i sess m busy label pid sub d nsub bsub fold tail view open
  for i in "${!W_SESS[@]}"; do
    [[ ${W_PARENT[$i]} == "$want" ]] || continue
    sess=${W_SESS[$i]}
    m=" "; [[ $sess == "$CUR" ]] && m="▶"
    busy=""
    pid=""; [[ -f $STATE/pi/$sess/busy ]] && read -r pid < "$STATE/pi/$sess/busy"
    [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && busy="${YEL}●${RST}"
    # nested `pi -p` runs this worker started (recorded by the skill's shim/pi)
    sub=$STATE/pi/$sess/sub nsub=0 bsub=0 fold="  " tail="" open=0
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
    label=${sess#*-wt-}; label=${label:0:$((PAD - 13 - ${#nsub} - 3))}
    printf '%s\t%04d\t%s\t  %s     %s└%s %s%s %s%s\n' "$2" "$3" "s:$sess" "$m" "$DIM" "$RST" "$fold" "$label" "$busy" "$tail"
    (( open )) || continue
    for d in "$sub"/*/; do
      [[ -f ${d}label ]] || continue
      n=${d%/}; n=${n##*/}
      m=" "; [[ $CUR == "pisub-$sess--$n" ]] && m="▶"
      busy=""; pid=""
      [[ -f ${d}pid ]] && read -r pid < "${d}pid"
      if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then busy="${YEL}●${RST}"
      elif [[ -f ${d}exit && $(<"${d}exit") != 0 ]]; then busy="${RED}✗${RST}"; fi
      read -r label < "${d}label"; label=${label:0:$((PAD - 16))}
      printf '%s\t%04d\t%s\t  %s       %s└ %s%s %s\n' "$2" "$3" "v:pisub-$sess--$n" "$m" "$DIM" "$label" "$RST" "$busy"
    done
  done
}

# group \t window-index \t target \t display  → stable sort by group keeps tab order
prev=""
while IFS=$'\t' read -r id idx active act path name; do
  m=" "; if [[ $active == 1 && ( -z $CUR || $CUR == main ) ]]; then m="▶"; elif [[ $act == 1 ]]; then m="•"; fi
  # show one steady glyph instead of the spinner so the sidebar isn't redrawn per frame
  if is_braille "$name"; then name="⋯${name:1}"; fi
  group_of "$path"
  child_count "$id"
  fold=" " open=1
  if (( REPLY_N > 0 )); then
    if [[ $COLLAPSED == *" $id "* ]]; then
      fold="▸" open=0
      (( VIEWING )) && m="▶"   # the child being viewed is folded away: point at its parent
    else fold="▾"; fi
  fi
  activity "$id"
  # the ⋯ spinner glyph is now shown as the activity dot instead
  name=${name#⋯ }; name=${name#✳ }
  name=${name:0:$((PAD - 6))}
  tail=""; tw=0
  if (( REPLY_N > 0 )); then
    busy_children "$id"
    if (( open == 0 )); then tail="${DIM} ${REPLY_N}${RST}"; tw=$((1 + ${#REPLY_N})); fi
    if (( REPLY_B > 0 )); then tail="$tail ${YEL}⋯${REPLY_B}${RST}"; tw=$((tw + 2 + ${#REPLY_B})); fi
  fi
  room=$(( PAD - 6 - ${#name} - tw )); (( room < 0 )) && room=0
  printf '%s\t%04d\t%s\t  %s %s %s%s%s%*s\n' "$REPLY" "$idx" "$id" "$m" "$fold" "$REPLY_A" "$name" "$tail" "$room" ''
  (( open )) && children "$id" "$REPLY" "$idx"
done < <(tmux list-windows -t main -F $'#{window_id}\t#{window_index}\t#{window_active}\t#{window_activity_flag}\t#{pane_current_path}\t#{window_name}' 2>/dev/null) |
sort -t$'\t' -s -k1,1 -k2,2 |
while IFS=$'\t' read -r g idx target display; do
  [[ $g == "$prev" ]] || { printf '\t%s%s%s\n' "$DIM" "$g" "$RST"; prev=$g; }
  printf '%s\t%s\n' "$target" "$display"
done
orphans=$(children "" workers 9999 | cut -f3-)
[[ -n $orphans ]] && { printf '\t%sworkers%s\n' "$DIM" "$RST"; printf '%s\n' "$orphans"; }
exit 0
