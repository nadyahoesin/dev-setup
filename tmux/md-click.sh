#!/usr/bin/env bash
# Double-click hook: if the double-clicked text is a path to an existing .md
# file, open it in the markdown sidebar and exit 0. Otherwise exit 1 so tmux runs
# the normal double-click (select word + copy).
#   md-click.sh <pane_id> <pane_current_path> <mouse_x> <mouse_line>
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
pane="$1" cwd="$2" x="$3" line="$4"
path=$(python3 "$HOME/.config/tmux/md-click-parse.py" "$x" "$line") || exit 1
case "$path" in
  "~/"*) path="$HOME/${path#\~/}" ;;
  /*) ;;
  *) path="$cwd/$path" ;;
esac
[ -f "$path" ] || exit 1
cd "$cwd" 2>/dev/null
"$HOME/.config/tmux/md-sidebar.sh" "$pane" "$path"
exit 0
