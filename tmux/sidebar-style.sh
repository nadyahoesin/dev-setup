#!/usr/bin/env bash
# Pick how the sidebar separates tabs:  sidebar-style.sh [spaced|dividers|cards|sections|next]
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
F="${TMPDIR:-/tmp}/tmux-sidebar-$UID.style"
styles=(spaced dividers cards sections)
cur=spaced; [ -f "$F" ] && read -r cur < "$F"
want=${1:-next}
if [ "$want" = next ]; then
  for i in "${!styles[@]}"; do [ "${styles[$i]}" = "$cur" ] && want=${styles[$(( (i + 1) % ${#styles[@]} ))]}; done
  [ "$want" = next ] && want=spaced
fi
echo "$want" > "$F"
"$HOME/.config/tmux/sidebar-refresh.sh"
unset TMUX; tmux display-message "sidebar style: $want" 2>/dev/null
