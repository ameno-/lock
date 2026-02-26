import type { Router } from "express";
import { Router as makeRouter } from "express";
import type { HookPayload, StreamType, EventFrame } from "../protocol";
import type { SessionRegistry } from "../sessions/SessionRegistry";
import type { EventRouter } from "./EventRouter";

function hookToStream(eventName: string): StreamType {
  switch (eventName) {
    case "PostToolUse":
    case "PreToolUse":
      return "tool";
    case "UserPromptSubmit":
      return "assistant";
    case "SubagentStop":
      return "subagent";
    default:
      return "system";
  }
}

function deriveSessionKey(payload: HookPayload): string {
  if (payload.session_id) return payload.session_id.slice(0, 12);
  if (payload.cwd) {
    const parts = (payload.cwd as string).split("/");
    return parts[parts.length - 1] || "default";
  }
  return "default";
}

function buildData(eventName: string, payload: HookPayload): Record<string, unknown> {
  const base: Record<string, unknown> = {
    hookEvent: eventName,
    cwd: payload.cwd,
    sessionId: payload.session_id,
  };
  switch (eventName) {
    case "PostToolUse":
      return { ...base, phase: "result", toolName: payload.tool_name, toolInput: payload.tool_input, toolResponse: payload.tool_response };
    case "PreToolUse":
      return { ...base, phase: "start", toolName: payload.tool_name, toolInput: payload.tool_input };
    case "UserPromptSubmit":
      return { ...base, message: payload.message };
    default:
      return base;
  }
}

export function createHookReceiver(router: EventRouter, registry: SessionRegistry): Router {
  const r = makeRouter();

  r.post("/hook", (req, res) => {
    try {
      const payload = req.body as HookPayload;
      const eventName = payload.hook_event_name ?? "Unknown";
      const sessionKey = deriveSessionKey(payload);
      const stream = hookToStream(eventName);

      registry.touch(sessionKey, payload.session_id ?? sessionKey);
      const seq = registry.nextSeq(sessionKey);

      const frame: EventFrame = {
        type: "event",
        sessionKey,
        seq,
        stream,
        data: buildData(eventName, payload),
        ts: Date.now(),
      };

      router.publish(frame);
      res.json({ ok: true, sessionKey, seq });
    } catch (err) {
      console.error("[hook] Error:", err);
      res.status(500).json({ ok: false, error: String(err) });
    }
  });

  r.get("/health", (_req, res) => {
    res.json({ ok: true, ts: Date.now() });
  });

  return r;
}
