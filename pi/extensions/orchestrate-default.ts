/**
 * Make pi orchestrate the way Claude Code does, without being asked.
 *
 * In Claude Code a SessionStart hook states the delegation runtime as a
 * standing rule, so every session starts already knowing that delegated work
 * runs as pi workers through ~/.claude/skills/orchestrate-pi-subagents. pi had
 * no equivalent: the skill was only loaded when it was named, and even then the
 * model often reached for its own `Agent` tool instead — a different fleet, in
 * a different place, invisible to the tmux sidebar.
 *
 * So, for an interactive pi session that is not itself a worker:
 *   1. the skill is appended to the system prompt, every session, in full;
 *   2. the competing spawn routes (@tintinweb/pi-subagents' Agent/workflow
 *      tools) are blocked, except read-only Explore/Plan lookups — the same
 *      fence the Claude Code hook applies.
 *
 * Off with PI_NO_ORCHESTRATOR_DEFAULT=1.
 */

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SKILL_DIR = join(homedir(), ".claude", "skills", "orchestrate-pi-subagents");
const SKILL_MD = join(SKILL_DIR, "SKILL.md");

// tools from @tintinweb/pi-subagents that start work somewhere this setup
// cannot see; `Agent` is allowed through for read-only lookups only
const SPAWN_TOOLS = new Set(["Agent", "SubagentWorkflow", "get_subagent_result", "steer_subagent"]);
const READ_ONLY_AGENTS = new Set(["explore", "plan"]);

const STANDING_RULE = `# Delegation runtime (standing rule)

Any work you hand to a subagent runs as a pi worker on DeepSeek V4.1 Flash,
through \`${SKILL_DIR}/scripts/agent-session.sh\`, following the skill below.
This is not optional and does not need to be asked for: it is how this machine
runs delegated work, so every worker shows up in the tmux sidebar next to the
session that started it.

Do not use the \`Agent\` / \`SubagentWorkflow\` tools to do work — they are
blocked for anything but a read-only \`Explore\`/\`Plan\` lookup, because what
they start is invisible here. Do small, latency-sensitive work yourself.

The skill's own judgment — what to absorb, what to escalate, how to brief and
review — applies to this session as written.`;

export default function (pi: ExtensionAPI) {
	if (process.env.PI_NO_ORCHESTRATOR_DEFAULT === "1") return;
	if (process.env.PI_SUBAGENT_SESSION) return; // this session IS a worker

	let block = "";
	try {
		block = `${STANDING_RULE}\n\n<skill name="orchestrate-pi-subagents" path="${SKILL_MD}">\n${readFileSync(SKILL_MD, "utf8").trim()}\n</skill>`;
	} catch {
		return; // no skill on this machine: leave pi exactly as it was
	}

	pi.on("before_agent_start", async (event, ctx) => {
		// only a session you sit in front of orchestrates; a one-shot `pi -p`
		// is somebody's helper and should not carry a manager's playbook
		if (ctx.mode !== "tui") return;
		return { systemPrompt: `${event.systemPrompt}\n\n${block}` };
	});

	pi.on("tool_call", async (event) => {
		if (!SPAWN_TOOLS.has(event.toolName)) return;
		const type = String((event.input as { subagent_type?: unknown })?.subagent_type ?? "").toLowerCase();
		if (event.toolName === "Agent" && READ_ONLY_AGENTS.has(type)) return;
		return {
			block: true,
			reason:
				`${event.toolName} is disabled here: delegated work runs as pi workers through ` +
				`${SKILL_DIR}/scripts/agent-session.sh (acquire / dispatch / wait / read), so it stays ` +
				`visible in the tmux sidebar. Follow the orchestrate-pi-subagents skill. ` +
				`Read-only Agent(subagent_type: "Explore"|"Plan") lookups are still allowed.`,
		};
	});
}
