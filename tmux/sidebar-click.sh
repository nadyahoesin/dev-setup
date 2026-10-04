#!/usr/bin/env bash
# Outer-tmux mouse handler: a left click at row $1 of the sidebar pane.
# Every cache line takes one screen row; line 1 (screen row 0) is a blank parking row.
# List rows come from sidebar-list.sh, whose
# first field is the target: "@id" = tab in main, "" = group header (no-op).
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
unset TMUX
export LC_ALL=en_US.UTF-8   # ${#var} counts characters (fold-glyph column)
exec 2>/dev/null   # never let a stray error reach tmux/fzf output
y=$(( ${1:-0} + 1 ))      # screen row N shows cache line N+1 (line 1 is the blank parking row)
x=${2:--1}               # screen column (content starts at 2: fzf margin + gutter)
[ "$y" -ge 2 ] 2>/dev/null || exit 0
CACHE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.rows"   # what the sidebar is showing right now
[ -s "$CACHE" ] || { "$HOME/.config/tmux/sidebar-list.sh" > "${TMPDIR:-/tmp}/tmux-sidebar-$UID.all"; "$HOME/.config/tmux/sidebar-view.sh" > "$CACHE"; }
target=$(sed -n "${y}p" "$CACHE" | cut -f1)
COLLAPSED_FILE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.collapsed"   # tabs whose worker list is folded away
HINT="${TMPDIR:-/tmp}/tmux-sidebar-$UID.ccview"   # "<pane> <agent id|main> <when>": what a click is about to put on screen
# did the click land on this row's fold glyph (▸/▾)? Its column depends on the
# sidebar style (boxes shift it), so find it in the row itself.
on_fold() {
  local vis n
  vis=$(sed -n "${y}p" "$CACHE" | cut -f2 | sed $'s/\x1b\\[[0-9;]*m//g')
  # bash 3.2 matches multibyte glyphs byte-wise (▸ shares bytes with ─), so let
  # grep/sed/wc do the Unicode work
  printf '%s' "$vis" | grep -q '[▾▸]' || return 1
  n=$(printf '%s' "$vis" | sed 's/[▾▸].*//' | wc -m | tr -d ' ')
  [ "$x" -ge $(( n + 1 )) ] && [ "$x" -le $(( n + 3 )) ]
}
# did the click land on this row's ✕ (right edge of a tab's card)?
on_close() {
  local vis n
  vis=$(sed -n "${y}p" "$CACHE" | cut -f2 | sed $'s/\x1b\\[[0-9;]*m//g')
  printf '%s' "$vis" | grep -q '✕' || return 1
  n=$(printf '%s' "$vis" | sed 's/✕.*//' | wc -m | tr -d ' ')
  [ "$x" -ge $(( n + 1 )) ] && [ "$x" -le $(( n + 3 )) ]
}
case "$target" in
  @*) if on_close; then
        # same as ⌘W: close the tab's active pane
        tmux kill-pane -t "main:$target"
        exec "$HOME/.config/tmux/sidebar-refresh.sh"
      fi
      if on_fold; then
        # clicked the fold glyph: hide this tab's workers, or list them again
        if grep -qx -- "$target" "$COLLAPSED_FILE" 2>/dev/null; then
          grep -vx -- "$target" "$COLLAPSED_FILE" > "$COLLAPSED_FILE.tmp"; mv -f "$COLLAPSED_FILE.tmp" "$COLLAPSED_FILE"
        else
          echo "$target" >> "$COLLAPSED_FILE"
          # folding away the worker you're watching: go back to its tab
          cur=$(tmux list-clients -F '#{client_session}' | head -1)
          case "$cur" in pisub-*) cur=${cur#pisub-}; cur=${cur%%--*} ;; esac
          if [ "$cur" != main ] && grep -qx "parent_window=$target" "$HOME/.orchestrate-subagents/$cur.env" 2>/dev/null; then
            for c in $(tmux list-clients -F '#{client_tty}'); do tmux switch-client -c "$c" -t "main:$target"; done
          fi
        fi
        exec "$HOME/.config/tmux/sidebar-refresh.sh"
      fi
      # A tab row is the main agent: if the pane is showing a subagent, go back
      # to main before switching, so the subagent is never what you land on.
      # Decided from one screen read — a plain tab switch must stay instant.
      p=$(tmux display -t "main:$target" -p '#{pane_id} #{@agent_kind}')
      if [ "${p#* }" = claude ] &&
         tmux capture-pane -p -t "${p%% *}" | tail -30 | grep -v '⏺ main' | grep -q '^[ ❯├└│]*⏺ .* · ↓'; then
        printf '%s %s %s\n' "${p%% *}" main "$(date +%s)" | sed 's/^%//' > "$HINT"
        "$HOME/.config/tmux/sidebar-refresh.sh" &
        "$HOME/.config/tmux/cc-agent-open.pl" "${p%% *}" main
        : > "$HINT"; for f in "${TMPDIR:-/tmp}/tmux-sidebar-$UID".ccnames.*; do [ -f "$f" ] && : > "$f"; done
      fi
      for c in $(tmux list-clients -F '#{client_tty}'); do tmux switch-client -c "$c" -t "main:$target"; done ;;
  s:*) if on_fold; then
        # clicked the fold glyph of a worker that started nested `pi -p` runs
        sess=${target#s:}; EXPANDED_FILE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.expanded"
        if grep -qx -- "$sess" "$EXPANDED_FILE" 2>/dev/null; then
          grep -vx -- "$sess" "$EXPANDED_FILE" > "$EXPANDED_FILE.tmp"; mv -f "$EXPANDED_FILE.tmp" "$EXPANDED_FILE"
          cur=$(tmux list-clients -F '#{client_session}' | head -1)
          case "$cur" in "pisub-$sess--"*)   # folding the run you're watching: go to its worker
            for c in $(tmux list-clients -F '#{client_tty}'); do tmux switch-client -c "$c" -t "=$sess"; done ;;
          esac
        else
          echo "$sess" >> "$EXPANDED_FILE"
        fi
        exec "$HOME/.config/tmux/sidebar-refresh.sh"
      fi
      for c in $(tmux list-clients -F '#{client_tty}'); do tmux switch-client -c "$c" -t "=${target#s:}"; done ;;
  v:ccsub-*) # a Claude Code subagent: same idea, following its transcript
       view=${target#v:}; id=${view#ccsub-}; base="" reg=""
       if on_fold; then   # the fold glyph of a subagent that started subagents of its own
         EXPANDED_FILE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.expanded"
         if sed -n "${y}p" "$CACHE" | grep -q '▾'; then
           # Folding. It may be open only because you are looking at one of its
           # subagents (├ └ on the row Claude Code marks ⏺): then go up to the
           # parent, as folding a pi worker's run you are watching does —
           # otherwise it could never be closed.
           grep -vx -- "$view" "$EXPANDED_FILE" 2>/dev/null > "$EXPANDED_FILE.tmp"; mv -f "$EXPANDED_FILE.tmp" "$EXPANDED_FILE"
           for f in "$HOME/.orchestrate-subagents/cc"/*/"$id" "$HOME/.orchestrate-subagents/cc"/*/"$id.done"; do
             [ -f "$f" ] || continue
             p=${f%/*}; p="%${p##*/}"
             if tmux capture-pane -p -t "$p" | tail -30 | grep -q '[├└] *⏺ '; then
               printf '%s %s %s\n' "${p#%}" "$id" "$(date +%s)" > "$HINT"
               "$HOME/.config/tmux/cc-agent-open.pl" "$p" "$f"
             fi
             : > "$HINT"; for f in "${TMPDIR:-/tmp}/tmux-sidebar-$UID".ccnames.*; do [ -f "$f" ] && : > "$f"; done
             break
           done
         else
           echo "$view" >> "$EXPANDED_FILE"
         fi
         exec "$HOME/.config/tmux/sidebar-refresh.sh"
       fi
       for f in "$HOME/.orchestrate-subagents/cc"/*/"$id" "$HOME/.orchestrate-subagents/cc"/*/"$id.done"; do
         [ -f "$f" ] && { IFS= read -r base < "$f"; reg=$f; break; }
       done
       [ -n "$base" ] || exit 0
       # The real thing first: go to the tab that owns it and have Claude Code
       # open the subagent in its own view. Only when it cannot — the subagent
       # is no longer in Claude Code's list — fall back to following the
       # transcript in a session of its own.
       # every tmux call is a process, and under memory pressure each one is
       # ~80ms: ask for the window and the clients in one, switch in one more
       p=${reg%/*}; p="%${p##*/}"
       info=$(tmux display -t "$p" -p '#{window_id}' \; list-clients -F '#{client_tty}' 2>/dev/null)
       win=${info%%$'\n'*}; clients=${info#*$'\n'}; [ "$clients" = "$info" ] && clients=""
       case "$win" in @*) ;; *) win="" ;; esac
       # Keys first, switch after: switching first showed whatever that pane
       # had up — its main agent, or another subagent — and highlighted that
       # row for the moment it took the keys to land.
       # The highlight follows what the pane shows, which it only shows once
       # the keys have landed and the sidebar has been redrawn after that. Say
       # now what is about to be on screen, and redraw at once, so the row
       # lights up with the click instead of a moment after it.
       [ -n "$win" ] && { printf '%s %s %s\n' "${p#%}" "$id" "$(date +%s)" > "$HINT"; "$HOME/.config/tmux/sidebar-refresh.sh" & }
       if [ -n "$win" ] && "$HOME/.config/tmux/cc-agent-open.pl" "$p" "$reg"; then
         for c in $clients; do tmux select-pane -t "$p" \; switch-client -c "$c" -t "main:$win"; done
         : > "$HINT"; for f in "${TMPDIR:-/tmp}/tmux-sidebar-$UID".ccnames.*; do [ -f "$f" ] && : > "$f"; done   # the keys have landed: the screen is the truth again
         exec "$HOME/.config/tmux/sidebar-refresh.sh"
       fi
       : > "$HINT"; for f in "${TMPDIR:-/tmp}/tmux-sidebar-$UID".ccnames.*; do [ -f "$f" ] && : > "$f"; done
       tmux has-session -t "=$view" 2>/dev/null ||
         tmux new-session -d -s "$view" -x 200 -y 50 "$HOME/.config/tmux/cc-agent-view.sh '$base'"
       for c in $(tmux list-clients -F '#{client_tty}'); do tmux switch-client -c "$c" -t "=$view"; done ;;
  v:*) # a nested `pi -p` run: a read-only session tailing its transcript, made on first open
       view=${target#v:}; rest=${view#pisub-}; sess=${rest%--*}; n=${rest##*--}
       log="$HOME/.orchestrate-subagents/pi/$sess/sub/$n/transcript.log"
       [ -f "$log" ] || exit 0
       tmux has-session -t "=$view" 2>/dev/null ||
         tmux new-session -d -s "$view" -x 200 -y 50 "printf '\\e[2m%s\\e[0m\\n' \"\$(cat '${log%/*}/label')\"; tail -n +1 -F '$log'"
       for c in $(tmux list-clients -F '#{client_tty}'); do tmux switch-client -c "$c" -t "=$view"; done ;;
  *)  exit 0 ;;
esac
"$HOME/.config/tmux/sidebar-refresh.sh"   # switch-client fires no select-window hook
