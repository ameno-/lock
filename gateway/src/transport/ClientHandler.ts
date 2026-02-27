import type WebSocket from "ws";
import { validateToken } from "../auth";
import type { ClientMessage, ServerMessage, EventFrame } from "../protocol";
import type { SessionRegistry } from "../sessions/SessionRegistry";
import type { EventRouter } from "../events/EventRouter";
import { sendToSession } from "../sessions/TmuxBridge";

export class ClientHandler {
  private authenticated = false;
  private unsubscribes: Array<() => void> = [];
  private pingTimer: ReturnType<typeof setInterval> | null = null;
  private readonly id = Math.random().toString(36).slice(2, 8);

  constructor(
    private readonly ws: WebSocket,
    private readonly registry: SessionRegistry,
    private readonly router: EventRouter
  ) {
    console.log(`[client:${this.id}] connected`);
    ws.on("message", (raw) => this.onMessage(raw.toString()));
    ws.on("close", () => this.onClose());
    ws.on("error", (err) => console.error(`[client:${this.id}] error:`, err.message));

    // Auth timeout
    const t = setTimeout(() => {
      if (!this.authenticated) { this.send({ type: "auth_err", message: "Auth timeout" }); ws.close(); }
    }, 30_000);
    ws.once("close", () => clearTimeout(t));
  }

  private send(msg: ServerMessage): void {
    if (this.ws.readyState === 1) this.ws.send(JSON.stringify(msg));
  }

  private onMessage(raw: string): void {
    let msg: ClientMessage;
    try { msg = JSON.parse(raw) as ClientMessage; }
    catch { return; }

    if (!this.authenticated) {
      if (msg.type !== "auth") return;
      if (validateToken(msg.token)) {
        this.authenticated = true;
        this.send({ type: "auth_ok" });
        console.log(`[client:${this.id}] authenticated`);
        this.pingTimer = setInterval(() => this.send({ type: "ping" }), 25_000);
      } else {
        this.send({ type: "auth_err", message: "Invalid token" });
        this.ws.close();
      }
      return;
    }

    if (msg.type === "pong") return;

    if (msg.type === "req") {
      const { id, method, params } = msg;
      const p = (params ?? {}) as Record<string, string>;
      this.dispatch(id, method, p).catch((err: unknown) => {
        this.send({ type: "res", id, error: { code: 500, message: String(err) } });
      });
    }
  }

  private async dispatch(id: string, method: string, p: Record<string, string>): Promise<void> {
    switch (method) {
      case "sessions.list":
        this.send({ type: "res", id, result: this.registry.list() });
        break;

      case "session.subscribe": {
        const key = p.sessionKey;
        const unsub = this.router.subscribe(key, (frame: EventFrame) => this.send(frame));
        this.unsubscribes.push(unsub);
        this.send({ type: "res", id, result: { ok: true, sessionKey: key } });
        break;
      }

      case "session.send": {
        const session = this.registry.get(p.sessionKey);
        if (!session) { this.send({ type: "res", id, error: { code: 404, message: "Session not found" } }); return; }
        await sendToSession(p.sessionKey, p.text);
        this.send({ type: "res", id, result: { ok: true } });
        break;
      }

      case "session.promote": {
        const ok = this.registry.promote(p.sessionKey);
        this.send({ type: "res", id, result: { ok } });
        break;
      }

      default:
        this.send({ type: "res", id, error: { code: 404, message: `Unknown method: ${method}` } });
    }
  }

  private onClose(): void {
    console.log(`[client:${this.id}] disconnected`);
    if (this.pingTimer) clearInterval(this.pingTimer);
    for (const u of this.unsubscribes) u();
  }
}
