#!/usr/bin/env bash
# Viewport of the sidebar: reads ALL rows (sidebar-list.sh output, cached in
# $ALL) and prints what fits the pane, starting at the scroll offset, with a
# scrollbar in the right-hand column when the list is taller than the pane.
#   sidebar-view.sh            print the visible rows (stdout)
# fzf is only a display (no mouse, no input), so scrolling lives here.
# Line 1 is always a blank "parking" row: fzf must put its cursor somewhere, and
# when the active tab is scrolled out of view the cursor sits there.
# The view jumps to the active tab only when the active tab changes, so wheel
# scrolling (sidebar-scrolld.py) isn't undone by the next refresh.
exec 2>/dev/null
T="${TMPDIR:-/tmp}/tmux-sidebar-$UID"
W=51 PH=40 off=0 last=""
read -r W PH < "$T.size"
read -r off < "$T.offset"
read -r last _ _ < "$T.offset.meta"
# one awk pass (bash 3.2 string handling made every wheel step ~100ms)
LC_ALL=C exec awk -v W="$W" -v PH="$PH" -v off="$off" -v last="$last" \
  -v OFFSET_FILE="$T.offset" -v META="$T.offset.meta" '
function vislen(s,   t) {           # display columns: drop ANSI, count UTF-8 lead bytes
  t = s; gsub(/\033\[[0-9;]*m/, "", t)
  return length(t) - gsub(/[\200-\277]/, "", t)
}
{ line[NR - 1] = $0 }
END {
  total = NR
  if (W !~ /^[0-9]+$/) W = 51
  if (PH !~ /^[0-9]+$/) PH = 40
  if (off !~ /^[0-9]+$/) off = 0
  off0 = off; view = PH - 1; CW = W - 2; ci = -1; key = ""
  for (i = 0; i < total; i++) if (line[i] ~ /\t\342\226\266$/) { ci = i; split(line[i], f, "\t"); key = f[1]; break }
  if (ci >= 0 && key != last) {        # active tab changed: bring it (and its card borders) into view
    if (ci - 1 < off) off = (ci > 0 ? ci - 1 : 0)
    if (ci + 1 >= off + view) off = ci + 2 - view
  }
  if (off > total - view) off = total - view
  if (off < 0) off = 0
  if (off != off0) print off > OFFSET_FILE
  print (key != "" ? key : last), total, view > META
  bar = total > view
  if (bar) {                            # thumb length ∝ visible share, position ∝ offset
    ts = int(view * view / total); if (ts < 1) ts = 1
    tp = int((view - ts) * off / (total - view))
  }
  BOR = "\033[38;2;42;74;80m"; THUMB = "\033[38;2;64;212;231m"; RST = "\033[0m"
  printf "\t \n"
  for (i = off; i < total && i - off < view; i++) {
    l = line[i]; cm = ""
    if (l ~ /\t\342\226\266$/) { cm = "\t\342\226\266"; sub(/\t\342\226\266$/, "", l) }
    if (!bar) { print l cm; continue }
    t = l; sub(/\t.*/, "", t); d = substr(l, length(t) + 2)
    pad = CW - 1 - vislen(d); if (pad < 0) pad = 0
    r = i - off
    g = (r >= tp && r < tp + ts) ? THUMB "\342\224\203" RST : BOR "\342\224\202" RST
    printf "%s\t%s%*s%s%s\n", t, d, pad, "", g, cm
  }
}' "$T.all"
