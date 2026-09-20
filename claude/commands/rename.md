---
description: Rename this tmux tab (pi's /rename, for Claude Code)
allowed-tools: Bash(tmux rename-window:*)
---

Rename the tmux tab this session is running in, then stop.

- If `$ARGUMENTS` is non-empty, that is the name: `tmux rename-window -- "$ARGUMENTS"`.
- If it is empty, invent one from what this conversation is actually about —
  two or three lowercase words, hyphenated, no trailing punctuation, under 24
  characters (e.g. `lidia-e2e`, `po-confirm-rebuild`) — and rename to that.

Do not read files, search, or explain. One `tmux rename-window` call, then a
single line: the new name.

Renaming this way turns `automatic-rename` off for the window, so the name
sticks instead of following Claude Code's per-task terminal title.
