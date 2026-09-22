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

# Every hook event names the turn it belongs to (prompt_id), and a background
# agent's tool calls keep the id of the turn that spawned them. That is the one
# signal that separates "this pane is working" from "something the last turn
# left running" — session_id and transcript_path are the parent's for both.
# Ids we have already seen are remembered per pane, capped.
pid=$(printf '%s' "$json" | jq -r '.prompt_id // ""')
SEEN="${TMPDIR:-/tmp}/tmux-agent-turns-$UID-${TMUX_PANE#%}"
seen() { [ -n "$pid" ] && [ -f "$SEEN" ] && grep -qxF -- "$pid" "$SEEN"; }
remember() {
  [ -n "$pid" ] || return 0
  seen || printf '%s\n' "$pid" >> "$SEEN"
  [ "$(wc -l < "$SEEN")" -gt 50 ] && { tail -25 "$SEEN" > "$SEEN.tmp" && mv -f "$SEEN.tmp" "$SEEN"; }
  return 0
}
case "$want" in
  prompt) want=working turn=1; remember ;;   # UserPromptSubmit
  idle)   # Stop, and SessionStart — said explicitly, so the sidebar shows a grey dot.
    # Except a compaction: it fires SessionStart in the middle of the very turn
    # it is compacting, and closing the turn there strands the tab grey for the
    # rest of that turn — every event after it carries the running turn's id,
    # which is by then one we have already seen, and so reads as old work.
    # `source` is SessionStart's alone (startup/resume/clear/compact/fork).
    [ "$(printf '%s' "$json" | jq -r '.source // ""')" = compact ] && exit 0
    want=idle turn=0 ;;
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
    if [ "$(TMUX= $T display -t "$TMUX_PANE" -p '#{@agent_turn}')" != 1 ]; then
      # No turn open. Either this belongs to a turn that has already ended —
      # a straggler, or a background agent it left running, neither of which
      # stops you typing — or to a turn whose UserPromptSubmit never fired,
      # as when a session is started with a prompt on the command line. The
      # id says which: one we have seen is old work, one we have not is a
      # live turn nobody told us about.
      seen && exit 0
      [ -n "$pid" ] || exit 0          # no id to judge by: assume old work
      remember
      turn=1
    fi
    if [ "$want" = pre ] && [ -n "$blocking" ]; then want=waiting
    else
      # A question or permission prompt sits *inside* an open turn: the main
      # loop is stopped dead until you answer, so while the pane is waiting,
      # *no* tool event of any kind can be the main loop's — a background
      # agent the turn left running is the only thing that can still call
      # tools. Ignore them all; only the blocking tool's own PostToolUse means
      # you answered and work resumed.
      if [ -z "$blocking" ] &&
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
