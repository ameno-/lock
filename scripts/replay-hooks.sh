#!/usr/bin/env bash
# replay-hooks.sh — POST test hook events to the gateway to simulate Claude Code
# Usage: ./scripts/replay-hooks.sh [gateway_url]
# Example: ./scripts/replay-hooks.sh http://localhost:19000

set -euo pipefail

GATEWAY="${1:-http://localhost:19000}"
SESSION_ID="test-session-$(date +%s)"

post() {
  local desc="$1"
  shift
  echo "→ $desc"
  curl -s -X POST "$GATEWAY/hook" \
    -H "Content-Type: application/json" \
    -d "$@" | jq .
  sleep 0.4
}

echo "=== AgentCockpit Hook Replay ==="
echo "Gateway: $GATEWAY"
echo "Session: $SESSION_ID"
echo ""

# 1. User prompt submitted
post "UserPromptSubmit" "{
  \"hook_event_name\": \"UserPromptSubmit\",
  \"session_id\": \"$SESSION_ID\",
  \"cwd\": \"/Users/ameno/dev/agentcockpit\",
  \"message\": {\"role\": \"user\", \"content\": \"Check git status and show any diffs\"}
}"

# 2. PreToolUse — Bash git status
post "PreToolUse: git status" "{
  \"hook_event_name\": \"PreToolUse\",
  \"session_id\": \"$SESSION_ID\",
  \"cwd\": \"/Users/ameno/dev/agentcockpit\",
  \"tool_name\": \"Bash\",
  \"tool_input\": {\"command\": \"git status --porcelain\", \"description\": \"Check working tree status\"}
}"

# 3. PostToolUse — Bash git status result
post "PostToolUse: git status result" "{
  \"hook_event_name\": \"PostToolUse\",
  \"session_id\": \"$SESSION_ID\",
  \"cwd\": \"/Users/ameno/dev/agentcockpit\",
  \"tool_name\": \"Bash\",
  \"tool_input\": {\"command\": \"git status --porcelain\"},
  \"tool_response\": {
    \"stdout\": \" M gateway/src/server.ts\n?? AgentCockpit/\",
    \"stderr\": \"\",
    \"interrupted\": false
  }
}"

# 4. PreToolUse — Read file
post "PreToolUse: Read file" "{
  \"hook_event_name\": \"PreToolUse\",
  \"session_id\": \"$SESSION_ID\",
  \"cwd\": \"/Users/ameno/dev/agentcockpit\",
  \"tool_name\": \"Read\",
  \"tool_input\": {\"file_path\": \"/Users/ameno/dev/agentcockpit/gateway/src/server.ts\"}
}"

# 5. PostToolUse — Read result
post "PostToolUse: Read result" "{
  \"hook_event_name\": \"PostToolUse\",
  \"session_id\": \"$SESSION_ID\",
  \"cwd\": \"/Users/ameno/dev/agentcockpit\",
  \"tool_name\": \"Read\",
  \"tool_input\": {\"file_path\": \"/Users/ameno/dev/agentcockpit/gateway/src/server.ts\"},
  \"tool_response\": {\"content\": \"import { WebSocketServer } from 'ws';\n...\", \"numLines\": 42}
}"

# 6. PreToolUse — Bash git diff
post "PreToolUse: git diff" "{
  \"hook_event_name\": \"PreToolUse\",
  \"session_id\": \"$SESSION_ID\",
  \"cwd\": \"/Users/ameno/dev/agentcockpit\",
  \"tool_name\": \"Bash\",
  \"tool_input\": {\"command\": \"git diff HEAD\"}
}"

# 7. PostToolUse — git diff result (actual diff output)
post "PostToolUse: git diff result" "{
  \"hook_event_name\": \"PostToolUse\",
  \"session_id\": \"$SESSION_ID\",
  \"cwd\": \"/Users/ameno/dev/agentcockpit\",
  \"tool_name\": \"Bash\",
  \"tool_input\": {\"command\": \"git diff HEAD\"},
  \"tool_response\": {
    \"stdout\": \"diff --git a/gateway/src/server.ts b/gateway/src/server.ts\nindex abc123..def456 100644\n--- a/gateway/src/server.ts\n+++ b/gateway/src/server.ts\n@@ -1,5 +1,7 @@\n import { WebSocketServer } from 'ws';\n+import express from 'express';\n+import { createServer } from 'http';\n import { SessionRegistry } from './sessions/SessionRegistry';\n-const PORT = 8080;\n+const PORT = parseInt(process.env.AGENTCOCKPIT_PORT ?? '19000', 10);\",
    \"stderr\": \"\",
    \"interrupted\": false
  }
}"

# 8. Subagent spawned
post "SubagentStop (done)" "{
  \"hook_event_name\": \"SubagentStop\",
  \"session_id\": \"subagent-explore-$(date +%s)\",
  \"cwd\": \"/Users/ameno/dev/agentcockpit\"
}"

# 9. Stop
post "Stop" "{
  \"hook_event_name\": \"Stop\",
  \"session_id\": \"$SESSION_ID\",
  \"cwd\": \"/Users/ameno/dev/agentcockpit\"
}"

echo ""
echo "=== Replay complete ==="
