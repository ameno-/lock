# AgentCockpit

AgentCockpit is an iPhone/iPad cockpit for coding agents.

As of February 26, 2026, this repo supports three endpoint modes from the iOS app:

- `AgentCockpit Gateway` (legacy custom protocol)
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
- `gateway/`: TypeScript gateway that ingests hook events and exposes WS to the app

### iOS connection stack

- `ACSettingsStore`: endpoint mode + URL config (`ws`/`wss`, host, port, path)
- `ACGatewayConnection`: websocket lifecycle + reconnect
- `ACSessionTransport`: request/response methods for legacy, ACP, Codex
- `AppModel`: routes legacy events and JSON-RPC notifications into UI event store

### Gateway stack

- `/hook` receiver for Claude-style hook payloads
- in-memory session registry + event router
- websocket client handler for legacy custom protocol

## Quick start

### Legacy gateway mode

1. Start gateway:
```bash
docker compose up --build
```
2. Launch iOS app and set:
- Protocol: `AgentCockpit Gateway`
- Scheme: `ws`
- Host/Port: gateway endpoint
- Token: value matching `AGENTCOCKPIT_TOKEN`

### Direct ACP mode

1. Run an ACP server exposed via `ws://` or `wss://`
2. In iOS settings set:
- Protocol: `ACP`
- Scheme/Host/Port/Path: ACP endpoint
- Optional Working Dir

### Direct Codex app-server mode

1. Run codex app-server (websocket transport)
2. In iOS settings set:
- Protocol: `Codex App Server`
- Scheme/Host/Port/Path: codex endpoint
- Optional Working Dir

## Capability manifest: AgentCockpit vs Agmente

| Capability | AgentCockpit (this repo) | Agmente |
|---|---|---|
| Multi-protocol endpoint support | Legacy + ACP + Codex mode selector in app settings | ACP + Codex with dynamic runtime switching |
| Transport | WebSocket (`ws`/`wss`) | WebSocket (`ws`/`wss`) |
| JSON-RPC support | Minimal request/response/notification/request parsing | Full typed JSON-RPC service layers |
| ACP lifecycle | `initialize` + `initialized`, `session/new`, `session/list`, `session/prompt` (minimal) | Broad ACP method/event support including permission, fs, terminal |
| Codex lifecycle | `initialize` + `initialized`, `thread/start`, `thread/list`, `turn/start` (minimal) | Broad Codex surface (`thread/*`, `turn/*`, `item/*`, config, model, skills, account, approvals) |
| Server-initiated requests | Auto-response for approval/user-input request methods (minimal fallback) | Structured handling of approval and user-input flows |
| Event rendering | Unified card canvas with tool/reasoning/git/file/subagent/raw cards | Rich transcript model with protocol-specific mapping and diffing |
| Session/thread creation | Create from AIs tab (`+`) in ACP/Codex modes | Full create/resume/list/load flows with persistence |
| Persistence | In-memory event/session state | Persistent server/session/message strategies with protocol fallbacks |
| Remote hardening | Token auth in legacy mode; endpoint configurable | Bearer + optional Cloudflare Access headers |

## Blueprint: combine AgentCockpit + Agmente strengths

Use ACP as the alignment contract and preserve a small mobile UX footprint:

1. Keep one mobile UI surface.
2. Add protocol runtime adapters behind a shared JSON-RPC core.
3. Normalize ACP/Codex updates into a shared render model.
4. Preserve legacy gateway mode for hook-stream deployments.
5. Expand from minimal method coverage to full ACP/Codex parity incrementally.

## Minimal MVP scope (phone/iPad first)

Implemented in this iteration:

- iOS17-compatible build baseline fixed
- endpoint protocol mode setting (`Gateway`/`ACP`/`Codex`)
- JSON-RPC transport plumbing in app
- basic ACP and Codex request flows for session/thread creation, list, prompt/turn
- minimal JSON-RPC event mapping into existing canvas cards
- fallback auto-replies for approval-type server requests

Recommended next increments:

1. Complete typed ACP event parser (`session/update` variants).
2. Add Codex thread hydration (`thread/read`/`thread/resume` + listener patterns).
3. Add explicit approval UI instead of auto-replies.
4. Add persisted local session/thread index for offline continuity.

## External references

- Agmente: https://github.com/rebornix/Agmente
- ACP protocol repo: https://github.com/agentclientprotocol/agent-client-protocol
- ACP docs: https://agentclientprotocol.com/
- Codex app server docs: https://developers.openai.com/codex/app-server/
- Codex app server source: https://github.com/openai/codex/tree/main/codex-rs/app-server
- Happy blueprint: https://github.com/slopus/happy/tree/main
