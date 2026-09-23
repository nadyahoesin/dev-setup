#!/usr/bin/env bash
# Reconcile every Claude pane's sidebar markers with what the pane actually shows.
#   sidebar-resync.sh [-n]      -n = report only, change nothing
#
# The markers are event-driven (hooks), so anything that happens while a hook is
# missing leaves them stale for good: a session started before a hook existed, a
# hook that failed, a turn interrupted mid-flight. Nothing else ever re-derives
# them. This reads the pane itself — the one source that cannot drift — and puts
# the markers back in agreement.
#
# Only three things are decidable from the screen, and only those are touched:
#   a question/permission prompt is open   -> waiting
#   background agents are listed           -> @agent_bg = N, heartbeat stamped
#   neither, and no turn is open           -> idle
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
T=/opt/homebrew/bin/tmux
unset TMUX
dry=0; [ "${1:-}" = -n ] && dry=1
now=$($(command -v date) +%s)
changed=0

set -- $($T list-panes -s -t main -F '#{pane_id}' 2>/dev/null)
for p in "$@"; do
  [ "$($T display -t "$p" -p '#{@agent_kind}')" = claude ] || continue
  win=$($T display -t "$p" -p '#{window_name}')
  st=$($T display -t "$p" -p '#{@agent_state}')
  turn=$($T display -t "$p" -p '#{@agent_turn}')
  scr=$($T capture-pane -p -t "$p" 2>/dev/null | tail -40)

  # A blocking prompt draws its own key hints; nothing else on screen does.
  asking=0
  case "$scr" in
    *"Enter to select"*|*"Do you want to proceed"*|*"Do you want to allow"*) asking=1 ;;
  esac
  # Background agents are the "◯ <name> … · ↓ <n> tokens" rows under the footer.
  # `← N agent` is only the switcher hint and says nothing about what is running.
  n=$(printf '%s\n' "$scr" | grep -cE '^[[:space:]]*◯[[:space:]]+.*·[[:space:]]+↓')

  want_st=""; want_bg=""
  if [ "$asking" = 1 ]; then want_st=waiting
  elif [ "$n" -gt 0 ]; then want_bg=$n
  else
    want_bg=0
    [ "$turn" = 1 ] || want_st=idle
  fi

  note=""
  if [ -n "$want_st" ] && [ "$want_st" != "$st" ]; then
    note="state ${st:-unset} -> $want_st"
    [ "$dry" = 1 ] || $T set -p -t "$p" @agent_state "$want_st"
  fi
  if [ -n "$want_bg" ]; then
    cur=$($T display -t "$p" -p '#{@agent_bg}')
    if [ "$want_bg" != "${cur:-0}" ] || [ "$want_bg" -gt 0 ]; then
      [ "$want_bg" != "${cur:-0}" ] && note="${note:+$note, }bg ${cur:-0} -> $want_bg"
      if [ "$dry" != 1 ]; then
        $T set -p -t "$p" @agent_bg "$want_bg"
        [ "$want_bg" -gt 0 ] && $T set -p -t "$p" @agent_bg_at "$now"
      fi
    fi
  fi
  [ -n "$note" ] && { printf '%-32s %s\n' "${win#✳ }" "$note"; changed=$((changed + 1)); }
done

[ "$changed" = 0 ] && echo "all panes already agree with their screens"
[ "$dry" = 1 ] || "$HOME/.config/tmux/sidebar-refresh.sh" >/dev/null 2>&1
exit 0
