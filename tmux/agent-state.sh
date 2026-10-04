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
  prompt) want=working turn=1; remember
    # A new turn is a clean slate: any background agent still counted here died
    # without its SubagentStop, and must not keep the tab yellow.
    TMUX= $T set -p -u -t "$TMUX_PANE" @agent_bg
    # An idle session may have been put on background QoS (taskpolicy -b) to
    # give the rest of the machine room under memory pressure; the moment you
    # type into it again it is the one that matters, so undo that for it and
    # everything it started. Async: this hook is on the prompt's critical path.
    ( cp=$(pgrep -P "$(TMUX= $T display -t "$TMUX_PANE" -p '#{pane_pid}')" | head -1)
      fg() { taskpolicy -B -p "$1"; for c in $(pgrep -P "$1"); do fg "$c"; done; }
      [ -n "$cp" ] && fg "$cp" ) >/dev/null 2>&1 & ;;
  bgstart|bgstop)
    # A background subagent (Explore, Task, ...) runs *inside* the Claude
    # process: there is no child process, so the shell scan in sidebar-list.sh
    # cannot see it, and its tool events carry the prompt_id of the turn that
    # spawned it — by then already seen, so they read as stragglers and are
    # dropped. A turn that ends while agents are still running therefore went
    # grey and stayed grey, with the pane itself saying "Waiting for N
    # background agents to finish". SubagentStart/SubagentStop are the only
    # events that bound a subagent's life, so count them.
    # The count says how many; the sidebar also lists them, one row each, the
    # way it lists pi workers. So keep a file per live subagent, named by its
    # id: line 1 is its transcript (minus .jsonl — the .meta.json beside it
    # holds the description), line 2 its type, for the moment before the meta
    # exists. Line 3 is when its clock started, as Claude Code shows it beside
    # the subagent: at its first start, and again each time it is sent a
    # message (see SendMessage below) — but not when it merely stops and picks
    # itself up again, as one waiting on a background command does. Line 4,
    # once it has stopped, is what the clock froze at. That running time is the
    # only thing a row in Claude Code's list can be told apart by.
    # A finished one is kept as <id>.done so a row you are looking at
    # does not vanish under you; those are swept after two hours.
    aid=$(printf '%s' "$json" | jq -r '.agent_id // ""')
    case "$aid" in ''|*[!A-Za-z0-9_-]*) aid="" ;; esac
    if [ -n "$aid" ]; then
      REG="$HOME/.orchestrate-subagents/cc/${TMUX_PANE#%}"
      if [ "$want" = bgstart ]; then
        mkdir -p "$REG"
        if [ -f "$REG/$aid.done" ]; then
          # A finished subagent given another message starts again under the
          # same id: take its file back; its clock runs on from where it started.
          { IFS= read -r l1; IFS= read -r l2; IFS= read -r at; } < "$REG/$aid.done"
          case "$at" in ''|*[!0-9]*) at=$(stat -f %B "$REG/$aid.done") ;; esac
          mv -f "$REG/$aid.done" "$REG/$aid"
          printf '%s\n%s\n%s\n' "$l1" "$l2" "$at" > "$REG/$aid"
        else
          tp=$(printf '%s' "$json" | jq -r '.transcript_path // ""')
          printf '%s\n%s\n%s\n' "${tp%.jsonl}/subagents/agent-$aid" \
            "$(printf '%s' "$json" | jq -r '.agent_type // "agent"')" "$(date +%s)" > "$REG/$aid"
        fi
        find "$REG" -name '*.done' -mmin +120 -delete
      elif [ -f "$REG/$aid" ]; then
        { IFS= read -r l1; IFS= read -r l2; IFS= read -r at; } < "$REG/$aid"
        case "$at" in ''|*[!0-9]*) at=$(stat -f %B "$REG/$aid") ;; esac
        printf '%s\n%s\n%s\n%s\n' "$l1" "$l2" "$at" "$(( $(date +%s) - at ))" > "$REG/$aid"
        mv -f "$REG/$aid" "$REG/$aid.done"
      fi
    fi
    n=$(TMUX= $T display -t "$TMUX_PANE" -p '#{@agent_bg}')
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$want" = bgstart ]; then n=$((n + 1)); else n=$((n - 1)); fi
    [ "$n" -lt 0 ] && n=0
    TMUX= $T set -p -t "$TMUX_PANE" @agent_bg "$n"
    TMUX= $T set -p -t "$TMUX_PANE" @agent_bg_at "$(date +%s)"
    "$HOME/.config/tmux/sidebar-refresh.sh" >/dev/null 2>&1 &
    exit 0 ;;
  compact)   # PreCompact
    # A compaction you ask for (/compact) is not a turn: no UserPromptSubmit
    # opens one, so the tab sat grey through minutes of "Compacting
    # conversation…". Open one here. An automatic compaction happens inside a
    # turn that is already open, and this is a no-op for it.
    want=working turn=1 ;;
  compacted)   # PostCompact
    # …and close it again when a manual one is done. An automatic one hands
    # back to the turn it interrupted, which is still working.
    [ "$(printf '%s' "$json" | jq -r '.trigger // ""')" = manual ] || exit 0
    want=idle turn=0 ;;
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
    # A message to a subagent restarts its clock in Claude Code's list; note
    # when, or the sidebar can no longer tell which row is which (see bgstart).
    case "$want$json" in pre*'"tool_name":"SendMessage"'*)
      to=$(printf '%s' "$json" | jq -r '.tool_input.to // ""')
      case "$to" in ''|*[!A-Za-z0-9_-]*) to="" ;; esac
      for f in "$HOME/.orchestrate-subagents/cc/${TMUX_PANE#%}/$to" "$HOME/.orchestrate-subagents/cc/${TMUX_PANE#%}/$to.done"; do
        [ -n "$to" ] && [ -f "$f" ] || continue
        { IFS= read -r l1; IFS= read -r l2; } < "$f"
        printf '%s\n%s\n%s\n' "$l1" "$l2" "$(date +%s)" > "$f"
      done ;;
    esac
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
      # Dropped as old work — but a *live* background agent's tool calls look
      # exactly like this, so use them as its heartbeat. Paired with the
      # @agent_bg count (which alone can drift if an agent dies without its
      # SubagentStop), this is what lets the working state decay by itself.
      if seen; then TMUX= $T set -p -t "$TMUX_PANE" @agent_bg_at "$(date +%s)"; exit 0; fi
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
