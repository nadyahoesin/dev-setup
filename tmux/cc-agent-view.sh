#!/usr/bin/env bash
# Read-only view of one Claude Code subagent: follows its transcript and draws
# it the way Claude Code draws a subagent you open from the main agent — the
# prompt, then ⏺ for each message and tool call with its ⎿ result under it.
# Run inside the ccsub-<agent id> session that sidebar-click.sh makes when you
# click the subagent's row.
#   cc-agent-view.sh <transcript path without .jsonl>
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
base=$1
if [ -f "$base.meta.json" ]; then
  jq -r '"\u001b[1m\(.description // "subagent")\u001b[0m\n\u001b[2m\(.agentType // "agent") · \(.model // "")\u001b[0m\n"' "$base.meta.json"
fi
tail -n +1 -F "$base.jsonl" 2>/dev/null | jq --unbuffered -r '
  def dim: "\u001b[2m" + . + "\u001b[0m";
  def cut(n): if length > n then .[0:n] + "…" else . end;
  def hang: gsub("\n"; "\n  ");                       # continuation lines sit under the text, not the bullet
  def head(n): split("\n") as $l                      # first n lines, then how many were left out
    | ($l[0:n] | map(cut(220)) | join("\n     "))
      + (if ($l | length) > n then "\n     … +\(($l | length) - n) lines" else "" end);
  def arg:                                            # the one argument worth showing, per tool
    .input as $i
    | if   .name == "Bash" then $i.command
      elif .name == "Read" or .name == "Write" or .name == "Edit" or .name == "NotebookEdit" then $i.file_path
      elif .name == "Grep" or .name == "Glob" then $i.pattern
      elif .name == "Agent" or .name == "Task" then $i.description
      elif .name == "Skill" then $i.skill
      elif .name == "ToolSearch" or .name == "WebSearch" then $i.query
      elif .name == "WebFetch" then $i.url
      else ($i | tostring) end
    | (. // "" | tostring | gsub("\n"; " ") | cut(160));
  def result: if type == "string" then . elif type == "array" then (map(.text? // "") | join("\n")) else tostring end;
  .type as $who | (.message.content // empty) |
  if type == "string" then
    (if $who == "user" then "\u001b[1m❯\u001b[0m " + (cut(4000) | hang) + "\n" else "⏺ " + hang + "\n" end)
  else .[] |
    if   .type == "text"        then "⏺ " + (.text | hang) + "\n"
    elif .type == "thinking"    then ("✻ Thinking…" | dim) + "\n"
    elif .type == "tool_use"    then "\u001b[32m⏺\u001b[0m \u001b[1m" + .name + "\u001b[0m(" + arg + ")"
    elif .type == "tool_result" then ("  ⎿  " + (.content | result | if . == "" then "(no output)" else head(4) end) | dim) + "\n"
    else empty end
  end'
