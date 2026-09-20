#!/usr/bin/env bash
# Reclaim node_modules from worktrees nobody is using.
#
# A worktree checkout is ~350 MB; its node_modules is ~2.6 GB. Open a few dozen
# over a month and the pool is hundreds of gigabytes of dependencies for
# branches that were merged weeks ago. Deleting node_modules is reversible —
# `pnpm install` brings it back — and touches nothing tracked, so this is safe
# to run unattended. Whole worktrees are never removed: that is a judgement
# call about unmerged work, and it stays yours.
#
#   worktree-gc.sh [--days N] [--dry-run] [--root DIR]...
#
# Defaults to 7 days and the two pools: Claude Code's and the pi fleet's.
# Skipped: anything a tmux pane is sitting in, and anything used recently.
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

DAYS=7 DRY=0
ROOTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="${2:?--days needs a number}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --root) ROOTS+=("${2:?--root needs a path}"); shift 2 ;;
    *) echo "usage: $0 [--days N] [--dry-run] [--root DIR]..." >&2; exit 2 ;;
  esac
done
[ ${#ROOTS[@]} -gt 0 ] || ROOTS=("$HOME/haloai/.claude/worktrees" "$HOME/haloai-wt")

# Every directory a pane is currently sitting in, on either tmux server. A
# worktree someone is working in is never touched, however old it looks.
live=$(
  { TMUX= /opt/homebrew/bin/tmux list-panes -a -F '#{pane_current_path}' 2>/dev/null
    TMUX= /opt/homebrew/bin/tmux -L ui list-panes -a -F '#{pane_current_path}' 2>/dev/null
  } | sort -u
)

now=$(date +%s)
cutoff=$(( DAYS * 86400 ))
freed=0 swept=0 kept=0

human() { awk -v k="$1" 'BEGIN { printf (k > 1048576 ? "%.1f GB" : "%.0f MB"), (k > 1048576 ? k/1048576 : k/1024) }'; }

for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue
  for wt in "$root"/*/; do
    wt=${wt%/}
    [ -d "$wt" ] || continue

    # in use: a pane's cwd is this worktree or below it
    if printf '%s\n' "$live" | grep -qx -- "$wt" || printf '%s\n' "$live" | grep -q "^$wt/"; then
      kept=$((kept + 1)); continue
    fi
    # touched recently — the branch is probably still in play
    age=$(( now - $(stat -f %m "$wt" 2>/dev/null || echo "$now") ))
    if [ "$age" -lt "$cutoff" ]; then kept=$((kept + 1)); continue; fi

    # a pnpm monorepo puts one under each package too
    mods=()
    for m in "$wt"/node_modules "$wt"/*/node_modules "$wt"/*/*/node_modules; do
      [ -d "$m" ] && mods+=("$m")
    done
    [ ${#mods[@]} -gt 0 ] || { kept=$((kept + 1)); continue; }

    kb=$(du -sk "${mods[@]}" 2>/dev/null | awk '{s += $1} END {print s + 0}')
    freed=$((freed + kb)); swept=$((swept + 1))
    printf '%s  %s  %s\n' "$([ "$DRY" = 1 ] && echo would-free || echo freeing)" \
      "$(human "$kb")" "${wt#$HOME/}"
    [ "$DRY" = 1 ] || rm -rf "${mods[@]}"
  done
done

printf '\n%s %s across %d worktree(s); %d left alone (in use or newer than %d days).\n' \
  "$([ "$DRY" = 1 ] && echo 'would reclaim' || echo reclaimed)" "$(human "$freed")" "$swept" "$kept" "$DAYS"
