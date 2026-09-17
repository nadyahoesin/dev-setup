#!/usr/bin/env bash
# Claude Code hook → per-pane activity state for the tmux sidebar.
#   agent-state.sh working|idle|notify   (hook JSON on stdin)
# Stored as the pane option @agent_state: working / waiting / (unset = idle).
#
# @agent_turn marks a turn as open, and exists because PostToolUse is an async
# hook: one fired by the last tool of a turn can land *after* the (synchronous)
# Stop hook has already set the pane idle, which left the tab yellow forever.
# UserPromptSubmit opens the turn, Stop closes it, and a "working" that arrives
# with no turn open is a straggler from a turn that already ended — dropped.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
exec 2>/dev/null
json=$(cat)
[ -n "${TMUX_PANE:-}" ] || exit 0
T=/opt/homebrew/bin/tmux
want=$1
turn=""     # 1 = open the turn, 0 = close it, empty = leave it as it is
case "$want" in
  prompt) want=working turn=1 ;;   # UserPromptSubmit
  idle)   want=idle    turn=0 ;;   # Stop — said explicitly, so the sidebar can show a grey dot
  notify)
    # only a permission / question prompt means "needs you"; the 60s idle nudge doesn't
    kind=$(printf '%s' "$json" | jq -r '(.notification_type // "") + " " + (.message // "")')
    case "$kind" in *permission*|*approval*|*question*) want=waiting ;; *) exit 0 ;; esac ;;
  working)                         # PostToolUse: only valid inside an open turn
    [ "$(TMUX= $T display -t "$TMUX_PANE" -p '#{@agent_turn}')" = 1 ] || exit 0 ;;
esac
[ "$turn" = 1 ] && TMUX= $T set -p -t "$TMUX_PANE" @agent_turn 1
[ "$turn" = 0 ] && TMUX= $T set -p -u -t "$TMUX_PANE" @agent_turn
cur=$(TMUX= $T display -t "$TMUX_PANE" -p '#{@agent_state}')
[ "$cur" = "$want" ] && exit 0          # PostToolUse fires constantly; only redraw on a change
if [ -n "$want" ]; then TMUX= $T set -p -t "$TMUX_PANE" @agent_state "$want"
else TMUX= $T set -p -u -t "$TMUX_PANE" @agent_state; fi
"$HOME/.config/tmux/sidebar-refresh.sh" >/dev/null 2>&1 &
exit 0
