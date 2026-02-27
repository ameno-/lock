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

    // MARK: - Pending interaction requests

    public var pendingApprovalRequests: [ACPendingApprovalRequest] {
        transport.pendingApprovalRequests
    }

    public var pendingUserInputRequests: [ACPendingUserInputRequest] {
        transport.pendingUserInputRequests
    }

    public func respondToApprovalRequest(id: String, decision: ACApprovalDecision) {
        transport.respondToApprovalRequest(id: id, decision: decision)
    }

    public func submitUserInputRequest(id: String, answers: [String: [String]]) {
        transport.submitUserInputRequest(id: id, answers: answers)
    }

    public func dismissUserInputRequest(id: String) {
        transport.dismissUserInputRequest(id: id)
    }

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
                genuiEnabled: settings.genuiEnabled,
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
    case sessions
    case work
}

enum JSONRPCEventAdapter {
    static func map(
        protocolMode: ACServerProtocol,
        method: String,
        params: [String: AnyCodable]?,
        genuiEnabled: Bool,
        fallbackSessionKey: String?
    ) -> (sessionKey: String, event: CanvasEvent)? {
        switch protocolMode {
        case .acp:
            return mapACP(
                method: method,
                params: params,
                genuiEnabled: genuiEnabled,
                fallbackSessionKey: fallbackSessionKey
            )
        case .codex:
            return mapCodex(
                method: method,
                params: params,
                genuiEnabled: genuiEnabled,
                fallbackSessionKey: fallbackSessionKey
            )
        }
    }

