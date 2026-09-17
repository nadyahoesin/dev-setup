#!/usr/bin/env bash
# Background redraw every 3s so shell commands starting/finishing and worker
# turns show up without a tmux hook. sidebar-refresh.sh only pushes to fzf when
# the rows actually changed, so an unchanged tick costs one list build.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
exec >/dev/null 2>&1
PID="${TMPDIR:-/tmp}/tmux-sidebar-$UID.poll.pid"
if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then exit 0; fi
echo $$ > "$PID"
while tmux has-session -t main 2>/dev/null; do
  "$HOME/.config/tmux/sidebar-refresh.sh"
  sleep 3
done
rm -f "$PID"
