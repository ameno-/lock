import type { SessionEntry } from "../protocol";
import { listSessions } from "./TmuxBridge";

export class SessionRegistry {
  private sessions = new Map<string, SessionEntry>();
  private promotedKey: string | null = null;
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private seqCounters = new Map<string, number>();

  async start(): Promise<void> {
    await this.refresh();
    this.pollTimer = setInterval(() => void this.refresh(), 5_000);
    console.log("[registry] Polling tmux sessions every 5s");
  }

  stop(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }

  private async refresh(): Promise<void> {
    try {
      const live = await listSessions();
      const liveKeys = new Set(live.map((s) => s.key));
      // Add / update live sessions
      for (const s of live) {
        const existing = this.sessions.get(s.key);
        this.sessions.set(s.key, {
          ...s,
          promoted: s.key === this.promotedKey,
          createdAt: existing?.createdAt ?? s.createdAt,
        });
      }
      // Mark stale sessions (keep them; iOS can still read history)
      for (const [key, entry] of this.sessions) {
        if (!liveKeys.has(key)) {
          entry.running = false;
        }
      }
    } catch (err) {
      console.error("[registry] Refresh error:", err);
    }
  }

  list(): SessionEntry[] {
    return Array.from(this.sessions.values())
      .sort((a, b) => Number(b.running) - Number(a.running) || b.createdAt - a.createdAt);
  }

  get(key: string): SessionEntry | undefined {
    return this.sessions.get(key);
  }

  promote(key: string): boolean {
    if (!this.sessions.has(key)) return false;
    this.promotedKey = key;
    for (const [k, s] of this.sessions) {
      s.promoted = k === key;
    }
    return true;
  }

  touch(sessionKey: string, sessionName: string): void {
    if (!this.sessions.has(sessionKey)) {
      this.sessions.set(sessionKey, {
        key: sessionKey,
        name: sessionName,
        window: "0",
        pane: "0",
        running: true,
        promoted: sessionKey === this.promotedKey,
        createdAt: Date.now(),
      });
    }
  }

  nextSeq(sessionKey: string): number {
    const n = (this.seqCounters.get(sessionKey) ?? 0) + 1;
    this.seqCounters.set(sessionKey, n);
    return n;
  }
}
