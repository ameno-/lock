// AppModel.swift — @Observable root model: gateway connection + promoted session
import SwiftUI

@Observable
@MainActor
public final class AppModel {
    public struct GenUIParseTelemetry: Sendable {
        public fileprivate(set) var parsed: Int = 0
        public fileprivate(set) var parseIgnored: Int = 0
        public fileprivate(set) var embeddedParsed: Int = 0
    }

    // MARK: - Sub-models
    public let settings = ACSettingsStore()
    public let connection: ACGatewayConnection
    public let transport: ACSessionTransport
    public let eventStore = AgentEventStore()
    private let genUIPersistence = GenUIPersistenceStore()
    private var pendingGenUIActionsByID: [String: PendingGenUIActionEnvelope] = [:]
    public private(set) var genUIParseTelemetry = GenUIParseTelemetry()

    public var activeGenUIActionCallbackDiagnostic: ACSessionTransport.GenUIActionCallbackDiagnostic {
        transport.activeGenUIActionCallbackDiagnostic
    }

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
        restorePersistedGenUIState()
    }

    // MARK: - Lifecycle

    public func start() {
        transport.resetConnectionLifecycle()
        connection.connect { [weak self] message in
            self?.handleMessage(message)
        }
    }

    public func stop() {
        persistGenUIStateNow()
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
                implicitGenUIFromTextEnabled: settings.implicitGenUIFromTextEnabled,
                fallbackSessionKey: promotedSessionKey
            ) {
                eventStore.ingest(event: mapped.event, sessionKey: mapped.sessionKey)
                recordGenUIParseTelemetry(for: mapped.event)
                if case .genUI = mapped.event {
                    persistGenUIStateNow()
                }
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

    // MARK: - GenUI persistence + recovery

    func enqueuePendingGenUIAction(sessionKey: String, event: GenUIEvent) -> String {
        let id = pendingGenUIActionID(sessionKey: sessionKey, event: event)
        let existing = pendingGenUIActionsByID[id]
        pendingGenUIActionsByID[id] = PendingGenUIActionEnvelope(
            id: id,
            sessionKey: sessionKey,
            event: event,
            enqueuedAt: existing?.enqueuedAt ?? .now,
            attemptCount: existing?.attemptCount ?? 0,
            lastAttemptAt: existing?.lastAttemptAt,
            lastError: existing?.lastError
        )
        persistGenUIStateNow()
        return id
    }

    func markPendingGenUIActionAttempt(id: String) {
        guard var pending = pendingGenUIActionsByID[id] else { return }
        pending.attemptCount += 1
        pending.lastAttemptAt = .now
        pending.lastError = nil
        pendingGenUIActionsByID[id] = pending
        persistGenUIStateNow()
    }

    func markPendingGenUIActionCompleted(id: String) {
        pendingGenUIActionsByID.removeValue(forKey: id)
        persistGenUIStateNow()
    }

    func markPendingGenUIActionFailed(id: String, errorMessage: String) {
        guard var pending = pendingGenUIActionsByID[id] else { return }
        pending.lastError = errorMessage
        pendingGenUIActionsByID[id] = pending
        persistGenUIStateNow()
    }

    func pendingGenUIActions(for sessionKey: String) -> [PendingGenUIActionEnvelope] {
        pendingGenUIActionsByID.values
            .filter { $0.sessionKey == sessionKey }
            .sorted { lhs, rhs in
                if lhs.enqueuedAt != rhs.enqueuedAt {
                    return lhs.enqueuedAt < rhs.enqueuedAt
                }
                return lhs.id < rhs.id
            }
    }

    func persistGenUIStateNow() {
        let snapshot = GenUIPersistenceSnapshot(
            surfacesBySession: eventStore.exportGenUISurfacesBySession(),
            pendingActions: pendingGenUIActionsByID.values.sorted { lhs, rhs in
                if lhs.enqueuedAt != rhs.enqueuedAt {
                    return lhs.enqueuedAt < rhs.enqueuedAt
                }
                return lhs.id < rhs.id
            }
        )
        genUIPersistence.save(snapshot)
    }

    private func restorePersistedGenUIState() {
        let snapshot = genUIPersistence.load()
        eventStore.restoreGenUISurfacesBySession(snapshot.surfacesBySession)
        pendingGenUIActionsByID = Dictionary(
            uniqueKeysWithValues: snapshot.pendingActions.map { ($0.id, $0) }
        )
    }

    private func pendingGenUIActionID(sessionKey: String, event: GenUIEvent) -> String {
        let actionID = event.actionPayload["actionId"]?.stringValue
            ?? event.actionPayload["action_id"]?.stringValue
            ?? event.actionLabel?
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
            ?? "action"
        let correlation = event.correlationID ?? "none"
        return "\(sessionKey)|\(event.surfaceID)|\(actionID)|\(event.revision)|\(correlation)"
    }

    private func recordGenUIParseTelemetry(for event: CanvasEvent) {
        var telemetry = genUIParseTelemetry
        var didMutate = false
        switch event {
        case .genUI(let genUIEvent):
            telemetry.parsed += 1
            didMutate = true
            if genUIEvent.contextPayload["__sourceText"] != nil,
               genUIEvent.contextPayload["__implicitFromText"]?.boolValue != true {
                telemetry.embeddedParsed += 1
            }
        case .rawOutput(let rawEvent):
            if rawEvent.text.contains("GenUI payload ignored") {
                telemetry.parseIgnored += 1
                didMutate = true
            }
        default:
            break
        }
        if didMutate {
            genUIParseTelemetry = telemetry
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
        implicitGenUIFromTextEnabled: Bool = true,
        fallbackSessionKey: String?
    ) -> (sessionKey: String, event: CanvasEvent)? {
        switch protocolMode {
        case .acp:
            return mapACP(
                method: method,
                params: params,
                genuiEnabled: genuiEnabled,
                implicitGenUIFromTextEnabled: implicitGenUIFromTextEnabled,
                fallbackSessionKey: fallbackSessionKey
            )
        case .codex:
            return mapCodex(
                method: method,
                params: params,
                genuiEnabled: genuiEnabled,
                implicitGenUIFromTextEnabled: implicitGenUIFromTextEnabled,
                fallbackSessionKey: fallbackSessionKey
            )
        }
    }

    private static func mapACP(
        method: String,
        params: [String: AnyCodable]?,
        genuiEnabled: Bool,
        implicitGenUIFromTextEnabled _: Bool,
        fallbackSessionKey: String?
    ) -> (sessionKey: String, event: CanvasEvent)? {
        guard method == "session/update" else { return nil }
        let parsed = ACPProtocolParser.parseSessionUpdate(
            params: params,
            fallbackSessionID: fallbackSessionKey
        )

        if !genuiEnabled && parsed.type == .genUI {
            return (
                parsed.sessionID,
                .rawOutput(
                    RawOutputEvent(
                        text: "GenUI payload received (disabled)",
                        hookEvent: method
                    )
                )
            )
        }

        switch parseGenUIEvent(
            payload: parsed.update,
            protocolPrefix: "acp",
            sessionKey: parsed.sessionID,
            fallbackID: firstNonEmpty(
                parsed.update["id"]?.stringValue,
                parsed.root["requestId"]?.stringValue
            ),
            fallbackTitle: "ACP GenUI"
        ) {
        case .event(let event):
            return (parsed.sessionID, .genUI(event))
        case .invalid(let reason):
            return (
                parsed.sessionID,
                .rawOutput(
                    RawOutputEvent(
                        text: "GenUI payload ignored (\(reason))",
                        hookEvent: method
                    )
                )
            )
        case .notGenUI:
            break
        }

        switch parsed.type {
        case .sessionInfo:
            return nil

        case .toolCallUpdate:
            let status = toolStatus(from: parsed, default: .done)
            let toolID = toolEventID(
                protocolPrefix: "acp",
                sessionKey: parsed.sessionID,
                primaryID: parsed.toolCallID,
                fallback: parsed.toolName
            )
            return (
                parsed.sessionID,
                .toolUse(
                    ToolUseEvent(
                        id: toolID,
                        toolName: parsed.toolName,
                        phase: status == .running ? .start : .result,
                        input: "",
                        result: parsed.toolResult,
                        status: status
                    )
                )
            )

        case .toolCall:
            let status = toolStatus(from: parsed, default: .running)
            let toolID = toolEventID(
                protocolPrefix: "acp",
                sessionKey: parsed.sessionID,
                primaryID: parsed.toolCallID,
                fallback: parsed.toolName
            )
            return (
                parsed.sessionID,
                .toolUse(
                    ToolUseEvent(
                        id: toolID,
                        toolName: parsed.toolName,
                        phase: status == .running ? .start : .result,
                        input: parsed.toolInput,
                        result: status == .running ? nil : parsed.toolResult,
                        status: status
                    )
                )
            )

        case .userMessage:
            guard !parsed.text.isEmpty else { return nil }
            let eventID = parsed.updateID ?? UUID().uuidString
            return (
                parsed.sessionID,
                .rawOutput(
                    RawOutputEvent(
                        id: "acp/\(parsed.sessionID)/user/\(eventID)",
                        text: "You: \(parsed.text)",
                        hookEvent: method
                    )
                )
            )

        case .agentMessage, .agentThought:
            guard !parsed.text.isEmpty else { return nil }
            let eventID = reasoningEventID(
                protocolPrefix: "acp",
                sessionKey: parsed.sessionID,
                primaryID: parsed.updateID,
                turnID: parsed.turnID,
                fallback: parsed.rawKind
            )
            return (
                parsed.sessionID,
                .reasoning(
                    ReasoningEvent(
                        id: eventID,
                        text: parsed.text,
                        isThinking: parsed.type == .agentThought
                    )
                )
            )

        case .genUI:
            return nil

        case .unknown(let kind):
            return (
                parsed.sessionID,
                .rawOutput(RawOutputEvent(text: "ACP \(kind)", hookEvent: method))
            )
        }
    }

    private static func mapCodex(
        method: String,
        params: [String: AnyCodable]?,
        genuiEnabled: Bool,
        implicitGenUIFromTextEnabled: Bool,
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
            let parsedItem = CodexProtocolParser.parseItem(
                from: item,
                fallbackTurnID: firstNonEmpty(
                    root["turnId"]?.stringValue,
                    root["turn"]?.dictValue?["id"]?.stringValue
                )
            )

            if parsedItem.type == .contextCompaction {
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

            let genuiOutcome = parseGenUIEvent(
                payload: item,
                protocolPrefix: "codex",
                sessionKey: sessionKey,
                fallbackID: firstNonEmpty(item["id"]?.stringValue, root["itemId"]?.stringValue),
                fallbackTitle: "Codex GenUI"
            )

            if case .event(let event) = genuiOutcome {
                return (sessionKey, .genUI(event))
            }
            if case .invalid(let reason) = genuiOutcome {
                return (
                    sessionKey,
                    .rawOutput(
                        RawOutputEvent(
                            text: "GenUI payload ignored (\(reason))",
                            hookEvent: method
                        )
                    )
                )
            }

            switch parsedItem.type {
            case .userMessage:
                guard !parsedItem.text.isEmpty else { return nil }
                let itemID = firstNonEmpty(
                    parsedItem.id,
                    root["itemId"]?.stringValue
                ) ?? UUID().uuidString
                return (
                    sessionKey,
                    .rawOutput(
                        RawOutputEvent(
                            id: "codex/\(sessionKey)/user/\(itemID)",
                            text: "You: \(parsedItem.text)",
                            hookEvent: method
                        )
                    )
                )

            case .agentMessage:
                guard !parsedItem.text.isEmpty else { return nil }
                switch parseEmbeddedGenUIEvent(
                    from: parsedItem.text,
                    protocolPrefix: "codex",
                    sessionKey: sessionKey,
                    fallbackID: firstNonEmpty(
                        parsedItem.id,
                        root["itemId"]?.stringValue,
                        root["item"]?.dictValue?["id"]?.stringValue
                    ),
                    fallbackTitle: "Codex GenUI"
                ) {
                case .event(let event):
                    return (sessionKey, .genUI(event))
                case .invalid(let reason):
                    return (
                        sessionKey,
                        .rawOutput(
                            RawOutputEvent(
                                text: "GenUI payload ignored (\(reason))",
                                hookEvent: method
                            )
                        )
                    )
                case .notGenUI:
                    break
                }
                if genuiEnabled && implicitGenUIFromTextEnabled {
                    switch synthesizeImplicitGenUIEvent(
                        from: parsedItem.text,
                        protocolPrefix: "codex",
                        sessionKey: sessionKey,
                        fallbackID: firstNonEmpty(
                            parsedItem.id,
                            root["itemId"]?.stringValue,
                            root["item"]?.dictValue?["id"]?.stringValue
                        ),
                        fallbackTitle: "Codex GenUI"
                    ) {
                    case .event(let event):
                        return (sessionKey, .genUI(event))
                    case .invalid:
                        break
                    case .notGenUI:
                        break
                    }
                }
                let turnID = firstNonEmpty(
                    parsedItem.turnID,
                    root["turnId"]?.stringValue,
                    root["turn"]?.dictValue?["id"]?.stringValue
                )
                let eventID = reasoningEventID(
                    protocolPrefix: "codex",
                    sessionKey: sessionKey,
                    primaryID: turnID == nil ? firstNonEmpty(
                        parsedItem.id,
                        root["itemId"]?.stringValue,
                        root["item"]?.dictValue?["id"]?.stringValue
                    ) : nil,
                    turnID: turnID,
                    fallback: "agentMessage"
                )
                return (sessionKey, .reasoning(ReasoningEvent(id: eventID, text: parsedItem.text, isThinking: false)))

            case .reasoning:
                guard !parsedItem.text.isEmpty else { return nil }
                let turnID = firstNonEmpty(
                    parsedItem.turnID,
                    root["turnId"]?.stringValue,
                    root["turn"]?.dictValue?["id"]?.stringValue
                )
                let eventID = reasoningEventID(
                    protocolPrefix: "codex",
                    sessionKey: sessionKey,
                    primaryID: turnID == nil ? firstNonEmpty(
                        parsedItem.id,
                        root["itemId"]?.stringValue,
                        root["item"]?.dictValue?["id"]?.stringValue
                    ) : nil,
                    turnID: turnID,
                    fallback: "reasoning"
                )
                return (sessionKey, .reasoning(ReasoningEvent(id: eventID, text: parsedItem.text, isThinking: true)))

            case .commandExecution:
                let statusRaw = parsedItem.status ?? ""
                let status: ToolStatus = switch statusRaw {
                case "failed", "declined": .error
                case "completed": .done
                default: method == "item/completed" ? .done : .running
                }
                let toolID = toolEventID(
                    protocolPrefix: "codex",
                    sessionKey: sessionKey,
                    primaryID: firstNonEmpty(
                        parsedItem.id,
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
                            input: parsedItem.commandText,
                            result: parsedItem.commandOutput,
                            status: status
                        )
                    )
                )

            case .fileChange:
                guard let change = parsedItem.fileChanges.first else { return nil }
                let fileID = toolEventID(
                    protocolPrefix: "codex",
                    sessionKey: sessionKey,
                    primaryID: firstNonEmpty(
                        parsedItem.id,
                        root["itemId"]?.stringValue
                    ),
                    fallback: "file/\(change.path)"
                )
                return (
                    sessionKey,
                    .fileEdit(
                        FileEditEvent(
                            id: fileID,
                            filePath: change.path,
                            operation: fileOperation(from: change.kind)
                        )
                    )
                )

            case .mcpToolCall, .collabToolCall:
                let toolName = parsedItem.toolName ?? "tool"
                let statusRaw = parsedItem.status ?? ""
                let status: ToolStatus = switch statusRaw {
                case "failed": .error
                case "completed": .done
                default: .running
                }
                let toolID = toolEventID(
                    protocolPrefix: "codex",
                    sessionKey: sessionKey,
                    primaryID: firstNonEmpty(
                        parsedItem.id,
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
                            input: parsedItem.toolArgumentsJSON,
                            result: parsedItem.toolResult,
                            status: status
                        )
                    )
                )

            case .contextCompaction:
                return nil

            case .unknown(let rawType):
                return (
                    sessionKey,
                    .rawOutput(
                        RawOutputEvent(
                            id: toolEventID(
                                protocolPrefix: "codex",
                                sessionKey: sessionKey,
                                primaryID: firstNonEmpty(
                                    parsedItem.id,
                                    root["itemId"]?.stringValue
                                ),
                                fallback: "item/\(rawType)"
                            ),
                            text: "Codex item: \(rawType)",
                            hookEvent: method
                        )
                    )
                )
            }

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
            switch parseGenUIEvent(
                payload: root,
                protocolPrefix: "codex",
                sessionKey: sessionKey,
                fallbackID: firstNonEmpty(root["id"]?.stringValue, root["requestId"]?.stringValue),
                fallbackTitle: "GenUI"
            ) {
            case .event(let event):
                return (sessionKey, .genUI(event))
            case .invalid(let reason):
                return (
                    sessionKey,
                    .rawOutput(
                        RawOutputEvent(
                            text: "GenUI update ignored (\(reason))",
                            hookEvent: method
                        )
                    )
                )
            case .notGenUI:
                return nil
            }

        default:
            return nil
        }
    }

    private static func toolStatus(from parsed: ACPUpdateContext, default fallback: ToolStatus) -> ToolStatus {
        guard let statusRaw = parsed.toolStatus else {
            return parsed.isError ? .error : fallback
        }
        switch statusRaw {
        case "error", "failed", "cancelled", "canceled":
            return .error
        case "completed", "done", "success":
            return .done
        case "pending", "in_progress", "running", "started":
            return .running
        default:
            return parsed.isError ? .error : fallback
        }
    }

    private static func fileOperation(from kind: String) -> FileOperation {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "delete", "deleted":
            return .delete
        case "create", "created", "add", "added":
            return .write
        default:
            return .edit
        }
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

    private enum GenUIParseResult {
        case event(GenUIEvent)
        case invalid(String)
        case notGenUI
    }

    private static func parseGenUIEvent(
        payload: [String: AnyCodable],
        protocolPrefix: String,
        sessionKey: String,
        fallbackID: String?,
        fallbackTitle: String
    ) -> GenUIParseResult {
        let explicit = payload["genUI"]?.dictValue
            ?? payload["gen_ui"]?.dictValue
            ?? payload["surfaceSpec"]?.dictValue
            ?? payload["surface_spec"]?.dictValue
        let marker = payload["kind"]?.stringValue
            ?? payload["type"]?.stringValue
            ?? payload["sessionUpdate"]?.stringValue

        guard explicit != nil || marker?.localizedCaseInsensitiveContains("genui") == true else {
            return .notGenUI
        }

        let ui = explicit ?? payload
        let schemaVersion = normalizedSchemaVersion(from: ui)
        guard schemaVersion == "v0" else { return .invalid("unsupported schema \(schemaVersion)") }

        let surfaceID = firstNonEmpty(
            ui["id"]?.stringValue,
            ui["surfaceId"]?.stringValue,
            ui["surface_id"]?.stringValue,
            fallbackID
        ) ?? UUID().uuidString
        let revision = normalizedRevision(from: ui)
        let correlationID = firstNonEmpty(
            ui["correlationId"]?.stringValue,
            ui["correlation_id"]?.stringValue,
            ui["requestId"]?.stringValue,
            payload["correlationId"]?.stringValue,
            payload["requestId"]?.stringValue
        )
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
        guard body.count <= 16_000 else { return .invalid("body too large") }

        let actionLabel = firstNonEmpty(
            ui["actionLabel"]?.stringValue,
            ui["action"]?.dictValue?["label"]?.stringValue,
            ui["primaryAction"]?.dictValue?["label"]?.stringValue
        )
        let actionPayload = ui["action"]?.dictValue
            ?? ui["primaryAction"]?.dictValue
            ?? [:]
        let contextPayload = ui["context"]?.dictValue
            ?? ui["callbackContext"]?.dictValue
            ?? ui["callback_context"]?.dictValue
            ?? payload["context"]?.dictValue
            ?? [:]
        let modeRaw = firstNonEmpty(
            ui["mode"]?.stringValue,
            ui["updateMode"]?.stringValue,
            ui["update_mode"]?.stringValue
        )?.lowercased()
        let updateMode: GenUIEvent.UpdateMode = (modeRaw == "patch") ? .patch : .snapshot

        let event = GenUIEvent(
            id: "\(protocolPrefix)/\(sessionKey)/genui/\(surfaceID)",
            schemaVersion: schemaVersion,
            mode: updateMode,
            surfaceID: surfaceID,
            revision: revision,
            correlationID: correlationID,
            title: title,
            body: body,
            surfacePayload: ui,
            contextPayload: contextPayload,
            actionLabel: actionLabel,
            actionPayload: actionPayload
        )
        return .event(event)
    }

    private static func looksLikeGenUIPayload(_ payload: [String: AnyCodable]) -> Bool {
        ACPProtocolParser.looksLikeGenUIPayload(payload)
    }

    private static func parseEmbeddedGenUIEvent(
        from text: String,
        protocolPrefix: String,
        sessionKey: String,
        fallbackID: String?,
        fallbackTitle: String
    ) -> GenUIParseResult {
        guard let jsonPayload = extractEmbeddedGenUIPayloadJSON(from: text) else {
            return .notGenUI
        }
        guard let data = jsonPayload.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = raw as? [String: Any]
        else {
            return .invalid("invalid embedded GenUI JSON")
        }
        var embeddedPayload = anyCodableDictionary(from: dictionary)
        mergeEmbeddedSourceText(text, into: &embeddedPayload)
        let wrapped: [String: AnyCodable] = [
            "kind": AnyCodable("genui/embed"),
            "genUI": AnyCodable(embeddedPayload)
        ]
        return parseGenUIEvent(
            payload: wrapped,
            protocolPrefix: protocolPrefix,
            sessionKey: sessionKey,
            fallbackID: fallbackID,
            fallbackTitle: fallbackTitle
        )
    }

    private struct ChecklistSignal {
        struct Item {
            let label: String
            let done: Bool
        }

        let total: Int
        let completed: Int
        let percent: Int
        let body: String
        let items: [Item]
    }

    private struct ProgressSignal {
        let percent: Int
        let body: String
    }

    private static func synthesizeImplicitGenUIEvent(
        from sourceText: String,
        protocolPrefix: String,
        sessionKey: String,
        fallbackID: String?,
        fallbackTitle: String
    ) -> GenUIParseResult {
        let heuristicText = textForImplicitGenUIHeuristics(from: sourceText)

        if let checklist = parseChecklistSignal(from: heuristicText) {
            let context: [String: AnyCodable] = [
                "__sourceText": AnyCodable(sourceText),
                "__implicitFromText": AnyCodable(true),
                "__implicitHeuristic": AnyCodable("checklist"),
                "checklistTotal": AnyCodable(checklist.total),
                "checklistCompleted": AnyCodable(checklist.completed),
                "progressPercent": AnyCodable(checklist.percent)
            ]
            let checklistItems = checklist.items.map { item in
                AnyCodable([
                    "id": AnyCodable(item.label.lowercased().replacingOccurrences(of: " ", with: "-")),
                    "label": AnyCodable(item.label),
                    "done": AnyCodable(item.done),
                ])
            }
            let checklistComponents: [AnyCodable] = [
                AnyCodable([
                    "id": AnyCodable("implicit-checklist"),
                    "type": AnyCodable("checklist"),
                    "title": AnyCodable("Checklist"),
                    "items": AnyCodable(checklistItems),
                ]),
                AnyCodable([
                    "id": AnyCodable("implicit-progress"),
                    "type": AnyCodable("progress"),
                    "label": AnyCodable("Completion"),
                    "value": AnyCodable(Double(checklist.percent) / 100.0),
                ]),
            ]
            let payload: [String: AnyCodable] = [
                "kind": AnyCodable("genui/implicit"),
                "genUI": AnyCodable([
                    "id": AnyCodable(deterministicImplicitSurfaceID(kind: "checklist")),
                    "schemaVersion": AnyCodable("v0"),
                    "mode": AnyCodable("snapshot"),
                    "title": AnyCodable("Checklist \(checklist.completed)/\(checklist.total)"),
                    "text": AnyCodable(truncated(checklist.body, maxLength: 4_000)),
                    "context": AnyCodable(context),
                    "components": AnyCodable(checklistComponents),
                ])
            ]
            if case let .event(event) = parseGenUIEvent(
                payload: payload,
                protocolPrefix: protocolPrefix,
                sessionKey: sessionKey,
                fallbackID: fallbackID,
                fallbackTitle: fallbackTitle
            ) {
                return .event(event)
            }
            return .notGenUI
        }

        if let progress = parseProgressSignal(from: heuristicText) {
            let context: [String: AnyCodable] = [
                "__sourceText": AnyCodable(sourceText),
                "__implicitFromText": AnyCodable(true),
                "__implicitHeuristic": AnyCodable("progress"),
                "progressPercent": AnyCodable(progress.percent)
            ]
            let progressComponents: [AnyCodable] = [
                AnyCodable([
                    "id": AnyCodable("implicit-progress"),
                    "type": AnyCodable("progress"),
                    "label": AnyCodable("Progress"),
                    "value": AnyCodable(Double(progress.percent) / 100.0),
                ]),
                AnyCodable([
                    "id": AnyCodable("implicit-text"),
                    "type": AnyCodable("text"),
                    "text": AnyCodable(truncated(progress.body, maxLength: 500)),
                ]),
            ]
            let payload: [String: AnyCodable] = [
                "kind": AnyCodable("genui/implicit"),
                "genUI": AnyCodable([
                    "id": AnyCodable(deterministicImplicitSurfaceID(kind: "progress")),
                    "schemaVersion": AnyCodable("v0"),
                    "mode": AnyCodable("snapshot"),
                    "title": AnyCodable("Progress \(progress.percent)%"),
                    "text": AnyCodable(truncated(progress.body, maxLength: 4_000)),
                    "context": AnyCodable(context),
                    "components": AnyCodable(progressComponents),
                ])
            ]
            if case let .event(event) = parseGenUIEvent(
                payload: payload,
                protocolPrefix: protocolPrefix,
                sessionKey: sessionKey,
                fallbackID: fallbackID,
                fallbackTitle: fallbackTitle
            ) {
                return .event(event)
            }
        }

        return .notGenUI
    }

    private static func textForImplicitGenUIHeuristics(from text: String) -> String {
        let withoutFenced = replacingRegexMatches(
            pattern: "```[\\s\\S]*?```",
            in: text,
            with: "\n"
        )
        return replacingRegexMatches(
            pattern: "`[^`]*`",
            in: withoutFenced,
            with: " "
        )
    }

    private static func parseChecklistSignal(from text: String) -> ChecklistSignal? {
        guard let regex = try? NSRegularExpression(
            pattern: "(?m)^\\s*[-*]\\s*\\[([ xX])\\]\\s+(.+?)\\s*$"
        ) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        var lines: [String] = []
        var items: [ChecklistSignal.Item] = []
        var completed = 0
        lines.reserveCapacity(matches.count)
        items.reserveCapacity(matches.count)

        for match in matches {
            guard match.numberOfRanges > 2,
                  let markerRange = Range(match.range(at: 1), in: text),
                  let itemRange = Range(match.range(at: 2), in: text)
            else {
                continue
            }
            let marker = text[markerRange]
            let itemText = text[itemRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !itemText.isEmpty else { continue }
            let isCompleted = marker.lowercased() == "x"
            if isCompleted {
                completed += 1
            }
            lines.append("- [\(isCompleted ? "x" : " ")] \(itemText)")
            items.append(.init(label: itemText, done: isCompleted))
        }

        guard !lines.isEmpty else { return nil }
        let total = lines.count
        let percent = Int((Double(completed) / Double(total) * 100).rounded())
        return ChecklistSignal(
            total: total,
            completed: completed,
            percent: percent,
            body: lines.joined(separator: "\n"),
            items: items
        )
    }

    private static func parseProgressSignal(from text: String) -> ProgressSignal? {
        guard let regex = try? NSRegularExpression(
            pattern: "(\\d{1,3}(?:\\.\\d+)?)\\s*%"
        ) else {
            return nil
        }
        let nsText = text as NSString
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return nil }

        struct Candidate {
            let percent: Int
            let body: String
            let hasKeyword: Bool
        }

        let keywords = [
            "progress",
            "complete",
            "completed",
            "completion",
            "done",
            "remaining",
            "milestone"
        ]

        var candidates: [Candidate] = []
        for match in matches {
            guard match.numberOfRanges > 1,
                  let numberRange = Range(match.range(at: 1), in: text),
                  let number = Double(text[numberRange]),
                  number >= 0,
                  number <= 100
            else {
                continue
            }

            let percent = Int(number.rounded())
            let body = lineSnippet(
                containing: match.range(at: 0),
                in: text
            ) ?? "Progress update: \(percent)%"

            let start = max(0, match.range(at: 0).location - 32)
            let end = min(nsText.length, NSMaxRange(match.range(at: 0)) + 32)
            let window = nsText.substring(
                with: NSRange(location: start, length: max(0, end - start))
            ).lowercased()
            let hasKeyword = keywords.contains(where: window.contains)
            candidates.append(Candidate(percent: percent, body: body, hasKeyword: hasKeyword))
        }

        if let prioritized = candidates.first(where: { $0.hasKeyword }) {
            return ProgressSignal(percent: prioritized.percent, body: prioritized.body)
        }
        if candidates.count == 1, let only = candidates.first {
            return ProgressSignal(percent: only.percent, body: only.body)
        }
        return nil
    }

    private static func lineSnippet(containing range: NSRange, in text: String) -> String? {
        guard let swiftRange = Range(range, in: text) else { return nil }
        let lineStart = text[..<swiftRange.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) }
            ?? text.startIndex
        let lineEnd = text[swiftRange.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let line = text[lineStart..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    private static func deterministicImplicitSurfaceID(kind: String) -> String {
        let normalized = kind
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        return "implicit-\(normalized.isEmpty ? "assistant-message" : normalized)"
    }

    private static func replacingRegexMatches(
        pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: replacement)
    }

    private static func truncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<end]) + "..."
    }

    private static func mergeEmbeddedSourceText(
        _ sourceText: String,
        into payload: inout [String: AnyCodable]
    ) {
        if var context = payload["context"]?.dictValue {
            context["__sourceText"] = AnyCodable(sourceText)
            payload["context"] = AnyCodable(context)
            return
        }
        if var context = payload["callbackContext"]?.dictValue {
            context["__sourceText"] = AnyCodable(sourceText)
            payload["callbackContext"] = AnyCodable(context)
            return
        }
        if var context = payload["callback_context"]?.dictValue {
            context["__sourceText"] = AnyCodable(sourceText)
            payload["callback_context"] = AnyCodable(context)
            return
        }
        payload["context"] = AnyCodable([
            "__sourceText": AnyCodable(sourceText)
        ])
    }

    private static func extractEmbeddedGenUIPayloadJSON(from text: String) -> String? {
        if let fenced = firstRegexCapture(
            pattern: "```(?:genui|gen_ui)\\s*([\\s\\S]*?)```",
            in: text
        ) {
            return fenced
        }
        return firstRegexCapture(
            pattern: "<genui>([\\s\\S]*?)</genui>",
            in: text
        )
    }

    private static func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func anyCodableDictionary(from raw: [String: Any]) -> [String: AnyCodable] {
        var mapped: [String: AnyCodable] = [:]
        mapped.reserveCapacity(raw.count)
        for (key, value) in raw {
            mapped[key] = anyCodableValue(from: value)
        }
        return mapped
    }

    private static func anyCodableValue(from raw: Any) -> AnyCodable {
        switch raw {
        case let value as String:
            return AnyCodable(value)
        case let value as Bool:
            return AnyCodable(value)
        case let value as Int:
            return AnyCodable(value)
        case let value as Double:
            return AnyCodable(value)
        case let value as [String: Any]:
            return AnyCodable(anyCodableDictionary(from: value))
        case let value as [Any]:
            return AnyCodable(value.map(anyCodableValue(from:)))
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return AnyCodable(value.boolValue)
            }
            if value.doubleValue.rounded(.towardZero) == value.doubleValue {
                return AnyCodable(value.intValue)
            }
            return AnyCodable(value.doubleValue)
        default:
            return AnyCodable(String(describing: raw))
        }
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

    private static func normalizedRevision(from payload: [String: AnyCodable]) -> Int {
        if let revision = payload["revision"]?.intValue
            ?? payload["rev"]?.intValue
            ?? payload["sequence"]?.intValue
            ?? payload["updateRevision"]?.intValue
            ?? payload["update_revision"]?.intValue {
            return max(0, revision)
        }

        if let text = firstNonEmpty(
            payload["revision"]?.stringValue,
            payload["rev"]?.stringValue,
            payload["sequence"]?.stringValue,
            payload["updateRevision"]?.stringValue,
            payload["update_revision"]?.stringValue
        ),
        let revision = Int(text) {
            return max(0, revision)
        }

        return 0
    }
}
