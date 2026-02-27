import Foundation

public enum CodexCanonicalItemType: Sendable, Equatable {
    case userMessage
    case agentMessage
    case reasoning
    case commandExecution
    case fileChange
    case mcpToolCall
    case collabToolCall
    case contextCompaction
    case unknown(String)
}

public struct CodexThreadSummary: Sendable, Equatable {
    public let id: String
    public let name: String?
    public let preview: String?
    public let statusType: String?
    public let cwd: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    public var isRunning: Bool {
        guard let normalized = statusType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !normalized.isEmpty
        else {
            return true
        }

        switch normalized {
        case "active", "running", "in_progress", "in-progress":
            return true
        case "idle", "done", "completed", "stopped", "cancelled", "canceled":
            return false
        default:
            return true
        }
    }
}

public struct CodexHistorySnapshot: Sendable, Equatable {
    public let threadID: String
    public let turns: [CodexTurnSnapshot]
}

public struct CodexTurnSnapshot: Sendable, Equatable {
    public let id: String?
    public let items: [CodexItemSnapshot]
}

public struct CodexFileChangeSnapshot: Sendable, Equatable {
    public let path: String
    public let kind: String
}

public struct CodexItemSnapshot: Sendable, Equatable {
    public let id: String?
    public let turnID: String?
    public let rawType: String
    public let type: CodexCanonicalItemType
    public let status: String?
    public let text: String
    public let commandText: String
    public let commandOutput: String?
    public let toolName: String?
    public let toolArgumentsJSON: String
    public let toolResult: String?
    public let fileChanges: [CodexFileChangeSnapshot]
}

public enum CodexProtocolParser {
    public static func parseThreadList(from result: AnyCodable?) -> [CodexThreadSummary] {
        let root = result?.dictValue ?? [:]
        let rows = root["data"]?.arrayValue
            ?? root["threads"]?.arrayValue
            ?? result?.arrayValue
            ?? []
        return rows.compactMap { row in
            guard let dictionary = row.dictValue else { return nil }
            return parseThreadSummary(from: dictionary)
        }
    }

    public static func parseThread(from result: AnyCodable?) -> CodexThreadSummary? {
        let root = result?.dictValue ?? [:]
        if let thread = root["thread"]?.dictValue {
            return parseThreadSummary(from: thread)
        }

        if let threadID = firstNonEmpty(
            root["threadId"]?.stringValue,
            root["thread_id"]?.stringValue
        ) {
            return CodexThreadSummary(
                id: threadID,
                name: firstNonEmpty(root["name"]?.stringValue, root["title"]?.stringValue),
                preview: firstNonEmpty(
                    root["preview"]?.stringValue,
                    root["summary"]?.stringValue,
                    root["prompt"]?.stringValue
                ),
                statusType: firstNonEmpty(
                    root["status"]?.dictValue?["type"]?.stringValue,
                    root["status"]?.stringValue,
                    root["state"]?.stringValue
                ),
                cwd: firstNonEmpty(
                    root["cwd"]?.stringValue,
                    root["workingDirectory"]?.stringValue,
                    root["working_directory"]?.stringValue
                ),
                createdAt: parseDate(root["createdAt"] ?? root["created_at"]),
                updatedAt: parseDate(root["updatedAt"] ?? root["updated_at"])
            )
        }

        let thread = root["data"]?.dictValue?["thread"]?.dictValue
            ?? root["data"]?.dictValue
            ?? root
        return parseThreadSummary(from: thread)
    }

    public static func parseHistory(from result: AnyCodable?) -> CodexHistorySnapshot {
        let root = result?.dictValue ?? [:]
        let thread = root["thread"]?.dictValue
            ?? root["data"]?.dictValue?["thread"]?.dictValue
            ?? root
        let threadID = firstNonEmpty(
            thread["id"]?.stringValue,
            root["threadId"]?.stringValue,
            root["thread_id"]?.stringValue
        ) ?? "codex"

        let turns: [AnyCodable] = thread["turns"]?.arrayValue
            ?? root["turns"]?.arrayValue
            ?? root["data"]?.dictValue?["turns"]?.arrayValue
            ?? []

        let parsedTurns: [CodexTurnSnapshot] = turns.compactMap { turn in
            guard let dictionary = turn.dictValue else { return nil }
            return parseTurn(from: dictionary)
        }

        return CodexHistorySnapshot(threadID: threadID, turns: parsedTurns)
    }

