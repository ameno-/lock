// TmuxBridge — wraps tmux CLI (gracefully no-ops in Docker where tmux may not be present)
import { exec as execCb } from "child_process";
import { promisify } from "util";
import type { SessionEntry } from "../protocol";

const exec = promisify(execCb);

function shellEscape(s: string): string {
  return "'" + s.replace(/'/g, "'\\''") + "'";
}

export async function listSessions(): Promise<SessionEntry[]> {
  try {
    const { stdout } = await exec(
      "tmux ls -F '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null"
    );
    const sessions: SessionEntry[] = [];
    for (const line of stdout.trim().split("\n")) {
      if (!line) continue;
      const m = line.match(/^(.+):(\d+)\.(\d+)$/);
      if (!m) continue;
      const [, name, window, pane] = m;
      sessions.push({ key: `${name}:${window}.${pane}`, name, window, pane, running: true, promoted: false, createdAt: Date.now() });
    }
    return sessions;
  } catch {
    return []; // tmux not running — normal in Docker
  }
}

export async function sendToSession(tmuxTarget: string, text: string): Promise<void> {
  await exec(`tmux send-keys -t ${shellEscape(tmuxTarget)} ${shellEscape(text)} Enter`);
}
