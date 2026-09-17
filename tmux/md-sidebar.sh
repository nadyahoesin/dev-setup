#!/usr/bin/env bash
# Show a file in the window's sidebar pane (cmux-style), rendered by mdview.py —
# markdown rendered, anything else shown as it is.
#
# There is exactly one sidebar pane per window and it is never split: opening
# another file adds a tab to it and switches to that tab. The pane and the
# viewer talk through two files named after the window:
#   <list>         one open file per line, in tab order
#   <list>.active  the file the viewer should be showing
#   md-sidebar.sh <pane_id> <file>
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
pane="$1" file="$2"
case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
[ -f "$file" ] || { tmux display-message "not a file: $file"; exit 1; }

win=$(tmux display-message -p -t "$pane" '#{window_id}') || exit 1
LIST="${TMPDIR:-/tmp}/tmux-mdview-$UID-${win#@}.tabs"

existing=$(tmux list-panes -t "$pane" -F '#{pane_id} #{@md_sidebar}' 2>/dev/null | awk '$2=="1"{print $1; exit}')
if [ -z "$existing" ]; then
  : > "$LIST"                      # a new sidebar starts with no tabs but this one
fi
grep -qxF -- "$file" "$LIST" 2>/dev/null || printf '%s\n' "$file" >> "$LIST"
printf '%s\n' "$file" > "$LIST.active"

if [ -z "$existing" ]; then
  # no `exec`, and the pane is held open on a non-zero exit: if the viewer ever
  # dies on its own the traceback stays on screen instead of vanishing with it
  # (Textual draws on stderr, so redirecting that away blanks the pane)
  existing=$(tmux split-window -h -d -l 45% -t "$pane" -P -F '#{pane_id}' \
    "$HOME/.config/tmux/mdview.py $(printf '%q' "$LIST"); s=\$?; [ \$s -eq 0 ] || { echo; echo \"mdview exited \$s — press enter\"; read -r _; }") || exit 1
  tmux set-option -p -t "$existing" @md_sidebar 1
fi
tmux select-pane -t "$existing" -T "md: $(basename "$file")"