    public static func parseItem(
        from item: [String: AnyCodable],
        fallbackTurnID: String? = nil
    ) -> CodexItemSnapshot {
        let rawType = item["type"]?.stringValue ?? "item"
        let type = canonicalType(from: rawType)
        let turnID = firstNonEmpty(
            item["turnId"]?.stringValue,
            item["turn_id"]?.stringValue,
            fallbackTurnID
        )
        let status = firstNonEmpty(
            item["status"]?.dictValue?["type"]?.stringValue,
            item["status"]?.stringValue
        )

        let text: String = switch type {
        case .userMessage:
            userMessageText(from: item)
        case .agentMessage:
            agentMessageText(from: item)
        case .reasoning:
            reasoningText(from: item)
        default:
            ""
        }

        return CodexItemSnapshot(
            id: firstNonEmpty(
                item["id"]?.stringValue,
                item["itemId"]?.stringValue,
                item["item_id"]?.stringValue
            ),
            turnID: turnID,
            rawType: rawType,
            type: type,
            status: status,
            text: text,
            commandText: commandText(from: item),
            commandOutput: firstNonEmpty(
                item["aggregatedOutput"]?.stringValue,
                item["stderr"]?.stringValue,
                item["stdout"]?.stringValue,
                item["result"]?.stringValue
            ),
            toolName: firstNonEmpty(
                item["tool"]?.stringValue,
                item["name"]?.stringValue,
                rawType
            ),
            toolArgumentsJSON: compactJSONString(from: item["arguments"]?.dictValue ?? [:]),
            toolResult: firstNonEmpty(item["result"]?.stringValue, item["output"]?.stringValue),
            fileChanges: parseFileChanges(from: item["changes"]?.arrayValue ?? [])
        )
    }

    public static func canonicalType(from rawType: String) -> CodexCanonicalItemType {
        let normalized = rawType
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()

        switch normalized {
        case "usermessage", "user_message":
            return .userMessage
        case "agentmessage", "agent_message":
            return .agentMessage
        case "reasoning":
            return .reasoning
        case "commandexecution", "command_execution":
            return .commandExecution
        case "filechange", "file_change":
            return .fileChange
        case "mcptoolcall", "mcp_tool_call":
            return .mcpToolCall
        case "collabtoolcall", "collab_tool_call":
            return .collabToolCall
        case "contextcompaction", "context_compaction":
            return .contextCompaction
        default:
            return .unknown(rawType)
        }
    }

