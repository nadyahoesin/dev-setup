# dev-setup

A lightweight terminal workspace for running many AI coding agents
(Claude Code, Codex, pi) side by side on a Mac without eating all the RAM.

This is a fork of [afgventura/dev-setup](https://github.com/afgventura/dev-setup).
The fork adds the activity dots, the worker and subagent trees in the sidebar,
the file viewer and most of the pi configuration described below.

```
┌────────────────────────┬──────────────────────────────────────┐
│ haloai                 │                                      │
│ ┃ ● Fix CI          ✕  │   tmux session "main"                │
│   └ ● review diff      │   (your shells / agents, persistent) │
│   └ • run the sims     │                                      │
│   • Add sidebar     ✕  │                                      │
│ govisa                 │                                      │
│   ! Deploy relay    ✕  │                                      │
└────────────────────────┴──────────────────────────────────────┘
   Ghostty window — the only terminal process; ⌘Q it any time
```

**What you get**

- **Ghostty** as the window with **tmux** owning the sessions — close Ghostty,
  reopen it, every agent is still running.
- A **left sidebar** listing the tabs of the `main` session, clickable and
  **grouped by project folder**. Names follow the agent's own terminal title
  (Claude Code sets one per task, so tabs relabel themselves). The active tab
  has a highlighted background.
- An **activity dot** per tab: red `!` = needs you (permission prompt or
  question), yellow `●` = mid-turn, green `●` = a command running in a plain
  shell tab, grey `•` = an agent idle at its prompt, or new output you have not
  looked at. Claude Code tab names are white, pi tab names violet.
- **Subagents as a tree** under the tab that started them: Claude Code
  subagents (including subagents of subagents), pi orchestrator workers, and a
  worker's nested `pi -p` runs. Each row has its own running / idle dot, and a
  click opens it.
- A `✕` on every tab row, and `▾`/`▸` to fold a tab's children.
- A **file viewer**: ⌥-click or double-click a file path printed in a tab and it
  opens in a pane on the right (markdown rendered, code highlighted).
- **⌘ shortcuts** that feel like a normal Mac app — no tmux prefix to learn.
- **Native macOS notifications** when an agent finishes or needs input;
  clicking one jumps to that tab.
- Shift+Enter inserts a newline in Claude Code / Codex (through both tmux layers).
- Truecolor + extended keys wired through, so agents render as they do natively.

## Install

```sh
git clone https://github.com/nadyahoesin/dev-setup.git ~/Workspace/dev-setup
~/Workspace/dev-setup/install.sh          # or: install.sh terminal | install.sh pi
```

Then open Ghostty. First notification will ask to allow **Agent Notifier** — click Allow.

`install.sh` is idempotent; re-run it after `git pull`.

`install.sh terminal`:

- installs Ghostty, JetBrains Mono, tmux, fzf, jq and glow with Homebrew;
- symlinks `tmux/tmux.conf` to `~/.tmux.conf` and the scripts in `tmux/` into
  `~/.config/tmux/`;
- generates `~/.config/ghostty/config` (pointing at this repo; an existing one
  is backed up);
- builds the notifier app;
- merges `claude/hooks.json` into `~/.claude/settings.json` and links the
  search guard to `~/.config/claude/`;
- appends the Codex snippet to `~/.codex/config.toml` and merges
  `codex/hooks.json`;
- sets `package-import-method=hardlink` in `~/.npmrc` (a worktree's
  `node_modules` then costs 40 MB of disk, not 2.6 GB);
- appends `ssh/config.snippet` to `~/.ssh/config`.

`install.sh pi`:

- installs pi with npm if it is missing;
- merges `settings.json`, `mcp.json`, `models.json` and `subagents.json` into
  `~/.pi/agent/` with `jq` (the repo's value wins on a conflict, and arrays
  such as `packages` and `enabledModels` are replaced whole);
- symlinks the extensions and `agents/general-purpose.md`.

Not installed by the script: `uv` (the file viewer runs through `uv run`) and
`pandoc` (optional, lets the viewer open Word documents). Nothing in `bridge/`,
`relay/`, `ios/`, `infra/` or `scripts/` is installed either.

## Shortcuts

| Key | Action |
|---|---|
| ⌘T | new tab, in the current tab's folder |
| ⌘W | close the current pane (the tab, when it is the last pane) |
| ⌘1–9 | jump to tab |
| ⌘⇧[ / ⌘⇧] | previous / next tab (in sidebar order) |
| ⌘S | full-screen picker over every session and tab, workers included (Esc closes) |
| ⌘R | rename tab. The name then stays fixed, and the agent can no longer rename it |
| ⌘⇧R | hand the tab's name back to the agent |
| ⌘D / ⌘⇧D | split right / down |
| ⌘⌥ arrows | move between splits |
| ⌘⇧K | clear scrollback |
| ⌘⇧U | pick & open a URL from the current tab (opens it directly if there is only one) |
| ⌘⇧M | pick a markdown file (ones named in the tab first, then the repo's) and open it in the file viewer |
| ⌘/ | shortcut cheat sheet |
| ⌘↩ | fullscreen |
| ⌘+ / ⌘− | font size |
| Shift+Enter | newline in an agent prompt |
| ⌥Enter | pi: queue the message until the current turn ends (Enter while busy = steer it in mid-turn); ⌥↑ pulls a queued message back |
| ⇧⌘-click | open a link under the mouse (tmux owns plain clicks, so Ghostty needs ⇧) |

Mouse:

- **Sidebar**: click a tab row to switch to it, a child row to open that worker
  or subagent, `✕` to close the tab, `▾`/`▸` to fold. The wheel scrolls the list.
- **A tab**: wheel scrolls the history; drag selects and copies on release (also
  inside Codex and other apps that take the mouse); double-click copies a word,
  triple-click a line; drag split borders to resize.
- **File paths**: ⌥-click or double-click a path to an existing file to open it
  in the file viewer.

File viewer keys: `←`/`→` or `[`/`]` switch tab, `w` closes the tab, `r`
reloads, `g`/`G` top / bottom, `q` quits.

## How it works

Two tmux servers. `main` (default socket) holds your real tabs. `ui`
(`-L ui`, config `tmux/ui.conf`) is throwaway chrome: a 51-column pane running
`sidebar.sh` (fzf as a pure display) next to a pane that attaches `main`, and
re-attaches if it ever drops. `ui` has no prefix, so every `C-b …` sequence
Ghostty's ⌘ keybinds emit passes straight through to `main`. When the last
Ghostty client detaches, `ui` kills itself; `main` lives on.

### The sidebar

`sidebar-list.sh` produces every row (target + display) and is the single
source of truth for what a row is and what a click on it does.
`sidebar-view.sh` cuts that list down to the rows that fit, at the current
scroll position, and draws the scrollbar; `sidebar-scrolld.py` is a small
daemon that does the same cut while you scroll, so the wheel stays smooth.

Updates are event-driven: hooks in `tmux.conf` and the agent hooks below call
`sidebar-refresh.sh`, which POSTs a `reload-sync` to fzf over a unix socket.
Hooks fire in bursts (every agent's title spinner), so the refresh is coalesced
(lock + dirty flag, throttled during a burst), skipped when the rows did not
change, and sends the cursor position in the same request as the reload. Every
hook is wrapped in `>/dev/null 2>&1 || true` — tmux would otherwise pop a
failing hook's output over the active pane. `sidebar-poll.sh` also refreshes
every 3 s, for the things no event announces: a subagent going quiet, a
background command ending.

Clicks are handled by tmux (`MouseDown1Pane` → `sidebar-click.sh`), never by
fzf, so keyboard focus can't land in the sidebar. A window resize or focus-in
(switching Spaces does both) runs `sidebar-redraw.sh` — full client redraw +
fzf re-render — because fzf sometimes came back with a blank list after a
resize.

`sidebar-style.sh [spaced|dividers|cards|sections|next]` picks how tabs are
separated. The default is `cards`. No key is bound to it.

### Activity dots

The dot comes from pane options (`@agent_state`, `@agent_kind`, …) that the
agents set themselves.

- **Claude Code**: `tmux/agent-state.sh`, called from the hooks in
  `claude/hooks.json` (`SessionStart`, `UserPromptSubmit`, `PreToolUse`,
  `PostToolUse`, `Stop`, `Notification`, `PreCompact`, `PostCompact`,
  `SubagentStart`, `SubagentStop`). A turn opens on the prompt and closes on
  `Stop`; a question, plan approval or permission prompt shows as "needs you";
  a compaction counts as working; a tab stays yellow while background
  subagents or background shell commands it started are still running. No hook
  fires when you press Esc, so the sidebar also reads the pane: a tab that no
  longer shows "esc to interrupt" is idle.
- **pi**: `pi/extensions/tmux-agent-state.ts` sets the same options from pi's
  own events.
- **Plain shell tabs**: green while a command other than the shell is running.

`sidebar-resync.sh` (`-n` to only report) re-reads every Claude Code pane and
corrects a dot that has drifted. Run it by hand; nothing calls it.

### Subagent trees

**Claude Code subagents.** `SubagentStart` / `SubagentStop` keep one file per
subagent under `~/.orchestrate-subagents/cc/<pane>/`, and the sidebar lists
them under their tab, nested by parent. A subagent that started subagents of
its own gets a `▸`, folded by default. Running = yellow `●`, quiet for two
minutes = grey `•`; a finished one stays only while you are looking at it, and
one you stop by hand is dropped. Row names are read from Claude Code's own
agent list, so they follow it as it renames them.

Clicking a row opens the subagent in Claude Code's own view.
That view is drawn by the Claude process, so `cc-agent-open.pl` gets there the
only way there is: it presses ↓ / ↑ / Enter in the pane, finding the right row
in the list under the prompt by type, nesting and running time. Clicking the
tab row goes back to the main agent. If the subagent is no longer in Claude
Code's list, `cc-agent-view.sh` shows its transcript in a read-only session
instead. Failed opens are logged to `~/.orchestrate-subagents/cc-open.log`.

**Orchestrator workers.** tmux sessions named `pi-wt-*` or `codex-wt-*`
(started by an orchestrator skill, see [Skills](#skills)) are listed under the
tab that started them; ones with no parent tab go in a "workers" group at the
bottom. A pi worker is yellow `●` while running and `◌` while queued for a
slot; the tab row shows the counts. Finished workers fold away. A worker's
nested `pi -p` runs unfold from its `▸`, and a click tails that run's
transcript.

### Notifications

`agent-notify.sh` is the Claude Code `Stop`/`Notification` hook and Codex's
`notify` hook. It drops a JSON request into `~/.local/state/agent-notifier/queue`;
`Agent Notifier.app` (tiny Swift app, `agent-notifier/`) posts the banner and,
on click, runs `tmux select-window` + brings Ghostty forward. Suppressed when
Ghostty is frontmost and that tab is already active, and for agents running in
sessions other than `main` (orchestrator workers — their orchestrator sweeps
them; you'd have no tab to jump to).

### File viewer

`md-click.sh` and `md-click-parse.py` turn a click into a file path;
`md-sidebar.sh` opens it in one pane per tab, 45% wide on the right, where
further files become tabs. `mdview.py` is the viewer (Textual, run through
`uv`): it renders markdown, highlights other text files, converts Word
documents with pandoc when that is installed, refuses other binaries, and
reloads when the file changes. `md-view.sh` is the ⌘⇧M picker, with a glow
preview.

## Layout

```
install.sh                the installer
ghostty/config            font, theme, window settings, ⌘ keybinds (→ tmux prefix sequences)
tmux/tmux.conf            main server: bindings, mouse, title→tab-name rule, hooks
tmux/ui.conf              outer chrome: sidebar pane, mouse, focus rules
tmux/ghostty-ui.sh        Ghostty's `command`: builds the layout, attaches
tmux/sidebar.sh           the sidebar pane (fzf)
tmux/sidebar-list.sh      every row: grouping, dots, trees, styles
tmux/sidebar-view.sh      the rows that fit + scrollbar
tmux/sidebar-scrolld.py   wheel scrolling daemon
tmux/sidebar-refresh.sh   coalesced reload    sidebar-poll.sh   3 s refresh
tmux/sidebar-click.sh     click handler       sidebar-redraw.sh redraw after resize / focus
tmux/sidebar-nav.sh       ⌘⇧[ / ⌘⇧]           sidebar-pos.sh    cursor onto the active row
tmux/sidebar-style.sh     pick the tab style  sidebar-resync.sh correct drifted dots
tmux/agent-state.sh       Claude Code hooks → activity dot + subagent registry
tmux/agent-notify.sh      notification hook (Claude Code + Codex)
tmux/cc-agent-open.pl     open a Claude Code subagent in Claude Code's own view (presses the keys)
tmux/cc-agent-view.sh     fallback transcript viewer for a subagent no longer in Claude Code's list
tmux/md-*.sh, mdview.py   file viewer: click parsing, pane, picker, viewer; glow-sidebar.json = preview theme
tmux/open-url.sh          ⌘⇧U URL picker
tmux/keys-help.sh         ⌘/ cheat sheet
tmux/copy-release.sh      drag-release: include the cursor cell tmux would otherwise drop
tmux/selftest.sh          acceptance test (see Testing)
tmux/clicktest.py         injects real mouse bytes to test sidebar clicks
tmux/cc-click-test.sh     end-to-end test of subagent-row clicks
agent-notifier/           Swift source + build script for the notifier app
claude/hooks.json         hook entries merged into ~/.claude/settings.json
claude/guard-search.sh    search guard (Claude Code + Codex)
codex/config.snippet.toml notify hook + shared Chrome MCP over HTTP
codex/hooks.json          search guard hook
ssh/config.snippet        one reused SSH connection to github.com
pi/                       pi coding agent: settings, models, MCP servers, subagent type, extensions
infra/remote-pi-relay/    Terraform: a Remote Pi relay on Cloud Run
bridge/ relay/ protocol/ ios/   Remote Agent — a separate project, see README.remote-agent.md
scripts/worktree-gc.sh    delete node_modules in worktrees unused for N days
.agents/skills/           agent skills (.claude/skills is a symlink to this directory, for Claude Code)
.artifacts/               notes left by the orchestration run that built Remote Agent
```

## Tuning

- Sidebar width: `SIDEBAR_WIDTH` in `tmux/ghostty-ui.sh` and the two `-x 51` in
  `tmux/ui.conf` (the attach and resize hooks) must agree. `sidebar-list.sh`
  and `sidebar-view.sh` read the live pane width and only fall back to 51.
- Active-row colour: `hl` in `tmux/sidebar-list.sh` (background) and the bar
  colour next to it.
- MCP tokens for pi are read from env vars named in `pi/mcp.json`
  (`bearerTokenEnv`) — keep secrets in the Keychain and export them from your
  shell rc, e.g. `export X="$(security find-generic-password -a "$USER" -s "<item>" -w)"`.

## pi

`pi/settings.json` lists the packages pi installs on first run:
`cc-my-pi`, `pi-mcp-adapter`, `@tintinweb/pi-subagents`, `@lnilluv/pi-ralph-loop`,
`pi-context-view`, `@juicesharp/rpiv-ask-user-question`, `pi-goal-x` and
`remote-pi`. The default model is `opencode-go/deepseek-v4.1-flash`.

### Extensions

`loop.ts` adds `/loop [interval] <prompt>` like Claude Code's:
with an interval it fires on a fixed schedule; without one it is a self-paced
loop where the agent picks each delay by calling `schedule_wakeup` (30 s–24 h,
or `at: "00:00"` / ISO time for a fixed clock time). Also exposed as tools
`loop_start` / `loop_stop`, so the agent can start a loop itself instead of
asking you to.

`tasks.ts` adds Claude Code's background-task model: tools
`background_run` (detached command, agent is woken with the output when it
exits), `watch` (poll a command until its output matches a regex / exits 0,
then wake the agent), `task_output`, `task_stop`; `/tasks` and
`/watch [every 30s] [until <regex>] <cmd>` for humans. Logs live in
`~/.pi/agent/tasks/`.

`skills-inline.ts` lets a prompt reference any number of skills
anywhere in the text, Claude Code style (`per /repo-safety and /testing, …`);
pi's own `/skill:name` only works as the first word and takes one skill. The
SKILL.md bodies go into context as one collapsed `📚 loaded skills` message
and the prompt stays exactly as typed. Typing `/` anywhere in the line pops
the skill picker (Tab/Enter inserts the name). Project skills in `.pi/skills`,
`.agents/skills` and `.claude/skills` of the working directory and its parents
are found too.

`tmux-agent-state.ts` gives a pi tab its activity dot (see
[Activity dots](#activity-dots)) and marks the tab as pi so the sidebar can
colour its name. It does nothing outside tmux or inside a worker.

`tmux-window-name/` is a vendored copy of `pi-tmux-window-name`
(auto-names the tmux tab from the first prompt; `/rename` regenerates,
`/rename <name>` sets your own) with two fixes: it
sends the `x-opencode-session` header opencode-go requires, and keeps reasoning
minimal so thinking models return a parseable name.
It also ignores in-process pi-subagents child sessions (no UI bound, name
`<agent>#<id>`), which otherwise re-fired its handlers and renamed the tab
after a subagent every time the orchestrator spawned one.

`orchestrate-default.ts` makes an interactive pi session delegate to pi
workers in their own tmux sessions (so they show in the sidebar) instead of
in-process subagents: it adds a standing rule plus the skill at
`~/.claude/skills/orchestrate-pi-subagents/` to the system prompt, and blocks
the `Agent` / `SubagentWorkflow` tools for anything but a read-only `Explore`
or `Plan` lookup. That skill is not part of this repo; without it the
extension does nothing. `PI_NO_ORCHESTRATOR_DEFAULT=1` turns it off.

`no-mesh.ts` blocks remote-pi's agent-network tools (`agent_send`,
`agent_request`, `list_peers`) and drops incoming mesh messages: one session
broadcasting a status note landed in every other session as a
`[remote-pi:mesh-message]` that started a model turn there. remote-pi is used
for the phone only.

`wheel.ts` sets the fullscreen mouse-wheel step to 5 lines per
event — the same step as tmux copy-mode in other panes (pi hard-codes 1 and
repaints the whole screen per event — upstream #9052 / #9549 — which is why a
trackpad flick lagged); `/wheel N` tunes it, Alt still multiplies by 5.

`cc-my-pi-no-git-poll.ts` stops cc-my-pi's statusline from running
`git status --untracked-files=all` + `git diff --shortstat HEAD` every 3 s in
every idle session. On a big dirty monorepo those outlast the 3 s timeout and
restart forever — 7 idle sessions pushed load average to ~400. cc-my-pi hardcodes
the poll, so the extension re-patches the installed package each time pi starts
(it survives `pi update`); the footer still refreshes on input and after each
tool call. `PI_GIT_INFO_POLL=1` turns polling back on.

`guard-search.ts` is the [search guard](#search-guard) for pi.

### Models

`pi/models.json` caps deepseek-v4.1-flash and both muse-spark contributor
models at a 500k context window, so auto-compaction and the ctx meter both work
off 500k — cost isn't the constraint at $0.003/M cached input; long-context
quality and latency are.

`enabledModels` scopes the catalogue to exact `provider/model` entries.
Without it a bare model name like `gpt-5.6-luna` resolved to opencode-go's copy
and was billed there instead of to the ChatGPT subscription. Log in once with
`/login` → OpenAI Codex.

`opencode-go-2` is opencode-go again under a second API key (read from the
Keychain with `!security …` at request time), so two accounts can be billed
separately. Note the Responses-API models (muse-spark, gpt-5.6-luna) store
encrypted reasoning items that are bound to the key that issued them: changing
a provider's key under a running session yields `reasoning encrypted_content
was not issued to this caller`. pi only replays those items when provider *and*
model match, so the fix is to switch the session to the other provider id
(`/model opencode-go-2/<same model>`), which drops the stale items — never swap
the key in place.

`self-hosted/z-ai/glm-5.3-flash` is a self-hosted GLM 5.3 Flash behind a
private gateway; it only works on that network. Its key is also read from the
Keychain at request time, so it doesn't depend on shell env. pi reads
`models.json` only at startup (`/reload` doesn't touch the model catalogue), so
a session started before a provider existed has to be relaunched to see it.

The Keychain item names in `models.json` and the endpoints in `mcp.json` are
this setup's own; replace them with yours.

### Settings

`tuiMode: fullscreen` renders only the visible part of the transcript on its
own screen; the default inline mode re-prints the whole transcript through
tmux on every resume, which is what made resuming a long session slow and
flickery.

Two things worth setting by hand, which the installer does not do:
`PI_SKIP_VERSION_CHECK=1` in the shell rc skips the network version check at
startup (run `pi update` yourself now and then), and `claudeHeaderEnabled:
false` in `~/.pi/settings.json` turns off cc-my-pi's startup banner, which
instantiates every extension a second time — that left remote-pi bound to a
dead API and broke `/remote-pi pair`, and it costs startup time.

### Subagents

`pi/agents/general-purpose.md` is the one in-process subagent type:
pi-subagents' three built-ins (general-purpose / Explore / Plan) are switched
off (`pi/subagents.json` → `disableDefaultAgents`), and any `subagent_type` the
model makes up falls back to it (`fallbackSubagent`). It is a parent twin (all
tools, same system prompt and skills) pinned to `model:
openai-codex/gpt-5.6-luna`, `thinking: medium` — frontmatter is authoritative
in pi-subagents, so the orchestrating model cannot pick another model for a
subagent. A project-local `.pi/agents/<name>.md` still wins.

When `orchestrate-default.ts` is active (see above), only read-only lookups
reach this subagent type; everything else is delegated to pi workers.

### Remote control

`remote-pi` is the remote control (iOS app "Remote Pi"): `/remote-pi` in the
session you want to drive → `/remote-pi relay url <your relay>` → scan the QR
with the app. Peers are paired with Ed25519 keys. `infra/remote-pi-relay/` is
Terraform for running your own relay on Cloud Run; its `main.tf` names a GCP
project and state bucket you will need to change.

Not to be confused with **Remote Agent** (`bridge/`, `relay/`, `protocol/`,
`ios/`), a separate, home-grown remote control for pi that runs on your local
network with a shared token and has its own iOS app. It is documented in
[README.remote-agent.md](README.remote-agent.md) and is not installed by
`install.sh`.

## Skills

`.agents/skills/orchestrate-subagents/` is the orchestrator skill from the haloai repo:
one Codex/Claude session plans and fans work out to worker Codex sessions in
their own tmux sessions/worktrees (`scripts/codex-session.sh`), with briefs,
pushback rules, an adversarial-review stage and a closeout log. Workers run in
an isolated tmux server (`TMUX_TMPDIR` jail) so a worker's `tmux kill-session`
can never take down its siblings. Its examples and paths are written for that
repo. `.claude/skills` is a symlink to `.agents/skills`, so Claude Code sees
the same skill. Copy both into another repo to use it there.

This is the only skill vendored here. Everything else pi can load comes from
the packages in `pi/settings.json` or from your own skill directories.

## Search guard

Agents sometimes reach for recursive `grep` or `find`, which walk
`node_modules` and every worktree (millions of files here) while `rg`/`fd`
honour `.gitignore` and finish in under a second. `claude/guard-search.sh` is
a PreToolUse hook for the shell tool that rejects recursive grep and
directory-walking `find` (`-maxdepth 0-2` allowed) with a hint to use rg/fd.
The same protocol serves Claude Code (`claude/hooks.json`) and Codex
(`codex/hooks.json`, trusted once in the TUI); `pi/extensions/guard-search.ts`
does it for pi. Non-recursive `grep` (piped or `git grep`) and text inside
quotes or heredocs are untouched; a recursive flag is rejected wherever the
grep sits. It also rejects backgrounding an orchestrator's worker `wait` with
`&`: nothing notifies the session when such a wait ends, so the worker would
finish in silence.

## Testing after a change

```sh
~/Workspace/dev-setup/tmux/cc-click-test.sh <pane id> <window id> <agent id | tab | fold:<agent id>>…
```

`cc-click-test.sh` runs the real click handler on real subagent rows and checks
what the pane shows, which sidebar row is highlighted, and that the sidebar's
names match Claude Code's. It needs live subagents in the pane and is run from
the repo (it is not linked into `~/.config/tmux`).

`tmux/selftest.sh` (26 checks; quits and relaunches Ghostty, closes spare empty
shell tabs) and `tmux/clicktest.py` were written for the first sidebar layout —
a `TABS` header and one blank line between rows. Their sidebar checks have not
been updated for the current styles, so expect those to fail.
