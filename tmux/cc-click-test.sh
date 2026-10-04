#!/usr/bin/env bash
# End-to-end check of clicking Claude Code subagent rows in the sidebar: runs
# the real click handler on real rows and reads back what the user would see —
# which view the pane shows and which sidebar row is highlighted.
#   cc-click-test.sh <pane id> <window id> <target>...
# target = an agent id, "tab" (the tab's own row = the main agent), or
# "fold:<agent id>" (the ▸/▾ glyph on that row). Needs live subagents in <pane>.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" LC_ALL=en_US.UTF-8
unset TMUX
pane=$1 win=$2; shift 2
CACHE="${TMPDIR:-/tmp}/tmux-sidebar-$UID.rows"
D="$HOME/.config/tmux"
strip() { sed $'s/\x1b\\[[0-9;]*m//g'; }
nap() { perl -e "select(undef,undef,undef,$1)"; }
desc() {   # agent id → its description
  local f; for f in "$HOME/.orchestrate-subagents/cc/${pane#%}/$1" "$HOME/.orchestrate-subagents/cc/${pane#%}/$1.done"; do
    [ -f "$f" ] && { jq -r '.description' "$(head -1 "$f").meta.json"; return; }
  done
}
view() {   # what the pane shows: main, or the description of the subagent on screen
  local t; t=$(tmux capture-pane -p -t "$pane" | tail -14 | grep -E '^─+ .* ─$' | tail -1 | sed -E 's/^─+ (.*) ─$/\1/')
  [ "$t" = "$(tmux display -t "$pane" -p '#{window_name}' | sed 's/^✳ //')" ] && t=main
  printf '%s' "${t:-main}"
}
lit() {    # target of the highlighted sidebar row
  awk -F'\t' '$NF == "▶" { print $1 }' "$CACHE" | head -1
}
pass=0 fail=0
for t in "$@"; do
  case $t in
    tab)    row=$win; want_view=main; want_lit=$win ;;
    fold:*) row="v:ccsub-${t#fold:}"; want_view="" want_lit="" ;;
    *)      row="v:ccsub-$t"; want_view=$(desc "$t"); want_lit=$row ;;
  esac
  "$D/sidebar-refresh.sh"; nap 0.3
  n=$(awk -F'\t' -v r="$row" '$1 == r { print NR; exit }' "$CACHE")
  if [ -z "$n" ]; then echo "SKIP  $t: no sidebar row"; continue; fi
  x=20
  case $t in fold:*) x=$(( $(sed -n "${n}p" "$CACHE" | cut -f2 | strip | sed 's/[▾▸].*//' | wc -m) + 2 )) ;; esac
  "$D/sidebar-click.sh" $((n - 1)) "$x"
  nap 0.7
  gv=$(view); gl=$(lit)
  # names: the sidebar's rows for this tab's subagents against Claude Code's own list, in order
  sb=$(awk -F'\t' '$1 ~ /^v:ccsub-/ { print $2 }' "$CACHE" | strip | sed -E 's/^[│┃ ]*└ ([▾▸] )?//; s/ [●•].*$//; s/…$//' | tr '\n' '|')
  cc=$(tmux capture-pane -p -t "$pane" | tail -12 | grep -E '^[ ❯├└│]*[◯⏺] ' | grep -v ' main' | sed -E 's/^[ ❯├└│]*[◯⏺] +[^ ]+( \(\+[0-9]+\))? +//; s/  +[0-9hms ]+ · ↓.*$//' | tr '\n' '|')
  echo "        sidebar: $sb"; echo "        claude:  $cc"
  if [ -z "$want_view" ]; then echo "fold  $t -> view [$gv] highlight [$gl] row: $(awk -F'\t' -v r="$row" '$1 == r { print $2 }' "$CACHE" | strip | cut -c1-40)"; continue; fi
  if [ "$gv" = "$want_view" ] && [ "$gl" = "$want_lit" ]; then pass=$((pass + 1)); echo "ok    $t ($want_view)"
  else fail=$((fail + 1)); echo "FAIL  $t: view [$gv] want [$want_view] | highlight [$gl] want [$want_lit]"; fi
done
echo "passed $pass, failed $fail"
