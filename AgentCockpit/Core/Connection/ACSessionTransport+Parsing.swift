// ACSessionTransport+Parsing.swift — Shared parsing helpers
import Foundation

extension ACSessionTransport {
    static func mapCodexHistory(from result: AnyCodable?) -> [CanvasEvent] {
        let snapshot = CodexProtocolParser.parseHistory(from: result)
        var history: [CanvasEvent] = []
        for turn in snapshot.turns {
            for item in turn.items {
                history.append(contentsOf: parseCodexHistoryItem(item, threadKey: snapshot.threadID))
            }
        }
        return history
    }

    static func mapACPHistory(from result: AnyCodable?, sessionKey: String) -> [CanvasEvent] {
        let root = result?.dictValue ?? [:]
        let messages = root["history"]?.arrayValue
            ?? root["messages"]?.arrayValue
            ?? root["session"]?.dictValue?["history"]?.arrayValue
            ?? root["session"]?.dictValue?["messages"]?.arrayValue
            ?? []

        var history: [CanvasEvent] = []
        history.reserveCapacity(messages.count)

        for (index, messageAny) in messages.enumerated() {
            guard let message = messageAny.dictValue else { continue }
            let role = (message["role"]?.stringValue ?? "assistant").lowercased()
            let content = historyMessageText(from: message).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }

            let messageID = message["id"]?.stringValue
                ?? message["messageId"]?.stringValue
                ?? message["message_id"]?.stringValue
                ?? "\(index)"

            switch role {
            case "user":
                history.append(
                    .rawOutput(
                        RawOutputEvent(
                            id: "acp/\(sessionKey)/history/user/\(messageID)",
                            text: "You: \(content)",
                            hookEvent: "history/userMessage"
                        )
                    )
                )
            case "system":
                history.append(
                    .rawOutput(
                        RawOutputEvent(
                            id: "acp/\(sessionKey)/history/system/\(messageID)",
                            text: content,
                            hookEvent: "history/systemMessage"
                        )
                    )
                )
            default:
                history.append(
                    .reasoning(
                        ReasoningEvent(
                            id: "acp/\(sessionKey)/history/assistant/\(messageID)",
                            text: content,
                            isThinking: false
                        )
                    )
                )
            }
        }

