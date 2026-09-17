#!/usr/bin/env bash
# Left-hand tab list for the "main" tmux session, rendered with fzf as a
# pure display (no input line, no key/mouse handling). Clicks are handled
# by the outer tmux (ui.conf → sidebar-click.sh); refreshes arrive over the
# unix socket from tmux hooks (sidebar-refresh.sh). Never polls.
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
unset TMUX   # always address the default ("main") server, not the outer ui one

SOCK="${TMPDIR:-/tmp}/tmux-sidebar-$UID.sock"
LIST="$HOME/.config/tmux/sidebar-list.sh"
CACHE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.rows"   # rows currently shown; refresh/pos/click read it

rm -f "$SOCK"
# smooth wheel scrolling: one long-lived renderer fed by a FIFO (see sidebar-scrolld.py)
SCROLLD_PID="${TMPDIR:-/tmp}/tmux-sidebar-$UID.scrolld.pid"
if ! { [ -f "$SCROLLD_PID" ] && kill -0 "$(cat "$SCROLLD_PID")" 2>/dev/null; }; then
  python3 "$HOME/.config/tmux/sidebar-scrolld.py" </dev/null >/dev/null 2>&1 &
fi
tmux -L ui set -g @sidebar_fifo "${TMPDIR:-/tmp}/tmux-sidebar-$UID.scroll.fifo" 2>/dev/null
while :; do
  # If main is gone, wait for it to come back.
  if ! tmux has-session -t main 2>/dev/null; then sleep 1; continue; fi
  "$LIST" > "${TMPDIR:-/tmp}/tmux-sidebar-$UID.all"
  "$HOME/.config/tmux/sidebar-view.sh" | tee "$CACHE" | fzf \
    --listen="$SOCK" \
    --no-input --layout=reverse --no-info --no-separator --no-scrollbar \
    --delimiter='\t' --with-nth=2 \
    --pointer=' ' --marker='' --gutter=' ' --margin=0,0,0,1 \
    --color='fg:-1,bg:-1,fg+:-1,bg+:-1,hl:-1,hl+:-1,gutter:-1,pointer:-1' \
    --no-mouse --cycle --no-clear --ansi \
    --bind "load:transform($HOME/.config/tmux/sidebar-pos.sh)" \
    >/dev/null
  sleep 0.2
done
