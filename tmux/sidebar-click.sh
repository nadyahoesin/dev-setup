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
COLLAPSED_FILE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.collapsed"
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
case "$target" in
  @*) if on_fold; then
        # clicked the fold glyph of a tab that has worker children: toggle them
        if grep -qx -- "$target" "$COLLAPSED_FILE" 2>/dev/null; then
          grep -vx -- "$target" "$COLLAPSED_FILE" > "$COLLAPSED_FILE.tmp"; mv -f "$COLLAPSED_FILE.tmp" "$COLLAPSED_FILE"
        else
          echo "$target" >> "$COLLAPSED_FILE"
          # folding the tab whose worker you're watching: go back to that tab
          cur=$(tmux list-clients -F '#{client_session}' | head -1)
          if [ "$cur" != main ] && grep -qx "parent_window=$target" "$HOME/.orchestrate-subagents/$cur.env" 2>/dev/null; then
            for c in $(tmux list-clients -F '#{client_tty}'); do tmux switch-client -c "$c" -t "main:$target"; done
          fi
        fi
        exec "$HOME/.config/tmux/sidebar-refresh.sh"
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
