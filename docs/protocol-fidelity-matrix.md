# Protocol Fidelity Matrix

Last updated: 2026-02-28

## Scope

This matrix tracks runtime fidelity for AgentCockpit across:

- ACP servers (including `pi-acp`)
- Codex app server
- Agmente parity baseline

## ACP Coverage

| Capability | AgentCockpit | Notes |
|---|---|---|
| `initialize` + `initialized` | ✅ | JSON-RPC init path implemented in `ACSessionTransport`. |
| `session/list` | ✅ | Includes fallback to `session/resume/list`. |
| `session/new` | ✅ | Supports optional absolute `cwd`; returns explicit guidance on `-32602`. |
| `session/load` / `session/resume` | ✅ | Load/resume fallback implemented before prompt/send. |
| `session/prompt` | ✅ | Prompt payload includes `sessionId` + `prompt` + `text` for compatibility. |
| `session/cancel` | ✅ | Protocol-native cancel implemented (`cancel(sessionKey:)`). |
| ACP session history hydration | ✅ | `loadSessionContext` now maps `history/messages` replay into canvas events. |
| `session/update` notification mapping | ✅ (core) | Tool/user/agent/genui paths mapped with safe fallback to raw output. |
| Request approval handling | ✅ | Handles `item/commandExecution/requestApproval` and `item/fileChange/requestApproval`. |
| Request user input handling | ✅ | Handles `item/tool/requestUserInput` and `tool/requestUserInput`. |

## Codex App Server Coverage

| Capability | AgentCockpit | Notes |
|---|---|---|
| `initialize` + notifications init | ✅ | Sends `initialized` and `notifications/initialized`. |
| `thread/list` | ✅ | Session list source in Codex mode. |
| `thread/start` | ✅ | Supports optional `cwd`. |
| `thread/resume` | ✅ | Ensured before send/cancel/hydration. |
| `thread/read` hydration | ✅ | `includeTurns: true`; robust parsing for camelCase + snake_case item types. |
| `turn/start` | ✅ | Prompt send path implemented. |
| `turn/interrupt` | ✅ | Abort now protocol-native (no Ctrl-C text fallback). |
| `thread/tokenUsage/updated` metadata | ✅ | Updates digest/token overlays. |
| `thread/status/changed` metadata | ✅ | Updates status overlays. |
| `turn/started` / `turn/completed` lifecycle | ✅ | Tracks active turn for interrupts and session activity. |
| `item/agentMessage/delta` mapping | ✅ | Stable ID strategy improved to reduce chunk fragmentation. |
| `item/started` / `item/completed` mapping | ✅ (core) | Reasoning/tool/file/user/genui mapping with suppression for noise-only item types. |
| Request approval / user input | ✅ | Codex request flows wired through transport response handlers. |
| GenUI action callback transport | ✅ | `submitGenUIAction` supports ACP + Codex method fallback chain. |

## UI/Store Fidelity

| Area | Status | Notes |
|---|---|---|
| Session list signal quality | ✅ | Title/preview/location/status/activity/token overlays implemented. |
| Context hydration on session entry | ✅ | Work view activation hydrates from `thread/read`. |
| Prompt send path | ✅ | Verified in simulator with live round-trip. |
| Duplicate local user echo | ✅ fixed | Removed optimistic local echo to avoid duplicate `You:` rows. |
| Duplicate assistant punctuation variants | ✅ fixed | Reasoning merge now normalizes and fingerprints text before append. |
| Codex history/update merge continuity | ✅ improved | Hydrated `thread/read` messages now share turn-scoped IDs with follow-up `item/*` updates. |
| Raw event noise | ✅ improved | Technical hooks (`item/*`, `thread/*`, `session/*`) hidden in raw cards. |
| GenUI feature safety | ✅ | Settings toggle disables GenUI rendering and degrades to raw output cards. |
| GenUI upsert semantics | ✅ | Snapshot/patch merge behavior now handled in `AgentEventStore`. |
| Transcript display-mode policy | ✅ | `WorkTranscriptView` supports `standard`, `debug`, and `textOnly` with GenUI scaffold suppression rules. |
| GenUI callback transport resilience | ✅ | Action submission now probes fallback methods on `-32601` and caches successful callback method per protocol. |
| Composer ergonomics | ✅ improved | Compact message composer replaces oversized modifier strip layout. |

## Agmente Parity Gaps (Intentional / Pending)

| Gap | Current State | Planned Bead |
|---|---|---|
| Full transcript diffing/merge semantics | Partial | `ac-e3p.9` fixture verification expansion |
| Extended model/skills/account surfaces | Not yet | follow-up codex parity bead |
| Persisted offline transcript index | Not yet | follow-up persistence bead |

## Verification Gates

Minimum gate before rollout:

1. FlowDeck build succeeds on simulator target.
2. Session list loads in both ACP and Codex mode.
3. Session entry hydrates existing context.
4. Send + receive round-trip succeeds.
5. Abort uses protocol-native cancel/interrupt.
6. No duplicate `You:` echo on send.
7. No repeated assistant line caused only by punctuation/token spacing variants.
8. GenUI disabled mode falls back safely to raw output.
9. ACP history load populates user/assistant/system replay cards.
10. GenUI action callbacks succeed when method advertisement is incomplete (fallback probe path).
11. Fixture tests pass for ACP history, Codex delta coalescing, and GenUI schema/mode handling.

## Automated Evidence

- `AgentCockpitTests` passing (`77` tests):
  - ACP history mapping
  - Codex history turn-scoped event ID mapping
  - Codex history + delta merge continuity
  - Codex delta ID coalescing
  - Codex item/completed turn-scoped coalescing
  - GenUI disabled fallback
  - GenUI schema gate
  - GenUI patch mode mapping
  - GenUI store patch merge + snapshot replacement
  - GenUI callback negotiation + fallback probe/caching
  - Transcript display mode mapping and scaffold suppression
