// AppModel.swift — @Observable root model: gateway connection + promoted session
import SwiftUI

@Observable
@MainActor
public final class AppModel {
    // MARK: - Sub-models
    public let settings = ACSettingsStore()
    public let connection: ACGatewayConnection
    public let transport: ACSessionTransport
    public let eventStore = AgentEventStore()

    // MARK: - Navigation state
    public var promotedSessionKey: String? = nil
    public var selectedTab: AppTab = .work

    public init() {
        let conn = ACGatewayConnection(settings: settings)
        self.connection = conn
        self.transport = ACSessionTransport(connection: conn, settings: settings)
    }

    // MARK: - Lifecycle

    public func start() {
        transport.resetConnectionLifecycle()
        connection.connect { [weak self] message in
            self?.handleMessage(message)
        }
    }

    public func stop() {
        connection.disconnect()
    }

    // MARK: - Message handling

    private func handleMessage(_ message: ACServerMessage) {
        transport.handleMessage(message)

        if case .event(let frame) = message {
            eventStore.ingest(frame)
            return
        }

        if case .jsonrpcNotification(let method, let params) = message {
            if consumeMetadataNotification(
                protocolMode: settings.serverProtocol,
                method: method,
                params: params,
                fallbackSessionKey: promotedSessionKey
            ) {
                return
            }
            if let mapped = JSONRPCEventAdapter.map(
                protocolMode: settings.serverProtocol,
                method: method,
                params: params,
                fallbackSessionKey: promotedSessionKey
            ) {
                eventStore.ingest(event: mapped.event, sessionKey: mapped.sessionKey)
            }
            return
        }

        if case .jsonrpcRequest(let id, let method, let params) = message {
            transport.handleServerRequest(id: id, method: method, params: params)
        }
    }

    private func consumeMetadataNotification(
        protocolMode: ACServerProtocol,
        method: String,
        params: [String: AnyCodable]?,
        fallbackSessionKey: String?
    ) -> Bool {
        guard protocolMode == .codex else { return false }
        let root = params ?? [:]
        let sessionKey = root["threadId"]?.stringValue
            ?? root["thread"]?.dictValue?["id"]?.stringValue
            ?? root["turn"]?.dictValue?["threadId"]?.stringValue
            ?? fallbackSessionKey
            ?? "codex"
        let timestamp = dateFrom(root["updatedAt"])
            ?? dateFrom(root["timestamp"])
            ?? .now

        switch method {
        case "thread/tokenUsage/updated":
            if let usage = parseTokenUsage(from: root, timestamp: timestamp) {
                eventStore.updateTokenUsage(usage, sessionKey: sessionKey)
            }
            return true

        case "thread/status/changed":
            let status = root["status"]?.dictValue?["type"]?.stringValue
                ?? root["status"]?.stringValue
                ?? root["state"]?.stringValue
                ?? "unknown"
            eventStore.updateSessionStatus(status, sessionKey: sessionKey, at: timestamp)
            return true

        case "thread/started", "turn/started", "turn/completed":
            eventStore.touchSession(sessionKey, at: timestamp)
            return true

        default:
            return false
        }
    }

    private func parseTokenUsage(from root: [String: AnyCodable], timestamp: Date) -> SessionTokenUsage? {
        let usage = root["tokenUsage"]?.dictValue
            ?? root["token_usage"]?.dictValue
            ?? root["usage"]?.dictValue
            ?? root

        let input = integerValue(
            usage["inputTokens"]
            ?? usage["input_tokens"]
            ?? usage["input"]
            ?? usage["promptTokens"]
        )
        let output = integerValue(
            usage["outputTokens"]
            ?? usage["output_tokens"]
            ?? usage["output"]
            ?? usage["completionTokens"]
        )
        let total = integerValue(
            usage["totalTokens"]
            ?? usage["total_tokens"]
            ?? usage["total"]
        ) ?? {
            guard let input, let output else { return nil }
            return input + output
        }()

        guard input != nil || output != nil || total != nil else { return nil }
        return SessionTokenUsage(
            inputTokens: input,
            outputTokens: output,
            totalTokens: total,
            updatedAt: timestamp
        )
    }

    private func integerValue(_ value: AnyCodable?) -> Int? {
        if let int = value?.intValue { return int }
        if let double = value?.doubleValue { return Int(double) }
        if let text = value?.stringValue, let int = Int(text) { return int }
        return nil
    }

