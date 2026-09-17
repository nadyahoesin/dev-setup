#!/usr/bin/env bash
# Show a markdown file in a right-hand sidebar pane of the given pane's window
# (cmux-style), rendered by mdview.py. Reuses the window's sidebar if present.
#   md-sidebar.sh <pane_id> <file>
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
pane="$1" file="$2"
case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
[ -f "$file" ] || { tmux display-message "not a file: $file"; exit 1; }
view="exec $HOME/.config/tmux/mdview.py $(printf '%q' "$file")"

existing=$(tmux list-panes -t "$pane" -F '#{pane_id} #{@md_sidebar}' 2>/dev/null | awk '$2=="1"{print $1; exit}')
if [ -n "$existing" ]; then
  tmux respawn-pane -k -t "$existing" "$view"
else
  existing=$(tmux split-window -h -d -l 45% -t "$pane" -P -F '#{pane_id}' "$view") || exit 1
  tmux set-option -p -t "$existing" @md_sidebar 1
fi
tmux select-pane -t "$existing" -T "md: $(basename "$file")"
