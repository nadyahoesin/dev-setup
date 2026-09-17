#!/usr/bin/env bash
# Claude Code hook → per-pane activity state for the tmux sidebar.
#   agent-state.sh working|idle|notify   (hook JSON on stdin)
# Stored as the pane option @agent_state: working / waiting / (unset = idle).
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
exec 2>/dev/null
json=$(cat)
[ -n "${TMUX_PANE:-}" ] || exit 0
T=/opt/homebrew/bin/tmux
want=$1
if [ "$want" = notify ]; then
  # only a permission / question prompt means "needs you"; the 60s idle nudge doesn't
  kind=$(printf '%s' "$json" | jq -r '(.notification_type // "") + " " + (.message // "")')
  case "$kind" in *permission*|*approval*|*question*) want=waiting ;; *) exit 0 ;; esac
fi
[ "$want" = idle ] && want=""
cur=$(TMUX= $T display -t "$TMUX_PANE" -p '#{@agent_state}')
[ "$cur" = "$want" ] && exit 0          # PostToolUse fires constantly; only redraw on a change
if [ -n "$want" ]; then TMUX= $T set -p -t "$TMUX_PANE" @agent_state "$want"
else TMUX= $T set -p -u -t "$TMUX_PANE" @agent_state; fi
"$HOME/.config/tmux/sidebar-refresh.sh" >/dev/null 2>&1 &
exit 0
