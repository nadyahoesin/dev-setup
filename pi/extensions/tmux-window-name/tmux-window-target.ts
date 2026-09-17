export type TmuxExecResult = {
  code: number;
  stdout?: string;
};

export type TmuxExec = (command: string, args: string[]) => Promise<TmuxExecResult>;

function normalizeTarget(value: string | undefined): string | undefined {
  const target = value?.trim();
  return target || undefined;
}

export function buildRenameWindowArgs(name: string, target?: string): string[] {
  return target ? ["rename-window", "-t", target, name] : ["rename-window", name];
}

export async function resolveTmuxWindowTarget(
  exec: TmuxExec,
  env: NodeJS.ProcessEnv = process.env,
): Promise<string | undefined> {
  if (!env.TMUX) return undefined;

  const pane = normalizeTarget(env.TMUX_PANE);
  if (!pane) return undefined;

  try {
    const result = await exec("tmux", ["display-message", "-p", "-t", pane, "#{window_id}"]);
    if (result.code !== 0) return undefined;
    return normalizeTarget(result.stdout);
  } catch {
    return undefined;
  }
}

export type TmuxWindowState = {
  name: string;
  /** tmux's automatic-rename for this window; it turns itself off on a manual rename-window */
  automatic: boolean;
};

export async function readTmuxWindowState(
  exec: TmuxExec,
  target?: string,
  env: NodeJS.ProcessEnv = process.env,
): Promise<TmuxWindowState | undefined> {
  if (!env.TMUX) return undefined;

  const where = normalizeTarget(target) ?? normalizeTarget(env.TMUX_PANE);
  if (!where) return undefined;

  try {
    const result = await exec("tmux", [
      "display-message",
      "-p",
      "-t",
      where,
      "#{window_name}\t#{automatic-rename}",
    ]);
    if (result.code !== 0) return undefined;

    const [name, automatic] = (result.stdout ?? "").trim().split("\t");
    if (!name) return undefined;
    return { name, automatic: automatic !== "0" };
  } catch {
    return undefined;
  }
}
