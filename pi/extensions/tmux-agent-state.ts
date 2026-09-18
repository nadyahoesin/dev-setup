/**
 * Same sidebar indicator for pi as for Claude Code.
 *
 * Claude Code drives the tmux sidebar through hooks (claude/agent-state.sh),
 * which set the pane option `@agent_state` to working / waiting / idle. pi has
 * no hooks, so this extension does it from the extension events instead. The
 * sidebar then reads one option and cannot tell the two agents apart:
 *
 *   working   the agent is mid-turn            (yellow ●)
 *   waiting   it is blocked on you             (red !)
 *   idle      it is sitting at the prompt      (no dot)
 *
 * "idle" is set explicitly rather than unset: a pi pane's running command is
 * `node`, which the sidebar would otherwise read as "some command is running"
 * and light up green forever.
 */

import { spawn } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const TMUX = "/opt/homebrew/bin/tmux";
const REFRESH = `${process.env.HOME}/.config/tmux/sidebar-refresh.sh`;

type State = "working" | "waiting" | "idle";

export default function (pi: ExtensionAPI) {
	const pane = process.env.TMUX_PANE;
	// worker turns run headless in their own pane; the sidebar tracks those
	// through the orchestrator's busy pidfile, not through this option
	if (!pane || !process.env.TMUX || process.env.PI_SUBAGENT_SESSION) return;

	let current: State | "" = "";
	let running = false;

	// tmux is invoked with TMUX cleared so it talks to the default server
	// (the one holding this pane) rather than trying to nest.
	const run = (cmd: string, args: string[]) => {
		try {
			spawn(cmd, args, {
				stdio: "ignore",
				detached: true,
				env: { ...process.env, TMUX: "" },
			}).unref();
		} catch {}
	};

	const set = (state: State) => {
		if (state === current) return; // the sidebar redraw is not free
		current = state;
		run(TMUX, ["set", "-p", "-t", pane, "@agent_state", state]);
		run(REFRESH, []);
	};

	const clear = () => {
		current = "";
		run(TMUX, ["set", "-p", "-u", "-t", pane, "@agent_state"]);
		run(TMUX, ["set", "-p", "-u", "-t", pane, "@agent_kind"]);
		run(REFRESH, []);
	};

	// the sidebar tints a pi tab differently from a Claude Code one
	run(TMUX, ["set", "-p", "-t", pane, "@agent_kind", "pi"]);

	pi.on("session_start", async () => set("idle"));
	pi.on("agent_start", async () => {
		running = true;
		set("working");
	});
	pi.on("agent_settled", async () => {
		running = false;
		set("idle");
	});
	pi.on("agent_end", async () => set(running ? "working" : "idle"));
	// a blocking dialog (approval, a question, a picker) is "needs you"
	pi.on("ui_prompt_start", async () => set("waiting"));
	pi.on("ui_prompt_end", async () => set(running ? "working" : "idle"));
	pi.on("session_shutdown", async () => clear());
}