        return history
    }

    static func mapACPReplayUpdates(from result: AnyCodable?, sessionKey: String) -> [CanvasEvent] {
        let root = result?.dictValue ?? [:]
        let updates = root["updates"]?.arrayValue
            ?? root["events"]?.arrayValue
            ?? root["session"]?.dictValue?["updates"]?.arrayValue
            ?? []
        guard !updates.isEmpty else { return [] }

        var mapped: [CanvasEvent] = []
        mapped.reserveCapacity(updates.count)

        for updateAny in updates {
            guard let update = updateAny.dictValue else { continue }
            let parsed = ACPProtocolParser.parseSessionUpdate(
                params: [
                    "sessionId": AnyCodable(sessionKey),
                    "update": AnyCodable(update),
                ],
                fallbackSessionID: sessionKey
            )

            switch parsed.type {
            case .userMessage:
                guard !parsed.text.isEmpty else { continue }
                let eventID = parsed.updateID ?? UUID().uuidString
                mapped.append(
                    .rawOutput(
                        RawOutputEvent(
                            id: "acp/\(sessionKey)/user/\(eventID)",
                            text: "You: \(parsed.text)",
                            hookEvent: "session/update"
                        )
                    )
                )
            case .agentMessage, .agentThought:
                guard !parsed.text.isEmpty else { continue }
                mapped.append(
                    .reasoning(
                        ReasoningEvent(
                            id: parsed.updateID ?? "acp/\(sessionKey)/agent/\(UUID().uuidString)",
                            text: parsed.text,
                            isThinking: parsed.type == .agentThought
                        )
                    )
                )
            case .toolCall, .toolCallUpdate:
                let defaultStatus: ToolStatus = parsed.type == .toolCall ? .running : .done
                let status = mapACPToolStatus(from: parsed, default: defaultStatus)
                mapped.append(
                    .toolUse(
                        ToolUseEvent(
                            id: "acp/\(sessionKey)/tool/\(parsed.toolCallID ?? UUID().uuidString)",
                            toolName: parsed.toolName,
                            phase: parsed.type == .toolCall && status == .running ? .start : .result,
                            input: parsed.type == .toolCall ? parsed.toolInput : "",
                            result: parsed.type == .toolCall ? nil : parsed.toolResult,
                            status: status
                        )
                    )
                )
            case .genUI, .sessionInfo, .unknown:
                continue
            }
        }

        return mapped
    }

    static func parseCodexHistoryItem(_ item: CodexItemSnapshot, threadKey: String) -> [CanvasEvent] {
        let itemID = item.id ?? UUID().uuidString

        switch item.type {
        case .userMessage:
            guard !item.text.isEmpty else { return [] }
            return [
                .rawOutput(
                    RawOutputEvent(
                        id: "codex/\(threadKey)/user/\(itemID)",
                        text: "You: \(item.text)",
                        hookEvent: "history/userMessage"
                    )
                )
            ]

        case .agentMessage:
            guard !item.text.isEmpty else { return [] }
            return [
                .reasoning(
                    ReasoningEvent(
                        id: codexReasoningEventID(
                            threadKey: threadKey,
                            item: item,
                            fallback: "agentMessage"
                        ),
                        text: item.text,
                        isThinking: false
                    )
                )
            ]

        case .reasoning:
            guard !item.text.isEmpty else { return [] }
            return [
                .reasoning(
                    ReasoningEvent(
                        id: codexReasoningEventID(
                            threadKey: threadKey,
                            item: item,
                            fallback: "reasoning"
                        ),
                        text: item.text,
                        isThinking: true
                    )
                )
            ]

        case .commandExecution:
            let status: ToolStatus = switch item.status {
            case "failed", "declined":
                .error
            case "completed":
                .done
            default:
                .running
            }
            return [
                .toolUse(
                    ToolUseEvent(
                        id: "codex/\(threadKey)/tool/\(itemID)",
                        toolName: "command",
                        phase: status == .running ? .start : .result,
                        input: item.commandText,
                        result: item.commandOutput,
                        status: status
                    )
                )
            ]

        case .fileChange:
            guard let change = item.fileChanges.first else { return [] }
            return [
                .fileEdit(
                    FileEditEvent(
                        id: "codex/\(threadKey)/tool/\(itemID)",
                        filePath: change.path,
                        operation: fileOperation(from: change.kind)
                    )
                )
            ]

        default:
            return []
        }
    }

    static func codexReasoningEventID(
        threadKey: String,
        item: CodexItemSnapshot,
        fallback: String
    ) -> String {
        if let turnID = item.turnID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !turnID.isEmpty {
            return "codex/\(threadKey)/turn/\(turnID)/\(fallback)"
        }
        if let itemID = item.id?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !itemID.isEmpty {
            return "codex/\(threadKey)/\(itemID)"
        }
        return "codex/\(threadKey)/\(fallback)"
    }

    static func mapACPToolStatus(from parsed: ACPUpdateContext, default fallback: ToolStatus) -> ToolStatus {
        guard let statusRaw = parsed.toolStatus else {
            return parsed.isError ? .error : fallback
        }
        switch statusRaw {
        case "pending", "in_progress", "running", "started":
            return .running
        case "completed", "done", "success":
            return .done
        case "error", "failed", "cancelled", "canceled":
            return .error
        default:
            return parsed.isError ? .error : .done
        }
    }

    static func fileOperation(from kind: String) -> FileOperation {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "delete", "deleted":
            return .delete
        case "create", "created", "add", "added":
            return .write
        default:
            return .edit
        }
    }

    static func historyMessageText(from message: [String: AnyCodable]) -> String {
        if let text = message["content"]?.stringValue, !text.isEmpty {
            return text
        }
        if let text = message["text"]?.stringValue, !text.isEmpty {
            return text
        }
        if let content = message["content"]?.dictValue {
            if let text = content["text"]?.stringValue, !text.isEmpty {
                return text
            }
            if let nested = content["content"]?.dictValue?["text"]?.stringValue, !nested.isEmpty {
                return nested
            }
        }
        if let entries = message["content"]?.arrayValue {
            let parts = entries.compactMap { entry -> String? in
                if let text = entry.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    return text
                }
                guard let payload = entry.dictValue else { return nil }
                if let text = payload["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    return text
                }
                if let nested = payload["content"]?.dictValue?["text"]?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !nested.isEmpty {
                    return nested
                }
                return nil
            }
            if !parts.isEmpty {
                return parts.joined(separator: "\n")
            }
        }
        return ""
    }

    static func bestDisplayName(candidates: [String?], fallback: String) -> String {
        for candidate in candidates {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  value != "<undecodable>"
            else { continue }
            return value
        }
        return fallback
    }

    static func statusText(from session: [String: AnyCodable]) -> String? {
        session["status"]?.dictValue?["type"]?.stringValue
            ?? session["status"]?.stringValue
            ?? session["state"]?.stringValue
    }

    static func runningState(from status: String?) -> Bool {
        guard let normalized = status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !normalized.isEmpty
        else {
            return true
        }
        switch normalized {
        case "active", "running", "live", "in_progress", "in-progress":
            return true
        case "idle", "done", "completed", "stopped", "cancelled":
            return false
        default:
            return true
        }
    }

    static func dateFrom(_ value: AnyCodable?) -> Date? {
        guard let value else { return nil }
        if let raw = value.doubleValue {
            return Date(timeIntervalSince1970: normalizeUnixTimestampToSeconds(raw))
        }
        if let text = value.stringValue {
            if let numeric = Double(text) {
                return Date(timeIntervalSince1970: normalizeUnixTimestampToSeconds(numeric))
            }
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: text)
        }
        return nil
    }

    static func normalizeUnixTimestampToSeconds(_ raw: Double) -> TimeInterval {
        if raw >= 1e17 {
            return raw / 1_000_000_000.0
        }
        if raw >= 1e14 {
            return raw / 1_000_000.0
        }
        if raw >= 1e11 {
            return raw / 1_000.0
        }
        return raw
    }

    static func normalizedAbsoluteCwd(_ candidate: String?) -> String? {
        guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty else { return nil }
        guard candidate.hasPrefix("/") else { return nil }
        return candidate
    }

    static func acpCwd(from session: [String: AnyCodable], root: [String: AnyCodable]? = nil) -> String? {
        let sessionCwd = session["cwd"]?.stringValue
        let sessionWorkingDirectory = session["workingDirectory"]?.stringValue
        let sessionWorkingDirectoryLegacy = session["working_directory"]?.stringValue
        let sessionWorkspace = session["workspace"]?.stringValue
        let rootCwd = root?["cwd"]?.stringValue
        let rootWorkingDirectory = root?["workingDirectory"]?.stringValue
        let rootWorkingDirectoryLegacy = root?["working_directory"]?.stringValue
        let rootPiAcpCwd = root?["_meta"]?.dictValue?["piAcp"]?.dictValue?["cwd"]?.stringValue

        let candidate = sessionCwd
            ?? sessionWorkingDirectory
            ?? sessionWorkingDirectoryLegacy
            ?? sessionWorkspace
            ?? rootCwd
            ?? rootWorkingDirectory
            ?? rootWorkingDirectoryLegacy
            ?? rootPiAcpCwd
        return normalizedAbsoluteCwd(candidate)
    }
}
