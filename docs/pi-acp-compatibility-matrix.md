# pi-acp Compatibility Matrix

Last updated: 2026-02-27
Source baseline: `ameno-/pi-acp` commit `973ac86`

## Method-level contract

| Surface | pi-acp behavior | AgentCockpit behavior | Status |
|---|---|---|---|
| `initialize` | Returns ACP capabilities and `authMethods`; supports session list/resume/fork capability metadata. | Sends ACP initialize + initialized and tolerates capability variants. | ✅ |
| `session/new` | Requires absolute `cwd`; emits startup-info + `available_commands_update` notifications after response. | Sends optional `cwd`; surfaces explicit absolute-cwd remediation on `-32602`. | ✅ |
| `session/prompt` | Streams `agent_message_chunk`, `agent_thought_chunk`, `tool_call`, `tool_call_update`, and `session_info_update`. | Maps these updates to reasoning/tool/file/raw cards and digest metadata. | ✅ |
| `session/cancel` | Cancels active pi session request pipeline. | Uses protocol-native `session/cancel`. | ✅ |
| `session/list` / `session/resume/list` | Returns project-scoped sessions with `sessionId`, `cwd`, optional `title`, `updatedAt`, pagination cursor. | Parses id/title/cwd/timestamp variants and sorts by most recent activity. | ✅ |
| `session/load` | Requires absolute `cwd`; replays history as `user_message_chunk`, `agent_message_chunk`, tool replay updates, then commands update. | Loads/resumes on session entry and now hydrates ACP history into canvas events. | ✅ |
| `session/resume` / `unstable_resumeSession` | Resume path aliases load semantics. | Fallback chain `session/load` → `session/resume` used consistently. | ✅ |

## Notification-level contract

| `session/update` kind | pi-acp payload shape | AgentCockpit mapping |
|---|---|---|
| `user_message_chunk` | `content.text` | `RawOutputEvent` prefixed `You:` (history + live paths). |
| `agent_message_chunk` | `content.text` | `ReasoningEvent(isThinking: false)`. |
| `agent_thought_chunk` | `content.text` | `ReasoningEvent(isThinking: true)`. |
| `tool_call` | `toolCallId`, `title`, `kind`, optional `rawInput` | `ToolUseEvent(phase: .start)`. |
| `tool_call_update` | `toolCallId`, `status`, optional nested text output | `ToolUseEvent(phase: .result)` with status mapping. |
| `session_info_update` | status/metadata updates | Ignored for card noise; digest metadata path remains active. |
| `available_commands_update` | command list array | Ignored for transcript cards; safe no-op. |
| `current_mode_update` | mode id update | Safe no-op currently; reserved for mode UI follow-up. |

## Compatibility notes

- `cwd` must be absolute for `session/new` and `session/load` on pi-acp. AgentCockpit keeps this as a first-class user error with exact remediation text.
- pi-acp load path often replays history through notifications instead of returning bulk history in response. AgentCockpit supports both replay and response-history parsing.
- pi-acp emits mixed timestamp formats (`ISO-8601`, unix seconds, millis). Session list parsing normalizes all three.
- Slash-command and startup-info updates are preserved as regular assistant events; no special-case hard dependency exists in cockpit UI.

## Open deltas

1. `current_mode_update` should eventually drive explicit mode controls in Work view.
2. `available_commands_update` can be surfaced in composer UX (command suggestions).
3. End-to-end scripted harness against a running websocket pi-acp instance is still recommended for CI hardening.