    private func dateFrom(_ value: AnyCodable?) -> Date? {
        guard let value else { return nil }
        if let seconds = value.doubleValue {
            let normalized = seconds > 1_000_000_000_000 ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: normalized)
        }
        if let text = value.stringValue {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: text)
        }
        return nil
    }

    // MARK: - Session promotion

    public func promoteSession(_ key: String) {
        promotedSessionKey = key
        selectedTab = .work
        Task {
            try? await transport.promote(sessionKey: key)
        }
    }
}

public enum AppTab: Hashable {
    case home
    case work
    case ais
}

private enum JSONRPCEventAdapter {
    static func map(
        protocolMode: ACServerProtocol,
        method: String,
        params: [String: AnyCodable]?,
        fallbackSessionKey: String?
    ) -> (sessionKey: String, event: CanvasEvent)? {
        switch protocolMode {
        case .gatewayLegacy:
            return nil
        case .acp:
            return mapACP(method: method, params: params, fallbackSessionKey: fallbackSessionKey)
        case .codex:
            return mapCodex(method: method, params: params, fallbackSessionKey: fallbackSessionKey)
        }
    }

    private static func mapACP(
        method: String,
        params: [String: AnyCodable]?,
        fallbackSessionKey: String?
    ) -> (sessionKey: String, event: CanvasEvent)? {
        guard method == "session/update" else { return nil }
        let root = params ?? [:]
        let update = root["update"]?.dictValue ?? root
        let sessionKey = root["sessionId"]?.stringValue
            ?? root["session_id"]?.stringValue
            ?? update["sessionId"]?.stringValue
            ?? fallbackSessionKey
            ?? "acp"
        let kind = update["kind"]?.stringValue ?? update["type"]?.stringValue ?? "session/update"

        if kind.contains("tool_call_update") {
            let toolName = update["toolName"]?.stringValue
                ?? update["tool"]?.dictValue?["name"]?.stringValue
                ?? "Tool"
            let resultText = update["output"]?.stringValue
                ?? update["result"]?.stringValue
                ?? update["message"]?.stringValue
                ?? compactJSONString(from: update)
            let toolID = toolEventID(
                protocolPrefix: "acp",
                sessionKey: sessionKey,
                primaryID: firstNonEmpty(
                    update["toolCallId"]?.stringValue,
                    update["tool_call_id"]?.stringValue,
                    update["id"]?.stringValue
                ),
                fallback: toolName
            )
            return (
                sessionKey,
                .toolUse(
                    ToolUseEvent(
                        id: toolID,
                        toolName: toolName,
                        phase: .result,
                        input: "",
                        result: resultText,
                        status: kind.contains("error") ? .error : .done
                    )
                )
            )
        }

        if kind.contains("tool_call") {
            let toolName = update["toolName"]?.stringValue
                ?? update["tool"]?.dictValue?["name"]?.stringValue
                ?? "Tool"
            let inputText = update["input"]?.stringValue
                ?? update["arguments"]?.stringValue
                ?? compactJSONString(from: update["arguments"]?.dictValue ?? [:])
            let toolID = toolEventID(
                protocolPrefix: "acp",
                sessionKey: sessionKey,
                primaryID: firstNonEmpty(
                    update["toolCallId"]?.stringValue,
                    update["tool_call_id"]?.stringValue,
                    update["id"]?.stringValue
                ),
                fallback: toolName
            )
            return (
                sessionKey,
                .toolUse(
                    ToolUseEvent(
                        id: toolID,
                        toolName: toolName,
                        phase: .start,
                        input: inputText,
                        status: .running
                    )
                )
            )
        }

        if kind.contains("agent_message") || kind.contains("agent_thought") {
            let text = update["text"]?.stringValue
                ?? update["delta"]?.stringValue
                ?? update["content"]?.stringValue
                ?? update["message"]?.stringValue
                ?? compactJSONString(from: update)
            guard !text.isEmpty else { return nil }
            let eventID = reasoningEventID(
                protocolPrefix: "acp",
                sessionKey: sessionKey,
                primaryID: firstNonEmpty(
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
                fallback: kind,
                allowFallbackMerge: false
            )
            return (
                sessionKey,
                .reasoning(
                    ReasoningEvent(
                        id: eventID,
                        text: text,
                        isThinking: kind.contains("thought")
                    )
                )
            )
        }

        return (
            sessionKey,
            .rawOutput(RawOutputEvent(text: "ACP \(kind)", hookEvent: method))
        )
    }

    private static func mapCodex(
        method: String,
        params: [String: AnyCodable]?,
        fallbackSessionKey: String?
    ) -> (sessionKey: String, event: CanvasEvent)? {
        let root = params ?? [:]
        let sessionKey = root["threadId"]?.stringValue
            ?? root["thread"]?.dictValue?["id"]?.stringValue
            ?? root["turn"]?.dictValue?["threadId"]?.stringValue
            ?? fallbackSessionKey
            ?? "codex"

        switch method {
        case "item/agentMessage/delta":
            let delta = root["delta"]?.stringValue
                ?? root["text"]?.stringValue
                ?? ""
            guard !delta.isEmpty else { return nil }
            let eventID = reasoningEventID(
                protocolPrefix: "codex",
                sessionKey: sessionKey,
                primaryID: firstNonEmpty(
                    root["itemId"]?.stringValue,
                    root["item_id"]?.stringValue,
                    root["item"]?.dictValue?["id"]?.stringValue,
                    root["id"]?.stringValue
                ),
                turnID: firstNonEmpty(
                    root["turnId"]?.stringValue,
                    root["turn"]?.dictValue?["id"]?.stringValue
                ),
                fallback: "agentMessage"
            )
            return (sessionKey, .reasoning(ReasoningEvent(id: eventID, text: delta, isThinking: false)))

        case "item/started", "item/completed":
            guard let item = root["item"]?.dictValue else {
                return (sessionKey, .rawOutput(RawOutputEvent(text: method, hookEvent: method)))
            }
            let itemType = item["type"]?.stringValue ?? "item"

            if itemType == "userMessage" {
                let text = userMessageText(from: item)
                guard !text.isEmpty else { return nil }
                let itemID = firstNonEmpty(
                    item["id"]?.stringValue,
                    root["itemId"]?.stringValue
                ) ?? UUID().uuidString
                return (
                    sessionKey,
                    .rawOutput(
                        RawOutputEvent(
                            id: "codex/\(sessionKey)/user/\(itemID)",
                            text: "You: \(text)",
                            hookEvent: method
                        )
                    )
                )
            }

            if itemType == "agentMessage" {
                let text = item["text"]?.stringValue
                    ?? item["content"]?.stringValue
                    ?? ""
                guard !text.isEmpty else { return nil }
                let eventID = reasoningEventID(
                    protocolPrefix: "codex",
                    sessionKey: sessionKey,
                    primaryID: firstNonEmpty(
                        item["id"]?.stringValue,
                        root["itemId"]?.stringValue,
                        root["item"]?.dictValue?["id"]?.stringValue
                    ),
                    turnID: firstNonEmpty(
                        item["turnId"]?.stringValue,
                        root["turnId"]?.stringValue,
                        root["turn"]?.dictValue?["id"]?.stringValue
                    ),
                    fallback: "agentMessage"
                )
                return (sessionKey, .reasoning(ReasoningEvent(id: eventID, text: text, isThinking: false)))
            }

            if itemType == "reasoning" {
                let text = reasoningText(from: item)
                guard !text.isEmpty else { return nil }
                let eventID = reasoningEventID(
                    protocolPrefix: "codex",
                    sessionKey: sessionKey,
                    primaryID: firstNonEmpty(
                        item["id"]?.stringValue,
                        root["itemId"]?.stringValue,
                        root["item"]?.dictValue?["id"]?.stringValue
                    ),
                    turnID: firstNonEmpty(
                        item["turnId"]?.stringValue,
                        root["turnId"]?.stringValue,
                        root["turn"]?.dictValue?["id"]?.stringValue
                    ),
                    fallback: "reasoning"
                )
                return (sessionKey, .reasoning(ReasoningEvent(id: eventID, text: text, isThinking: true)))
            }

            if itemType == "commandExecution" {
                let command = commandText(from: item)
                let statusRaw = item["status"]?.stringValue ?? ""
                let status: ToolStatus = switch statusRaw {
                case "failed", "declined": .error
                case "completed": .done
                default: method == "item/completed" ? .done : .running
                }
                let output = item["aggregatedOutput"]?.stringValue
                    ?? item["stderr"]?.stringValue
                    ?? item["stdout"]?.stringValue
                let toolID = toolEventID(
                    protocolPrefix: "codex",
                    sessionKey: sessionKey,
                    primaryID: firstNonEmpty(
                        item["id"]?.stringValue,
                        root["itemId"]?.stringValue
                    ),
                    fallback: "command"
                )
                return (
                    sessionKey,
                    .toolUse(
                        ToolUseEvent(
                            id: toolID,
                            toolName: "command",
                            phase: status == .running ? .start : .result,
                            input: command,
                            result: output,
                            status: status
                        )
                    )
                )
            }

            if itemType == "fileChange" {
                if let changes = item["changes"]?.arrayValue,
                   let first = changes.first?.dictValue,
                   let path = first["path"]?.stringValue {
                    let kind = first["kind"]?.stringValue?.lowercased() ?? ""
                    let operation: FileOperation = switch kind {
                    case "delete", "deleted": .delete
                    case "create", "created", "add", "added": .write
                    default: .edit
                    }
                    let fileID = toolEventID(
                        protocolPrefix: "codex",
                        sessionKey: sessionKey,
                        primaryID: firstNonEmpty(
                            item["id"]?.stringValue,
                            root["itemId"]?.stringValue
                        ),
                        fallback: "file/\(path)"
                    )
                    return (sessionKey, .fileEdit(FileEditEvent(id: fileID, filePath: path, operation: operation)))
                }
            }

            if itemType == "mcpToolCall" || itemType == "collabToolCall" {
                let toolName = item["tool"]?.stringValue
                    ?? item["name"]?.stringValue
                    ?? itemType
                let statusRaw = item["status"]?.stringValue ?? ""
                let status: ToolStatus = switch statusRaw {
                case "failed": .error
                case "completed": .done
                default: .running
                }
                let toolID = toolEventID(
                    protocolPrefix: "codex",
                    sessionKey: sessionKey,
                    primaryID: firstNonEmpty(
                        item["id"]?.stringValue,
                        root["itemId"]?.stringValue
                    ),
                    fallback: toolName
                )
                return (
                    sessionKey,
                    .toolUse(
                        ToolUseEvent(
                            id: toolID,
                            toolName: toolName,
                            phase: status == .running ? .start : .result,
                            input: compactJSONString(from: item["arguments"]?.dictValue ?? [:]),
                            result: item["result"]?.stringValue,
                            status: status
                        )
                    )
                )
            }

            return (
                sessionKey,
                .rawOutput(RawOutputEvent(text: "Codex item: \(itemType)", hookEvent: method))
            )

        case "turn/started", "turn/completed", "thread/started", "thread/status/changed", "thread/tokenUsage/updated":
            return nil

        default:
            return nil
        }
    }

    private static func commandText(from item: [String: AnyCodable]) -> String {
        if let array = item["command"]?.arrayValue {
            let parts = array.compactMap(\.stringValue)
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        return item["command"]?.stringValue ?? "command"
    }

    private static func userMessageText(from item: [String: AnyCodable]) -> String {
        if let content = item["content"]?.arrayValue {
            let parts = content.compactMap { entry -> String? in
                guard let payload = entry.dictValue else { return entry.stringValue }
                if payload["type"]?.stringValue == "text" {
                    return payload["text"]?.stringValue
                }
                return nil
            }
            let filtered = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !filtered.isEmpty {
                return filtered.joined(separator: "\n")
            }
        }
        return item["text"]?.stringValue ?? ""
    }

    private static func reasoningText(from item: [String: AnyCodable]) -> String {
        if let text = item["text"]?.stringValue, !text.isEmpty { return text }
        if let summaryText = item["summary"]?.stringValue, !summaryText.isEmpty { return summaryText }
        if let summaryItems = item["summary"]?.arrayValue {
            let parts = summaryItems.compactMap { entry -> String? in
                if let text = entry.stringValue, !text.isEmpty { return text }
                guard let payload = entry.dictValue else { return nil }
                return payload["text"]?.stringValue
                    ?? payload["summary"]?.stringValue
            }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                return parts.joined(separator: "\n")
            }
        }
        return item["content"]?.stringValue ?? ""
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String? {
        for candidate in candidates {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    private static func reasoningEventID(
        protocolPrefix: String,
        sessionKey: String,
        primaryID: String?,
        turnID: String?,
        fallback: String,
        allowFallbackMerge: Bool = true
    ) -> String {
        if let primaryID {
            return "\(protocolPrefix)/\(sessionKey)/\(primaryID)"
        }
        if let turnID {
            return "\(protocolPrefix)/\(sessionKey)/turn/\(turnID)/\(fallback)"
        }
        if !allowFallbackMerge {
            return "\(protocolPrefix)/\(sessionKey)/\(fallback)/\(UUID().uuidString)"
        }
        return "\(protocolPrefix)/\(sessionKey)/\(fallback)"
    }

    private static func toolEventID(
        protocolPrefix: String,
        sessionKey: String,
        primaryID: String?,
        fallback: String
    ) -> String {
        if let primaryID {
            return "\(protocolPrefix)/\(sessionKey)/tool/\(primaryID)"
        }
        return "\(protocolPrefix)/\(sessionKey)/tool/\(fallback)"
    }

    private static func compactJSONString(from dict: [String: AnyCodable]) -> String {
        guard !dict.isEmpty else { return "" }
        let raw = dictionaryToRawValue(dict)
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
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
}
