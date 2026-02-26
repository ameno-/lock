// AgentEventParser.swift — Pure function: ACEventFrame → CanvasEvent?
import Foundation

public enum AgentEventParser {

    /// Parse an incoming event frame into a renderable CanvasEvent.
    /// Returns nil for frames that should be silently ignored.
    public static func parse(_ frame: ACEventFrame) -> CanvasEvent? {
        let data = frame.data
        let hookEvent = data["hookEvent"]?.stringValue ?? ""

        switch frame.stream {
        case .tool:
            return parseTool(data: data, hookEvent: hookEvent, ts: frame.ts)

        case .assistant:
            return parseAssistant(data: data, ts: frame.ts)

        case .git:
            return parseGit(data: data, ts: frame.ts)

        case .subagent:
            return parseSubAgent(data: data, hookEvent: hookEvent, ts: frame.ts)

        case .skill:
            return parseSkill(data: data, ts: frame.ts)

        case .system:
            // System events (session start/stop) — show as raw if interesting
            if ["Stop", "UserPromptSubmit"].contains(hookEvent) {
                let text = hookEvent == "Stop" ? "Session ended" : "Prompt submitted"
                return .rawOutput(RawOutputEvent(text: text, hookEvent: hookEvent, timestamp: frame.ts))
            }
            return nil
        }
    }

    // MARK: - Tool parsing

    private static func parseTool(
        data: [String: AnyCodable],
        hookEvent: String,
        ts: Date
    ) -> CanvasEvent? {
        let toolName = data["toolName"]?.stringValue ?? "Unknown"
        let phase: ToolPhase = hookEvent == "PreToolUse" ? .start : .result

        // Check if it's a file operation
        if let filePath = extractFilePath(toolName: toolName, data: data) {
            let op = mapFileOperation(toolName)
            return .fileEdit(FileEditEvent(filePath: filePath, operation: op, timestamp: ts))
        }

        // Check if it's a git command
        if isGitCommand(toolName: toolName, data: data) {
            let rawDiff = data["toolResponse"]?.dictValue?["stdout"]?.stringValue ?? ""
            let (additions, deletions) = countDiffLines(rawDiff)
            return .gitDiff(GitDiffEvent(
                rawDiff: rawDiff,
                additions: additions,
                deletions: deletions,
                timestamp: ts
            ))
        }

        // Generic tool card
        let inputStr = formatToolInput(toolName: toolName, data: data)
        let resultStr: String?
        if phase == .result {
            let resp = data["toolResponse"]?.dictValue
            resultStr = resp?["stdout"]?.stringValue ?? resp?["result"]?.stringValue
        } else {
            resultStr = nil
        }

        let status: ToolStatus = {
            if phase == .start { return .running }
            let resp = data["toolResponse"]?.dictValue
            let stderr = resp?["stderr"]?.stringValue ?? ""
            return stderr.isEmpty ? .done : .error
        }()

        return .toolUse(ToolUseEvent(
            toolName: toolName,
            phase: phase,
            input: inputStr,
            result: resultStr,
            status: status,
            timestamp: ts
        ))
    }

    // MARK: - Assistant parsing

    private static func parseAssistant(data: [String: AnyCodable], ts: Date) -> CanvasEvent? {
        guard let message = data["message"]?.dictValue else { return nil }
        let content = message["content"]?.stringValue
            ?? (message["content"]?.value as? String)
            ?? ""

        // Check for <think> blocks
        if content.contains("<think>") || content.contains("<thinking>") {
            let (thinking, text) = AssistantTextParser.split(content)
            let displayText = thinking ?? text
            return .reasoning(ReasoningEvent(
                text: displayText,
                isThinking: thinking != nil,
                timestamp: ts
            ))
        }

        if content.isEmpty { return nil }
        return .reasoning(ReasoningEvent(text: content, isThinking: false, timestamp: ts))
    }

    // MARK: - Git parsing

    private static func parseGit(data: [String: AnyCodable], ts: Date) -> CanvasEvent? {
        let rawDiff = data["toolResponse"]?.dictValue?["stdout"]?.stringValue
            ?? data["diff"]?.stringValue
            ?? ""
        let filePath = data["filePath"]?.stringValue
        let (additions, deletions) = countDiffLines(rawDiff)
        return .gitDiff(GitDiffEvent(
            rawDiff: rawDiff,
            filePath: filePath,
            additions: additions,
            deletions: deletions,
            timestamp: ts
        ))
    }

    // MARK: - SubAgent parsing

    private static func parseSubAgent(
        data: [String: AnyCodable],
        hookEvent: String,
        ts: Date
    ) -> CanvasEvent? {
        let subSessionKey = data["sessionId"]?.stringValue
            ?? data["subSessionKey"]?.stringValue
            ?? UUID().uuidString
        let model = data["model"]?.stringValue

        let phase: SubAgentPhase = {
            switch hookEvent {
            case "SubagentStop": return .done
            default: return .spawned
            }
        }()

        return .subAgent(SubAgentEvent(
            subSessionKey: subSessionKey,
            modelName: model,
            phase: phase,
            timestamp: ts
        ))
    }

    // MARK: - Skill parsing

    private static func parseSkill(data: [String: AnyCodable], ts: Date) -> CanvasEvent? {
        let skillName = data["skillName"]?.stringValue ?? "Unknown Skill"
        let statusRaw = data["status"]?.stringValue ?? ""
        let status: SkillStatus = statusRaw == "done" ? .done : statusRaw == "failed" ? .failed : .running
        let durationMs = data["durationMs"]?.intValue
        return .skillRun(SkillRunEvent(skillName: skillName, status: status, durationMs: durationMs, timestamp: ts))
    }

    // MARK: - Helpers

    private static func isGitCommand(toolName: String, data: [String: AnyCodable]) -> Bool {
        guard toolName == "Bash" else { return false }
        let cmd = data["toolInput"]?.dictValue?["command"]?.stringValue ?? ""
        return cmd.trimmingCharacters(in: .whitespaces).hasPrefix("git")
    }

    private static func extractFilePath(toolName: String, data: [String: AnyCodable]) -> String? {
        let fileTools = ["Read", "Write", "Edit", "NotebookEdit"]
        guard fileTools.contains(toolName) else { return nil }
        let input = data["toolInput"]?.dictValue
        return input?["file_path"]?.stringValue
            ?? input?["notebook_path"]?.stringValue
            ?? input?["path"]?.stringValue
    }

    private static func mapFileOperation(_ toolName: String) -> FileOperation {
        switch toolName {
        case "Read": return .read
        case "Write": return .write
        case "Edit", "NotebookEdit": return .edit
        default: return .read
        }
    }

    private static func formatToolInput(toolName: String, data: [String: AnyCodable]) -> String {
        let input = data["toolInput"]?.dictValue ?? [:]
        if toolName == "Bash" {
            return input["command"]?.stringValue ?? ""
        }
        // Generic: show first string value
        return input.values.compactMap { $0.stringValue }.first ?? toolName
    }

    private static func countDiffLines(_ diff: String) -> (additions: Int, deletions: Int) {
        var additions = 0
        var deletions = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+") && !line.hasPrefix("+++") { additions += 1 }
            else if line.hasPrefix("-") && !line.hasPrefix("---") { deletions += 1 }
        }
        return (additions, deletions)
    }
}