    private static func mapACP(
        method: String,
        params: [String: AnyCodable]?,
        genuiEnabled: Bool,
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
        let kind = update["sessionUpdate"]?.stringValue
            ?? update["kind"]?.stringValue
            ?? update["type"]?.stringValue
            ?? "session/update"

        if !genuiEnabled && looksLikeGenUIPayload(update) {
            return (
                sessionKey,
                .rawOutput(
                    RawOutputEvent(
                        text: "GenUI payload received (disabled)",
                        hookEvent: method
                    )
                )
            )
        }

        if let event = parseGenUIEvent(
            payload: update,
            protocolPrefix: "acp",
            sessionKey: sessionKey,
            fallbackID: firstNonEmpty(update["id"]?.stringValue, root["requestId"]?.stringValue),
            fallbackTitle: "ACP GenUI"
        ) {
            return (sessionKey, .genUI(event))
        }

        if kind.contains("session_info_update") {
            return nil
        }

        if kind.contains("tool_call_update") {
            let toolName = update["toolName"]?.stringValue
                ?? update["title"]?.stringValue
                ?? update["tool"]?.dictValue?["name"]?.stringValue
                ?? "Tool"
            let resultText = sessionUpdateText(from: update)
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
                ?? update["title"]?.stringValue
                ?? update["tool"]?.dictValue?["name"]?.stringValue
                ?? "Tool"
            let inputText: String = {
                if let parsed = sessionUpdateText(from: update), !parsed.isEmpty {
                    return parsed
                }
                let rawInput = compactJSONString(from: update["rawInput"]?.dictValue ?? [:])
                if !rawInput.isEmpty {
                    return rawInput
                }
                return compactJSONString(from: update["arguments"]?.dictValue ?? [:])
            }()
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

        if kind.contains("user_message") {
            let text = sessionUpdateText(from: update) ?? compactJSONString(from: update)
            guard !text.isEmpty else { return nil }
            let eventID = firstNonEmpty(
                update["id"]?.stringValue,
                update["messageId"]?.stringValue,
                update["message_id"]?.stringValue
            ) ?? UUID().uuidString
            return (
                sessionKey,
                .rawOutput(
                    RawOutputEvent(
                        id: "acp/\(sessionKey)/user/\(eventID)",
                        text: "You: \(text)",
                        hookEvent: method
                    )
                )
            )
        }

        if kind.contains("agent_message") || kind.contains("agent_thought") {
            let text = sessionUpdateText(from: update)
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
                fallback: kind
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
        genuiEnabled: Bool,
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
            let turnID = firstNonEmpty(
                root["turnId"]?.stringValue,
                root["turn"]?.dictValue?["id"]?.stringValue
            )
            let eventID = reasoningEventID(
                protocolPrefix: "codex",
                sessionKey: sessionKey,
                primaryID: turnID == nil ? firstNonEmpty(
                    root["itemId"]?.stringValue,
                    root["item_id"]?.stringValue,
                    root["item"]?.dictValue?["id"]?.stringValue
                ) : nil,
                turnID: turnID,
                fallback: "agentMessage"
            )
            return (sessionKey, .reasoning(ReasoningEvent(id: eventID, text: delta, isThinking: false)))

        case "item/started", "item/completed":
            guard let item = root["item"]?.dictValue else {
                return (sessionKey, .rawOutput(RawOutputEvent(text: method, hookEvent: method)))
            }
            let itemType = item["type"]?.stringValue ?? "item"
            let normalizedItemType = itemType
                .replacingOccurrences(of: "-", with: "_")
                .lowercased()

            if normalizedItemType == "contextcompaction" || normalizedItemType == "context_compaction" {
                return nil
            }

            if !genuiEnabled && looksLikeGenUIPayload(item) {
                return (
                    sessionKey,
                    .rawOutput(
                        RawOutputEvent(
                            text: "GenUI payload received (disabled)",
                            hookEvent: method
                        )
                    )
                )
            }

            if let event = parseGenUIEvent(
                payload: item,
                protocolPrefix: "codex",
                sessionKey: sessionKey,
                fallbackID: firstNonEmpty(item["id"]?.stringValue, root["itemId"]?.stringValue),
                fallbackTitle: "Codex GenUI"
            ) {
                return (sessionKey, .genUI(event))
            }

            if normalizedItemType == "usermessage" || normalizedItemType == "user_message" {
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

            if normalizedItemType == "agentmessage" || normalizedItemType == "agent_message" {
                let text = agentMessageText(from: item)
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

            if normalizedItemType == "commandexecution" || normalizedItemType == "command_execution" {
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

            if normalizedItemType == "filechange" || normalizedItemType == "file_change" {
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

            if normalizedItemType == "mcptoolcall" || normalizedItemType == "mcp_tool_call"
                || normalizedItemType == "collabtoolcall" || normalizedItemType == "collab_tool_call" {
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
                .rawOutput(
                    RawOutputEvent(
                        id: toolEventID(
                            protocolPrefix: "codex",
                            sessionKey: sessionKey,
                            primaryID: firstNonEmpty(
                                item["id"]?.stringValue,
                                root["itemId"]?.stringValue
                            ),
                            fallback: "item/\(itemType)"
                        ),
                        text: "Codex item: \(itemType)",
                        hookEvent: method
                    )
                )
            )

        case "turn/started", "turn/completed", "thread/started", "thread/status/changed", "thread/tokenUsage/updated":
            return nil

        case "genui/update", "gen_ui/update":
            if !genuiEnabled {
                return (
                    sessionKey,
                    .rawOutput(
                        RawOutputEvent(
                            text: "GenUI update received (disabled)",
                            hookEvent: method
                        )
                    )
                )
            }
            if let event = parseGenUIEvent(
                payload: root,
                protocolPrefix: "codex",
                sessionKey: sessionKey,
                fallbackID: firstNonEmpty(root["id"]?.stringValue, root["requestId"]?.stringValue),
                fallbackTitle: "GenUI"
            ) {
                return (sessionKey, .genUI(event))
            }
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

    private static func sessionUpdateText(from update: [String: AnyCodable]) -> String? {
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
                if let s = entry.stringValue, !s.isEmpty { return s }
                guard let dict = entry.dictValue else { return nil }
                if let text = dict["text"]?.stringValue, !text.isEmpty { return text }
                if let nested = dict["content"]?.dictValue?["text"]?.stringValue, !nested.isEmpty {
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
            if !compact.isEmpty { return compact }
        }

        return nil
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

    private static func agentMessageText(from item: [String: AnyCodable]) -> String {
        if let text = item["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        if let content = item["content"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }
        if let entries = item["content"]?.arrayValue {
            let parts = entries.compactMap { entry -> String? in
                if let text = entry.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
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

    private static func parseGenUIEvent(
        payload: [String: AnyCodable],
        protocolPrefix: String,
        sessionKey: String,
        fallbackID: String?,
        fallbackTitle: String
    ) -> GenUIEvent? {
        let explicit = payload["genUI"]?.dictValue
            ?? payload["gen_ui"]?.dictValue
            ?? payload["surfaceSpec"]?.dictValue
            ?? payload["surface_spec"]?.dictValue
        let marker = payload["kind"]?.stringValue
            ?? payload["type"]?.stringValue
            ?? payload["sessionUpdate"]?.stringValue

        guard explicit != nil || marker?.localizedCaseInsensitiveContains("genui") == true else {
            return nil
        }

        let ui = explicit ?? payload
        let schemaVersion = normalizedSchemaVersion(from: ui)
        guard schemaVersion == "v0" else { return nil }

        let identifier = firstNonEmpty(
            ui["id"]?.stringValue,
            ui["surfaceId"]?.stringValue,
            fallbackID
        ) ?? UUID().uuidString
        let title = firstNonEmpty(
            ui["title"]?.stringValue,
            ui["name"]?.stringValue,
            marker,
            fallbackTitle
        ) ?? fallbackTitle
        let body = firstNonEmpty(
            ui["text"]?.stringValue,
            ui["body"]?.stringValue,
            ui["description"]?.stringValue,
            compactJSONString(from: ui)
        ) ?? ""
        guard body.count <= 16_000 else { return nil }

        let actionLabel = firstNonEmpty(
            ui["actionLabel"]?.stringValue,
            ui["action"]?.dictValue?["label"]?.stringValue,
            ui["primaryAction"]?.dictValue?["label"]?.stringValue
        )
        let actionPayload = ui["action"]?.dictValue
            ?? ui["primaryAction"]?.dictValue
            ?? [:]
        let modeRaw = firstNonEmpty(
            ui["mode"]?.stringValue,
            ui["updateMode"]?.stringValue,
            ui["update_mode"]?.stringValue
        )?.lowercased()
        let updateMode: GenUIEvent.UpdateMode = (modeRaw == "patch") ? .patch : .snapshot

        return GenUIEvent(
            id: "\(protocolPrefix)/\(sessionKey)/genui/\(identifier)",
            schemaVersion: schemaVersion,
            mode: updateMode,
            title: title,
            body: body,
            actionLabel: actionLabel,
            actionPayload: actionPayload
        )
    }

    private static func looksLikeGenUIPayload(_ payload: [String: AnyCodable]) -> Bool {
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
        )?.lowercased() ?? ""
        return marker.contains("genui")
    }

    private static func normalizedSchemaVersion(from payload: [String: AnyCodable]) -> String {
        if let text = firstNonEmpty(
            payload["schemaVersion"]?.stringValue,
            payload["schema_version"]?.stringValue,
            payload["version"]?.stringValue
        )?.lowercased() {
            if text == "0" || text == "v0" {
                return "v0"
            }
            return text
        }
        if let number = payload["schemaVersion"]?.intValue ?? payload["version"]?.intValue {
            return number == 0 ? "v0" : "\(number)"
        }
        return "v0"
    }
}
