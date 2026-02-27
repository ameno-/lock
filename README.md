# AgentCockpit

AgentCockpit is an iPhone/iPad cockpit for coding agents.

As of February 26, 2026, this repo supports two endpoint modes from the iOS app:

- `ACP` (JSON-RPC over WebSocket)
- `Codex App Server` (JSON-RPC over WebSocket)

## Why this exists

This project is optimized for mobile access to active coding sessions:

- quick session visibility
- lightweight event stream UI
- prompt/abort controls
- portable setup for phone/iPad

## Architecture

- `AgentCockpit/`: SwiftUI iOS app

### iOS connection stack

- `ACSettingsStore`: endpoint mode + URL config (`ws`/`wss`, host, port, path)
- `ACGatewayConnection`: websocket lifecycle + reconnect + auth headers
- `ACSessionTransport`: request/response service for ACP/Codex, session hydration, server-request replies
- `AppModel`: JSON-RPC notification mapping into `CanvasEvent`
- `AgentEventStore`: per-session event state, digest metadata, token/status overlays

## Quick start

### Direct ACP mode

1. Run an ACP server exposed via `ws://` or `wss://`
2. In iOS settings set:
- Protocol: `ACP`
- Scheme/Host/Port/Path: ACP endpoint
- Working Dir: required for ACP servers that require absolute cwd on `session/new`/`session/load` (for example `pi-acp`)

### Direct Codex app-server mode

1. Run codex app-server (websocket transport)
2. In iOS settings set:
- Protocol: `Codex App Server`
- Scheme/Host/Port/Path: codex endpoint
- Optional Working Dir

## Capability manifest: AgentCockpit vs Agmente

| Capability | AgentCockpit (this repo) | Agmente |
|---|---|---|
| Multi-protocol endpoint support | ACP + Codex mode selector in app settings | ACP + Codex with dynamic runtime switching |
| Transport | WebSocket (`ws`/`wss`) | WebSocket (`ws`/`wss`) |
| JSON-RPC support | Request/response + notifications + server-initiated requests | Full typed JSON-RPC service layers |
| ACP lifecycle | `initialize`, `session/new`, `session/list`, `session/prompt`, `session/load/session/resume` fallback | Broad ACP method/event support including permission, fs, terminal |
| Codex lifecycle | `initialize`, `thread/start/list/read/resume`, `turn/start` | Broad Codex surface (`thread/*`, `turn/*`, `item/*`, config, model, skills, account, approvals) |
| Server-initiated requests | Interactive approval + user-input queues with explicit responses | Structured handling of approval and user-input flows |
| Event rendering | Agmente-style session-first UI + canvas cards (tool/reasoning/git/file/subagent/raw/genui) | Rich transcript model with protocol-specific mapping and diffing |
| Session summaries | Includes protocol label, status, token usage, activity, cwd/location | Rich thread/session metadata parsing and persistence |
| Remote hardening | Bearer + optional Cloudflare Access headers | Bearer + optional Cloudflare Access headers |

## Blueprint: combine AgentCockpit + Agmente strengths

Use ACP as the alignment contract and preserve a small mobile UX footprint:

1. Keep one mobile UI surface.
2. Add protocol runtime adapters behind a shared JSON-RPC core.
3. Normalize ACP/Codex updates into a shared render model.
4. Expand from current method coverage to full ACP/Codex parity incrementally.

## Minimal MVP scope (phone/iPad first)

Implemented in this iteration:

- iOS17-compatible build baseline fixed
- endpoint protocol mode setting (`ACP`/`Codex`)
- JSON-RPC transport plumbing in app
- ACP and Codex request flows for session/thread creation, list, hydration, prompt/turn
- session-first Agmente-style mobile navigation and cards
- explicit approval and request-user-input handling in Work view
- GenUI event routing + renderer card scaffold
- ACP session list parsing hardening (`id/title/cwd/timestamps` variants)
- auth header support (Bearer + Cloudflare Access)
- capability-negotiated GenUI callback method routing (ACP/Codex)
- persisted GenUI surfaces + pending action recovery on session reactivation

Recommended next increments:

1. Add persisted local session/thread index for reconnect/offline continuity.
2. Expand protocol fixtures beyond GenUI into full ACP/Codex tool and approval lifecycles.
3. Add server capability cache invalidation/refresh strategy for long-lived transports.
4. Expand GenUI contract validation for future schema versions.

## Agent-Generated GenUI (Current)

AgentCockpit now supports rendering GenUI directly from assistant responses when the message includes an embedded JSON block:

````text
```genui
{"id":"surface-inline-1","schemaVersion":"v0","mode":"snapshot","title":"Deploy Gate","text":"Build passed","action":{"actionId":"continue","label":"Continue"}}
```
````

Notes:

- The block language can be `genui` or `gen_ui` (also supports `<genui>...</genui>` tags).
- This is parsed on the client from codex `agent_message` items and rendered as `CanvasEvent.genUI`.
- GenUI action callbacks are sent only when the connected server advertises a supported callback method.

## Display modes and embedded GenUI behavior

- `genuiEnabled = true`: explicit GenUI updates and embedded assistant GenUI blocks render as GenUI cards.
- `genuiEnabled = false`: GenUI payloads are not rendered as cards and fall back to raw output events.
- Embedded GenUI extraction preserves the full original assistant text in `context.__sourceText` while keeping existing context keys from the embedded payload.

## GenUI diagnostics in app

In `Settings > Features`, AgentCockpit now shows lightweight GenUI diagnostics:

- negotiated callback method (`GenUI callback`) for the active protocol mode, or `not advertised`
- parser counters from runtime mapping:
  - `GenUI parsed`
  - `GenUI ignored`
  - `GenUI embedded`

When the session list is empty, `Open Settings` is available directly from the empty state so diagnostics remain reachable without an active session.

## External references

- Agmente: https://github.com/rebornix/Agmente
- ACP protocol repo: https://github.com/agentclientprotocol/agent-client-protocol
- ACP docs: https://agentclientprotocol.com/
- Codex app server docs: https://developers.openai.com/codex/app-server/
- Codex app server source: https://github.com/openai/codex/tree/main/codex-rs/app-server
- Happy blueprint: https://github.com/slopus/happy/tree/main
