/**
 * Keep idle pi sessions idle: stop cc-my-pi's statusline git-info from running
 * `git status --untracked-files=all` + `git diff --shortstat HEAD` every 3s.
 * On a big dirty monorepo those take >3s, hit the timeout, and restart forever —
 * 7 idle sessions pinned the CPU (load avg ~400).
 *
 * cc-my-pi hardcodes the poll, so this re-applies a one-line patch to the
 * installed package whenever pi starts (survives `pi update`). The footer still
 * refreshes on input and after each tool call. PI_GIT_INFO_POLL=1 restores polling.
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const FILE = join(
	homedir(),
	".pi/agent/npm/node_modules/cc-my-pi/extensions/statusline/git-info/index.ts",
);
const ORIGINAL = "    pollingFiber = forkBackground(poll());";
const PATCHED =
	"    // Local patch (~/.pi/agent/extensions/cc-my-pi-no-git-poll.ts): no idle git polling.\n" +
	'    if (process.env.PI_GIT_INFO_POLL === "1") pollingFiber = forkBackground(poll());';

type Outcome = "already" | "patched" | "missing" | "changed";

function applyPatch(): Outcome {
	if (!existsSync(FILE)) return "missing";
	const source = readFileSync(FILE, "utf8");
	if (source.includes("PI_GIT_INFO_POLL")) return "already";
	if (!source.includes(ORIGINAL)) return "changed";
	writeFileSync(FILE, source.replace(ORIGINAL, PATCHED));
	return "patched";
}

// Top level, so it runs as early as possible during extension loading.
const outcome = applyPatch();

export default function (pi: ExtensionAPI) {
	if (outcome === "already" || outcome === "missing") return;
	pi.on("session_start", async (_event, ctx) => {
		ctx.ui.notify(
			outcome === "patched"
				? "cc-my-pi was updated: re-disabled idle git polling (takes effect next pi start)."
				: "cc-my-pi changed: idle git polling patch no longer matches — update ~/.pi/agent/extensions/cc-my-pi-no-git-poll.ts.",
			outcome === "patched" ? "info" : "warning",
		);
	});
}
