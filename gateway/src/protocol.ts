// AgentCockpit Gateway Protocol
// Message types for the WebSocket protocol between iOS client and gateway.
// NOT compatible with Clawdbot — this is a standalone protocol.

export type StreamType = "tool" | "assistant" | "git" | "subagent" | "skill" | "system";

// ── Client → Server ──────────────────────────────────────────────────────────

export interface AuthRequest {
  type: "auth";
  token: string;
}

export interface PongMessage {
  type: "pong";
}

export interface ClientRequest {
  type: "req";
  id: string;
  method: string;
  params?: Record<string, unknown>;
}

export type ClientMessage = AuthRequest | PongMessage | ClientRequest;

// ── Server → Client ──────────────────────────────────────────────────────────

export interface AuthOkResponse { type: "auth_ok"; }

export interface AuthErrResponse { type: "auth_err"; message: string; }

export interface ServerResponse {
  type: "res";
  id: string;
  result?: unknown;
  error?: string | { code: number; message: string };
}

export interface EventFrame {
  type: "event";
  sessionKey: string;
  seq: number;
  stream: StreamType;
  data: Record<string, unknown>;
  ts: number;
}

export interface PingMessage { type: "ping"; }

export type ServerMessage =
  | AuthOkResponse
  | AuthErrResponse
  | ServerResponse
  | EventFrame
  | PingMessage;

// ── Session types ─────────────────────────────────────────────────────────────

/** Session entry as sent to iOS clients via sessions.list */
export interface SessionEntry {
  key: string;
  name: string;
  window: string;
  pane: string;
  running: boolean;
  promoted: boolean;
  createdAt: number;
}

// ── Hook payload (Claude Code → Gateway) ─────────────────────────────────────

export interface HookPayload {
  hook_event_name: string;
  session_id?: string;
  cwd?: string;
  tool_name?: string;
  tool_input?: Record<string, unknown>;
  tool_response?: Record<string, unknown>;
  message?: Record<string, unknown>;
  [key: string]: unknown;
}
