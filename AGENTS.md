# AGENTS.md

## Project scope

AgentCockpit is a mobile cockpit for coding agents.

- iOS app: `AgentCockpit/`
- Legacy gateway: `gateway/`
- Protocol modes in app: `gateway_legacy`, `acp`, `codex`

## Development rules

- Use FlowDeck for all iOS build/run/test/simulator work.
- Keep iOS deployment compatibility at iOS 17+.
- Keep protocol handling layered:
  - websocket transport (`ACGatewayConnection`)
  - request/response service (`ACSessionTransport`)
  - event mapping (`AppModel` + parser/adapters)
- Preserve legacy gateway mode while adding ACP/Codex behavior.

## High-value paths

- `AgentCockpit/Core/Protocol/ACProtocol.swift`
- `AgentCockpit/Core/Connection/ACGatewayConnection.swift`
- `AgentCockpit/Core/Connection/ACSessionTransport.swift`
- `AgentCockpit/Core/AppModel.swift`
- `AgentCockpit/EventParsing/*`
- `gateway/src/*`

## Validation

- iOS build:
```bash
flowdeck build -w AgentCockpit.xcodeproj -s AgentCockpit -S "iPhone 17"
```
- Gateway typecheck/build:
```bash
cd gateway && npm run build
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