    public static func parseDate(_ value: AnyCodable?) -> Date? {
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

    private static func parseThreadSummary(from row: [String: AnyCodable]) -> CodexThreadSummary? {
        guard let id = firstNonEmpty(
            row["id"]?.stringValue,
            row["threadId"]?.stringValue,
            row["thread_id"]?.stringValue
        ) else {
            return nil
        }

        return CodexThreadSummary(
            id: id,
            name: firstNonEmpty(row["name"]?.stringValue, row["title"]?.stringValue),
            preview: firstNonEmpty(
                row["preview"]?.stringValue,
                row["summary"]?.stringValue,
                row["prompt"]?.stringValue
            ),
            statusType: firstNonEmpty(
                row["status"]?.dictValue?["type"]?.stringValue,
                row["status"]?.stringValue,
                row["state"]?.stringValue
            ),
            cwd: firstNonEmpty(
                row["cwd"]?.stringValue,
                row["workingDirectory"]?.stringValue,
                row["working_directory"]?.stringValue
            ),
            createdAt: parseDate(row["createdAt"] ?? row["created_at"]),
            updatedAt: parseDate(row["updatedAt"] ?? row["updated_at"])
        )
    }

    private static func parseTurn(from turn: [String: AnyCodable]) -> CodexTurnSnapshot {
        let turnID = firstNonEmpty(
            turn["id"]?.stringValue,
            turn["turnId"]?.stringValue,
            turn["turn_id"]?.stringValue
        )
        let items: [AnyCodable] = turn["items"]?.arrayValue
            ?? turn["events"]?.arrayValue
            ?? []

        let parsedItems: [CodexItemSnapshot] = items.compactMap { item in
            guard let dictionary = item.dictValue else { return nil }
            return parseItem(from: dictionary, fallbackTurnID: turnID)
        }

        return CodexTurnSnapshot(id: turnID, items: parsedItems)
    }

    private static func parseFileChanges(from changes: [AnyCodable]) -> [CodexFileChangeSnapshot] {
        var parsed: [CodexFileChangeSnapshot] = []
        parsed.reserveCapacity(changes.count)
        for change in changes {
            guard let dictionary = change.dictValue else { continue }
            guard let path = firstNonEmpty(
                dictionary["path"]?.stringValue,
                dictionary["filePath"]?.stringValue,
                dictionary["file_path"]?.stringValue
            ) else {
                continue
            }
            let kind = firstNonEmpty(dictionary["kind"]?.stringValue, dictionary["type"]?.stringValue) ?? ""
            parsed.append(CodexFileChangeSnapshot(path: path, kind: kind))
        }
        return parsed
    }

    private static func commandText(from item: [String: AnyCodable]) -> String {
        if let commandArray = item["command"]?.arrayValue {
            let parts = commandArray.compactMap { value in
                trimmed(value.stringValue)
            }
            if !parts.isEmpty {
                return parts.joined(separator: " ")
            }
        }

        if let command = trimmed(item["command"]?.stringValue) {
            return command
        }

        if let argv = item["argv"]?.arrayValue {
            let parts = argv.compactMap { value in
                trimmed(value.stringValue)
            }
            if !parts.isEmpty {
                return parts.joined(separator: " ")
            }
        }

        return "command"
    }

    private static func userMessageText(from item: [String: AnyCodable]) -> String {
        if let text = trimmed(item["text"]?.stringValue) {
            return text
        }

        let parts = textParts(from: item["content"])
        if !parts.isEmpty {
            return parts.joined(separator: "\n")
        }

        return ""
    }

    private static func agentMessageText(from item: [String: AnyCodable]) -> String {
        if let text = trimmed(item["text"]?.stringValue) {
            return text
        }
        if let text = trimmed(item["content"]?.stringValue) {
            return text
        }
        if let text = trimmed(item["message"]?.stringValue) {
            return text
        }

        let parts = textParts(from: item["content"])
        if !parts.isEmpty {
            return parts.joined(separator: "\n")
        }

        return ""
    }

    private static func reasoningText(from item: [String: AnyCodable]) -> String {
        if let text = trimmed(item["text"]?.stringValue) {
            return text
        }
        if let text = trimmed(item["summary"]?.stringValue) {
            return text
        }

        let summaryParts = textParts(from: item["summary"])
        if !summaryParts.isEmpty {
            return summaryParts.joined(separator: "\n")
        }

        if let text = trimmed(item["content"]?.stringValue) {
            return text
        }

        let contentParts = textParts(from: item["content"])
        if !contentParts.isEmpty {
            return contentParts.joined(separator: "\n")
        }

        return ""
    }

    private static func textParts(from value: AnyCodable?) -> [String] {
        guard let value else { return [] }

        if let text = trimmed(value.stringValue) {
            return [text]
        }

        if let dictionary = value.dictValue {
            var parts: [String] = []

            if dictionary["type"]?.stringValue?.lowercased() == "text",
               let direct = trimmed(dictionary["text"]?.stringValue) {
                parts.append(direct)
            }

            let directKeys = ["text", "value", "message", "delta", "result", "output"]
            for key in directKeys {
                if let direct = trimmed(dictionary[key]?.stringValue) {
                    parts.append(direct)
                }
            }

            if let summary = dictionary["summary"] {
                parts.append(contentsOf: textParts(from: summary))
            }
            if let content = dictionary["content"] {
                parts.append(contentsOf: textParts(from: content))
            }

            return deduplicated(parts)
        }

        if let array = value.arrayValue {
            let parts = array.flatMap { entry in
                textParts(from: entry)
            }
            return deduplicated(parts)
        }

        return []
    }

    private static func compactJSONString(from dict: [String: AnyCodable]) -> String {
        guard !dict.isEmpty else { return "" }
        let raw = dictionaryToRawValue(dict)
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return text
    }

    private static func dictionaryToRawValue(_ dict: [String: AnyCodable]) -> [String: Any] {
        var mapped: [String: Any] = [:]
        for (key, value) in dict {
            mapped[key] = rawValue(from: value)
        }
        return mapped
    }

    private static func rawValue(from value: AnyCodable) -> Any {
        if let dict = value.dictValue {
            return dictionaryToRawValue(dict)
        }
        if let array = value.arrayValue {
            return array.map(rawValue(from:))
        }
        if let text = value.stringValue { return text }
        if let bool = value.boolValue { return bool }
        if let int = value.intValue { return int }
        if let double = value.doubleValue { return double }
        return value.description
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String? {
        for candidate in candidates {
            if let trimmed = trimmed(candidate) {
                return trimmed
            }
        }
        return nil
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text != "<undecodable>"
        else {
            return nil
        }
        return text
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        ordered.reserveCapacity(values.count)
        for value in values where seen.insert(value).inserted {
            ordered.append(value)
        }
        return ordered
    }

    private static func normalizeUnixTimestampToSeconds(_ raw: Double) -> TimeInterval {
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
}
