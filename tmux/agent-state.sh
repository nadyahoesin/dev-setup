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
# which agent owns this pane, so the sidebar can tell Claude Code from pi
# (pi sets this from its tmux-agent-state extension). Only written when it
# changes: this hook runs on every tool call.
[ "$(TMUX= $T display -t "$TMUX_PANE" -p '#{@agent_kind}')" = claude ] ||
  TMUX= $T set -p -t "$TMUX_PANE" @agent_kind claude
turn=""     # 1 = open the turn, 0 = close it, empty = leave it as it is
case "$want" in
  prompt) want=working turn=1 ;;   # UserPromptSubmit
  idle)   want=idle    turn=0 ;;   # Stop — said explicitly, so the sidebar can show a grey dot
  notify)
    # only a permission / question prompt means "needs you"; the 60s idle nudge doesn't
    kind=$(printf '%s' "$json" | jq -r '(.notification_type // "") + " " + (.message // "")')
    case "$kind" in *permission*|*approval*|*question*) want=waiting ;; *) exit 0 ;; esac ;;
  pre|working)                     # PreToolUse / PostToolUse
    # AskUserQuestion and ExitPlanMode block on you by definition, so they say
    # "needs you" themselves. Notification can't be relied on for it: it is a
    # notification, and one doesn't always arrive for a question — a tab asking
    # one would then keep the yellow dot its own PreToolUse just set.
    blocking=""
    case "$json" in *'"tool_name":"AskUserQuestion"'*|*'"tool_name":"ExitPlanMode"'*) blocking=1 ;; esac
    # No turn open means no foreground turn is running: a tool event here
    # belongs to a background agent, which does not stop you typing, or is a
    # straggler from the turn that just ended. Neither is "working".
    #
    # This used to take a late event as a turn whose UserPromptSubmit we had
    # missed, to catch a session started from the command line. It caught
    # background agents instead and left tabs yellow for hours while their
    # prompt sat empty — a worse error, because an idle-looking tab you cannot
    # trust is the whole reason this file exists.
    [ "$(TMUX= $T display -t "$TMUX_PANE" -p '#{@agent_turn}')" = 1 ] || exit 0
    if [ "$want" = pre ] && [ -n "$blocking" ]; then want=waiting
    else
      # A question or permission prompt sits *inside* an open turn, and a late
      # PostToolUse — a backgrounded agent's, say — would otherwise paint the
      # tab yellow again while it is still waiting on you. Only a tool actually
      # starting, or the blocking tool itself finishing, means work resumed.
      if [ "$want" = working ] && [ -z "$blocking" ] &&
         [ "$(TMUX= $T display -t "$TMUX_PANE" -p '#{@agent_state}')" = waiting ]; then exit 0; fi
      want=working
    fi ;;
esac
[ "$turn" = 1 ] && TMUX= $T set -p -t "$TMUX_PANE" @agent_turn 1
[ "$turn" = 0 ] && { TMUX= $T set -p -u -t "$TMUX_PANE" @agent_turn
                     TMUX= $T set -p -t "$TMUX_PANE" @agent_idle_at "$(date +%s)"; }
cur=$(TMUX= $T display -t "$TMUX_PANE" -p '#{@agent_state}')
[ "$cur" = "$want" ] && exit 0          # PostToolUse fires constantly; only redraw on a change
if [ -n "$want" ]; then TMUX= $T set -p -t "$TMUX_PANE" @agent_state "$want"
else TMUX= $T set -p -u -t "$TMUX_PANE" @agent_state; fi
"$HOME/.config/tmux/sidebar-refresh.sh" >/dev/null 2>&1 &
exit 0
