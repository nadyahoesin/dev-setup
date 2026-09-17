#!/usr/bin/env bash
# ⌘⇧M: pick a markdown file (glow preview) and open it in the right sidebar.
# Candidates, in order: .md paths printed in this pane (e.g. a report path an
# agent just wrote), then the .md files of the pane's git repo / folder.
#   md-view.sh <pane_id> <pane_current_path>
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
pane="${1:-}" cwd="${2:-$PWD}"
cd "$cwd" 2>/dev/null || cd "$HOME"

expand() { case "$1" in "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;; *) printf '%s\n' "$1" ;; esac; }

{
  tmux capture-pane -p -J -S -500 -t "$pane" 2>/dev/null |
    grep -oE '(~|\.{0,2})?/?[A-Za-z0-9._@/+-]+\.md\b' | awk '!seen[$0]++' | tail -r |
    while read -r p; do p=$(expand "$p"); [ -f "$p" ] && printf '%s\n' "$p"; done
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -co --exclude-standard -- '*.md' 2>/dev/null
  else
    find . -maxdepth 4 -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sed 's#^\./##'
  fi
} | awk '!seen[$0]++' >"${TMPDIR:-/tmp}/md-view.$$"

if [ ! -s "${TMPDIR:-/tmp}/md-view.$$" ]; then
  rm -f "${TMPDIR:-/tmp}/md-view.$$"
  tmux display-message "no markdown files here"
  exit 0
fi

fzf --no-multi --layout=reverse --no-info --prompt='md ▸ ' \
  --header='type to filter · Enter open in sidebar · ⌃O open in app · Esc close' \
  --preview 'glow -s "$HOME/.config/tmux/glow-sidebar.json" -w "$FZF_PREVIEW_COLUMNS" {}' --preview-window='right,62%,border-left' \
  --bind "enter:become($HOME/.config/tmux/md-sidebar.sh '$pane' \"\$PWD\"/{})" \
  --bind 'ctrl-o:execute-silent(open {})' \
  --color='fg:-1,bg:-1,fg+:#ffffff:bold,bg+:#0969da,hl:-1,hl+:#ffffff,header:8,prompt:4,gutter:-1' \
  <"${TMPDIR:-/tmp}/md-view.$$"
rm -f "${TMPDIR:-/tmp}/md-view.$$"
exit 0
