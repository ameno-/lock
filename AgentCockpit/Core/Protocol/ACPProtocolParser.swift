import Foundation

public enum ACPCanonicalUpdateType: Sendable, Equatable {
    case toolCall
    case toolCallUpdate
    case userMessage
    case agentMessage
    case agentThought
    case sessionInfo
    case genUI
    case unknown(String)
}

public struct ACPUpdateContext: Sendable {
    public let sessionID: String
    public let rawKind: String
    public let type: ACPCanonicalUpdateType
    public let update: [String: AnyCodable]
    public let root: [String: AnyCodable]
    public let updateID: String?
    public let turnID: String?
    public let text: String
    public let toolName: String
    public let toolCallID: String?
    public let toolInput: String
    public let toolResult: String
    public let toolStatus: String?
    public let isError: Bool
}

public enum ACPProtocolParser {
    public static func parseSessionUpdate(
        params: [String: AnyCodable]?,
        fallbackSessionID: String?
    ) -> ACPUpdateContext {
        let root = params ?? [:]
        let update = root["update"]?.dictValue ?? root
        let sessionID = firstNonEmpty(
            root["sessionId"]?.stringValue,
            root["session_id"]?.stringValue,
            update["sessionId"]?.stringValue,
            update["session_id"]?.stringValue,
            fallbackSessionID
        ) ?? "acp"

        let rawKind = firstNonEmpty(
            update["sessionUpdate"]?.stringValue,
            update["kind"]?.stringValue,
            update["type"]?.stringValue
        ) ?? "session/update"

        let type = canonicalType(rawKind: rawKind, update: update)
        let text = extractText(from: update) ?? ""

        let toolName = firstNonEmpty(
            update["toolName"]?.stringValue,
            update["title"]?.stringValue,
            update["tool"]?.dictValue?["name"]?.stringValue
        ) ?? "Tool"

        let toolInput: String = {
            if !text.isEmpty {
                return text
            }
            let rawInput = compactJSONString(from: update["rawInput"]?.dictValue ?? [:])
            if !rawInput.isEmpty {
                return rawInput
            }
            return compactJSONString(from: update["arguments"]?.dictValue ?? [:])
        }()

        let toolResult: String = {
            if !text.isEmpty {
                return text
            }
            return compactJSONString(from: update)
        }()

        let lowerKind = rawKind.replacingOccurrences(of: "-", with: "_").lowercased()
        let toolStatus = normalizedStatus(from: update)
        let isError = lowerKind.contains("error")
            || toolStatus == "error"
            || toolStatus == "failed"
            || toolStatus == "cancelled"
            || toolStatus == "canceled"

        return ACPUpdateContext(
            sessionID: sessionID,
            rawKind: rawKind,
            type: type,
            update: update,
            root: root,
            updateID: firstNonEmpty(
                update["id"]?.stringValue,
                update["messageId"]?.stringValue,
                update["message_id"]?.stringValue,
                update["itemId"]?.stringValue,
                update["item_id"]?.stringValue,
                update["eventId"]?.stringValue,
                update["event_id"]?.stringValue
            ),
            turnID: firstNonEmpty(
                update["turnId"]?.stringValue,
                update["turn_id"]?.stringValue,
                root["turnId"]?.stringValue,
                root["turn_id"]?.stringValue
            ),
            text: text,
            toolName: toolName,
            toolCallID: firstNonEmpty(
                update["toolCallId"]?.stringValue,
                update["tool_call_id"]?.stringValue,
                update["id"]?.stringValue
            ),
            toolInput: toolInput,
            toolResult: toolResult,
            toolStatus: toolStatus,
            isError: isError
        )
    }

    public static func canonicalType(
        rawKind: String,
        update: [String: AnyCodable]
    ) -> ACPCanonicalUpdateType {
        if looksLikeGenUIPayload(update) {
            return .genUI
        }

        let normalized = rawKind.replacingOccurrences(of: "-", with: "_").lowercased()

        if normalized.contains("session_info_update") {
            return .sessionInfo
        }
        if normalized.contains("tool_call_update") {
            return .toolCallUpdate
        }
        if normalized.contains("tool_call") {
            return .toolCall
        }
        if normalized.contains("user_message_chunk") || normalized.contains("user_message") {
            return .userMessage
        }
        if normalized.contains("agent_thought_chunk") || normalized.contains("agent_thought") {
            return .agentThought
        }
        if normalized.contains("agent_message_chunk") || normalized.contains("agent_message") {
            return .agentMessage
        }

        return .unknown(rawKind)
    }

    public static func looksLikeGenUIPayload(_ payload: [String: AnyCodable]) -> Bool {
        if payload["genUI"]?.dictValue != nil || payload["gen_ui"]?.dictValue != nil {
            return true
        }
        if payload["surfaceSpec"]?.dictValue != nil || payload["surface_spec"]?.dictValue != nil {
            return true
        }

        let marker = firstNonEmpty(
            payload["kind"]?.stringValue,
            payload["type"]?.stringValue,
            payload["sessionUpdate"]?.stringValue
        )
        return marker?.localizedCaseInsensitiveContains("genui") == true
    }

    public static func extractText(from update: [String: AnyCodable]) -> String? {
        let direct = firstNonEmpty(
            update["text"]?.stringValue,
            update["delta"]?.stringValue,
            update["output"]?.stringValue,
            update["result"]?.stringValue,
            update["message"]?.stringValue,
            update["input"]?.stringValue,
            update["arguments"]?.stringValue
        )
        if let direct, !direct.isEmpty {
            return direct
        }

        if let contentObject = update["content"]?.dictValue {
            if let nested = firstNonEmpty(
                contentObject["text"]?.stringValue,
                contentObject["value"]?.stringValue
            ), !nested.isEmpty {
                return nested
            }
            if let nestedContent = contentObject["content"]?.dictValue,
               let nested = firstNonEmpty(
                   nestedContent["text"]?.stringValue,
                   nestedContent["value"]?.stringValue
               ), !nested.isEmpty {
                return nested
            }
        }

        if let contentArray = update["content"]?.arrayValue {
            let parts = contentArray.compactMap { entry -> String? in
                if let text = trimmed(entry.stringValue) {
                    return text
                }
                guard let dictionary = entry.dictValue else { return nil }
                if let text = trimmed(dictionary["text"]?.stringValue) {
                    return text
                }
                if let nested = trimmed(dictionary["content"]?.dictValue?["text"]?.stringValue) {
                    return nested
                }
                return nil
            }
            if !parts.isEmpty {
                return parts.joined(separator: "\n")
            }
        }

        if let inputObject = update["rawInput"]?.dictValue {
            let compact = compactJSONString(from: inputObject)
            if !compact.isEmpty {
                return compact
            }
        }

        return nil
    }

    public static func compactJSONString(from dict: [String: AnyCodable]) -> String {
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
        if let arr = value.arrayValue {
            return arr.map(rawValue(from:))
        }
        if let s = value.stringValue { return s }
        if let b = value.boolValue { return b }
        if let d = value.doubleValue { return d }
        if let i = value.intValue { return i }
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

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "<undecodable>"
        else {
            return nil
        }
        return value
    }

    private static func normalizedStatus(from update: [String: AnyCodable]) -> String? {
        let status = firstNonEmpty(
            update["status"]?.stringValue,
            update["status"]?.dictValue?["type"]?.stringValue,
            update["result"]?.dictValue?["status"]?.stringValue,
            update["toolResult"]?.dictValue?["status"]?.stringValue
        )
        return status?.replacingOccurrences(of: "-", with: "_").lowercased()
    }
}
