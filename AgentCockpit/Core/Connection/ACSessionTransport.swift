// ACSessionTransport.swift — Typed request/response methods across legacy gateway, ACP, and Codex app-server
import Foundation

public enum ACApprovalDecision: String, CaseIterable, Sendable {
    case accept
    case acceptForSession
    case decline
    case cancel
}

public struct ACPendingApprovalRequest: Identifiable, Sendable {
    public let id: String
    public let method: String
    public let threadId: String?
    public let turnId: String?
    public let itemId: String?
    public let reason: String?
    public let command: String?
    public let cwd: String?
    public let grantRoot: String?
    public let receivedAt: Date
}

public struct ACUserInputOption: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let details: String?
    public let isOther: Bool
    public let isSecret: Bool
}

public struct ACUserInputQuestion: Identifiable, Sendable {
    public let id: String
    public let header: String
    public let prompt: String
    public let options: [ACUserInputOption]
    public let allowsMultipleSelections: Bool
}

public struct ACPendingUserInputRequest: Identifiable, Sendable {
    public let id: String
    public let method: String
    public let threadId: String?
    public let turnId: String?
    public let questions: [ACUserInputQuestion]
    public let receivedAt: Date
}

@Observable
@MainActor
public final class ACSessionTransport {
    public enum GenUIActionCallbackDiagnostic: Sendable, Equatable {
        case method(String)
        case notAdvertised

        public var value: String {
            switch self {
            case .method(let method):
                method
            case .notAdvertised:
                "not advertised"
            }
        }
    }

    private let connection: ACGatewayConnection
    private let settings: ACSettingsStore

    private var pendingJSONRequests: [String: CheckedContinuation<AnyCodable?, Error>] = [:]
    private var requestCounter = 0
    private var didInitializeJSONRPC = false
    private var serverAdvertisedMethods: Set<String> = []
    private var negotiatedGenUIActionMethodByProtocol: [ACServerProtocol: String] = [:]
    private var loadedACPSessionIDs: Set<String> = []
    private var loadedCodexThreadIDs: Set<String> = []
    private var acpSessionDirectories: [String: String] = [:]
    private var activeCodexTurnByThread: [String: String] = [:]
    public private(set) var pendingApprovalRequests: [ACPendingApprovalRequest] = []
    public private(set) var pendingUserInputRequests: [ACPendingUserInputRequest] = []

    public var activeGenUIActionCallbackDiagnostic: GenUIActionCallbackDiagnostic {
        let protocolMode = settings.serverProtocol
        guard let method = resolvedGenUIActionMethod(for: protocolMode) else {
            return .notAdvertised
        }
        return .method(method)
    }

    public init(connection: ACGatewayConnection, settings: ACSettingsStore) {
        self.connection = connection
        self.settings = settings
    }

    public func resetConnectionLifecycle() {
        didInitializeJSONRPC = false
        serverAdvertisedMethods.removeAll()
        negotiatedGenUIActionMethodByProtocol.removeAll()
        loadedACPSessionIDs.removeAll()
        loadedCodexThreadIDs.removeAll()
        acpSessionDirectories.removeAll()
        activeCodexTurnByThread.removeAll()
    }

    // Called by AppModel when a message arrives
    public func handleMessage(_ msg: ACServerMessage) {
        switch msg {
        case .jsonrpcResponse(let id, let result, let error):
            if let continuation = pendingJSONRequests.removeValue(forKey: id) {
                if let error {
                    continuation.resume(throwing: ACTransportError.serverError(error.code, error.message))
                } else {
                    continuation.resume(returning: result)
                }
            }

        case .jsonrpcNotification(let method, let params):
            trackCodexTurnLifecycle(method: method, params: params)

        default:
            break
        }
    }

    public func handleServerRequest(id: String, method: String, params: [String: AnyCodable]?) {
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            let root = params ?? [:]
            let approval = ACPendingApprovalRequest(
                id: id,
                method: method,
                threadId: root["threadId"]?.stringValue,
                turnId: root["turnId"]?.stringValue,
                itemId: root["itemId"]?.stringValue,
                reason: root["reason"]?.stringValue,
                command: commandText(from: root),
                cwd: root["cwd"]?.stringValue,
                grantRoot: root["grantRoot"]?.stringValue,
                receivedAt: .now
            )
            upsertApprovalRequest(approval)

        case "item/tool/requestUserInput", "tool/requestUserInput":
            let root = params ?? [:]
            let request = ACPendingUserInputRequest(
                id: id,
                method: method,
                threadId: root["threadId"]?.stringValue,
                turnId: root["turnId"]?.stringValue,
                questions: parseUserInputQuestions(from: root),
                receivedAt: .now
            )
            upsertUserInputRequest(request)

        default:
            let error = ACJSONRPCErrorPayload(code: -32601, message: "Method not handled in AgentCockpit")
            connection.send(ACJSONRPCResponseMessage(id: id, error: error))
        }
    }

    public func respondToApprovalRequest(id: String, decision: ACApprovalDecision) {
        let payload = AnyCodable(decision.rawValue)
        connection.send(ACJSONRPCResponseMessage(id: id, result: payload))
        pendingApprovalRequests.removeAll { $0.id == id }
    }

    public func submitUserInputRequest(id: String, answers: [String: [String]]) {
        var answersPayload: [String: AnyCodable] = [:]
        for (key, values) in answers {
            answersPayload[key] = AnyCodable(values.map { AnyCodable($0) })
        }
        let result: [String: AnyCodable] = [
            "answers": AnyCodable(answersPayload)
        ]
        connection.send(ACJSONRPCResponseMessage(id: id, result: AnyCodable(result)))
        pendingUserInputRequests.removeAll { $0.id == id }
    }

    public func dismissUserInputRequest(id: String) {
        let result: [String: AnyCodable] = [
            "answers": AnyCodable([String: AnyCodable]())
        ]
        connection.send(ACJSONRPCResponseMessage(id: id, result: AnyCodable(result)))
        pendingUserInputRequests.removeAll { $0.id == id }
    }

    // MARK: - Public request methods

    public func listSessions() async throws -> [ACSessionEntry] {
        switch settings.serverProtocol {
        case .acp:
            do {
                let result = try await requestJSON(method: "session/list")
                let sessions = parseACPSessions(from: result)
                cacheACPSessionDirectories(from: sessions)
                return sessions
            } catch ACTransportError.serverError(let code, _) where code == -32601 {
                do {
                    let fallback = try await requestJSON(method: "session/resume/list")
                    let sessions = parseACPSessions(from: fallback)
                    cacheACPSessionDirectories(from: sessions)
                    return sessions
                } catch ACTransportError.serverError(let fallbackCode, _) where fallbackCode == -32601 {
                    return []
                }
            }

        case .codex:
            let result = try await requestJSON(
                method: "thread/list",
                params: ["limit": AnyCodable(100)]
            )
            return parseCodexThreads(from: result)
        }
    }

    public func createSession() async throws -> ACSessionEntry? {
        switch settings.serverProtocol {
        case .acp:
            var params: [String: AnyCodable] = [:]
            if !settings.workingDirectory.isEmpty {
                params["cwd"] = AnyCodable(settings.workingDirectory)
            }
            do {
                let result = try await requestJSON(
                    method: "session/new",
                    params: params.isEmpty ? nil : params
                )
                let created = parseACPSession(from: result)
                if let created {
                    cacheACPSessionDirectories(from: [created])
                    loadedACPSessionIDs.insert(created.key)
                }
                return created
            } catch ACTransportError.serverError(let code, let message)
                where code == -32602 && settings.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                throw ACTransportError.serverError(
                    code,
                    "Server rejected session/new (\(message)). Set an absolute Working Dir in Settings for ACP servers like pi-acp."
                )
            }

        case .codex:
            var params: [String: AnyCodable] = [:]
            if !settings.workingDirectory.isEmpty {
                params["cwd"] = AnyCodable(settings.workingDirectory)
            }
            let result = try await requestJSON(
                method: "thread/start",
                params: params
            )
            let created = parseCodexThread(from: result)
            if let key = created?.key {
                loadedCodexThreadIDs.insert(key)
            }
            return created
        }
    }

    public func subscribe(sessionKey: String) async throws {
        switch settings.serverProtocol {
        case .acp:
            try await ensureACPSessionLoaded(sessionKey: sessionKey)

        case .codex:
            try await ensureCodexThreadResumed(sessionKey: sessionKey)
        }
    }

    public func send(sessionKey: String, text: String) async throws {
        switch settings.serverProtocol {
        case .acp:
            try await ensureACPSessionLoaded(sessionKey: sessionKey)
            let params: [String: AnyCodable] = [
                "sessionId": AnyCodable(sessionKey),
                "prompt": AnyCodable(text),
                "text": AnyCodable(text),
            ]
            _ = try await requestJSON(method: "session/prompt", params: params)

        case .codex:
            try await ensureCodexThreadResumed(sessionKey: sessionKey)
            let textItem: [String: AnyCodable] = [
                "type": AnyCodable("text"),
                "text": AnyCodable(text),
            ]
            let params: [String: AnyCodable] = [
                "threadId": AnyCodable(sessionKey),
                "input": AnyCodable([AnyCodable(textItem)]),
            ]
            _ = try await requestJSON(method: "turn/start", params: params)
        }
    }

    public func loadSessionContext(sessionKey: String) async throws -> [CanvasEvent] {
        switch settings.serverProtocol {
        case .acp:
            return try await loadACPHistory(sessionKey: sessionKey)

        case .codex:
            let result = try await requestJSON(
                method: "thread/read",
                params: [
                    "threadId": AnyCodable(sessionKey),
                    "includeTurns": AnyCodable(true),
                ]
            )
            return parseCodexHistory(from: result)
        }
    }

    public func cancel(sessionKey: String) async throws {
        switch settings.serverProtocol {
        case .acp:
            var params: [String: AnyCodable] = ["sessionId": AnyCodable(sessionKey)]
            if let cwd = resolvedACPCwd(for: sessionKey) {
                params["cwd"] = AnyCodable(cwd)
            }
            _ = try await requestJSON(method: "session/cancel", params: params)

        case .codex:
            try await ensureCodexThreadResumed(sessionKey: sessionKey)
            var params: [String: AnyCodable] = [
                "threadId": AnyCodable(sessionKey),
            ]
            if let turnID = activeCodexTurnByThread[sessionKey] {
                params["turnId"] = AnyCodable(turnID)
            }
            _ = try await requestJSON(method: "turn/interrupt", params: params)
        }
    }

    public func submitGenUIAction(sessionKey: String, event: GenUIEvent) async throws {
        var payload = try validatedGenUIActionPayload(from: event)
        payload["surfaceId"] = AnyCodable(event.surfaceID)
        payload["schemaVersion"] = AnyCodable(event.schemaVersion)
        payload["revision"] = AnyCodable(event.revision)
        payload["mode"] = AnyCodable(event.mode == .patch ? "patch" : "snapshot")
        if let correlationID = event.correlationID {
            payload["correlationId"] = AnyCodable(correlationID)
        }
        if payload["context"] == nil, !event.contextPayload.isEmpty {
            payload["context"] = AnyCodable(event.contextPayload)
        }

        switch settings.serverProtocol {
        case .acp:
            try await ensureACPSessionLoaded(sessionKey: sessionKey)
            payload["sessionId"] = AnyCodable(sessionKey)
            guard let method = resolvedGenUIActionMethod(for: .acp) else {
                throw ACTransportError.invalidRequest(
                    "Server does not advertise a GenUI action callback method for ACP."
                )
            }
            _ = try await requestJSON(method: method, params: payload)

        case .codex:
            try await ensureCodexThreadResumed(sessionKey: sessionKey)
            payload["threadId"] = AnyCodable(sessionKey)
            guard let method = resolvedGenUIActionMethod(for: .codex) else {
                throw ACTransportError.invalidRequest(
                    "Connected Codex server does not advertise GenUI action callbacks."
                )
            }
            _ = try await requestJSON(method: method, params: payload)
        }
    }

    public func promote(sessionKey: String) async throws {
        switch settings.serverProtocol {
        case .acp, .codex:
            break
        }
    }

    // MARK: - Internal request helpers

    private func requestJSON(method: String, params: [String: AnyCodable]? = nil) async throws -> AnyCodable? {
        try await ensureJSONRPCInitializedIfNeeded()
        return try await sendJSONRequest(method: method, params: params)
    }

    private func sendJSONRequest(
        method: String,
        params: [String: AnyCodable]? = nil,
        timeoutSeconds: UInt64 = 15
    ) async throws -> AnyCodable? {
        requestCounter += 1
        let id = "rpc-\(requestCounter)"
        let msg = ACJSONRPCRequestMessage(id: id, method: method, params: params)

        return try await withCheckedThrowingContinuation { continuation in
            pendingJSONRequests[id] = continuation
            connection.send(msg)

            Task { @MainActor in
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                if let c = self.pendingJSONRequests.removeValue(forKey: id) {
                    c.resume(throwing: ACTransportError.timeout(method))
                }
            }
        }
    }

    private func ensureJSONRPCInitializedIfNeeded() async throws {
        guard !didInitializeJSONRPC else { return }

        let clientInfo: [String: AnyCodable] = [
            "name": AnyCodable("agentcockpit_ios"),
            "title": AnyCodable("AgentCockpit"),
            "version": AnyCodable("0.1.0"),
        ]

        let initParams: [String: AnyCodable] = switch settings.serverProtocol {
        case .acp:
            [
                "protocolVersion": AnyCodable(1),
                "clientInfo": AnyCodable(clientInfo),
                "capabilities": AnyCodable([
                    "filesystem": AnyCodable(true),
                    "terminal": AnyCodable(true),
                ]),
            ]

        case .codex:
            [
                "clientInfo": AnyCodable(clientInfo),
                "capabilities": AnyCodable([
                    "experimentalApi": AnyCodable(false)
                ]),
            ]
        }

        let initializeResult = try await sendJSONRequest(method: "initialize", params: initParams)
        configureServerCapabilities(fromInitializeResult: initializeResult)
        connection.send(ACJSONRPCNotificationMessage(method: "initialized", params: [:]))
        if settings.serverProtocol == .codex {
            connection.send(ACJSONRPCNotificationMessage(method: "notifications/initialized", params: [:]))
        }
        didInitializeJSONRPC = true
    }

    private func configureServerCapabilities(fromInitializeResult result: AnyCodable?) {
        let advertised = Self.advertisedMethods(fromInitializeResult: result)
        serverAdvertisedMethods = advertised
        if let negotiated = Self.negotiateGenUIActionMethod(
            for: settings.serverProtocol,
            advertisedMethods: advertised
        ) {
            negotiatedGenUIActionMethodByProtocol[settings.serverProtocol] = negotiated
        }
    }

    private func resolvedGenUIActionMethod(for protocolMode: ACServerProtocol) -> String? {
        if let cached = negotiatedGenUIActionMethodByProtocol[protocolMode] {
            return cached
        }
        if let resolved = Self.resolveGenUIActionMethod(
            for: protocolMode,
            advertisedMethods: serverAdvertisedMethods
        ) {
            negotiatedGenUIActionMethodByProtocol[protocolMode] = resolved
            return resolved
        }
        return nil
    }

    private func cacheACPSessionDirectories(from sessions: [ACSessionEntry]) {
        for session in sessions {
            guard let cwd = normalizedAbsoluteCwd(session.cwd)
            else { continue }
            acpSessionDirectories[session.key] = cwd
        }
    }

    private func resolvedACPCwd(for sessionKey: String) -> String? {
        if let cached = acpSessionDirectories[sessionKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty {
            return cached
        }

        return normalizedAbsoluteCwd(settings.workingDirectory)
    }

    private func ensureACPSessionLoaded(sessionKey: String) async throws {
        guard settings.serverProtocol == .acp else { return }
        guard !loadedACPSessionIDs.contains(sessionKey) else { return }

        let cwd = resolvedACPCwd(for: sessionKey)
        var baseParams: [String: AnyCodable] = ["sessionId": AnyCodable(sessionKey)]
        if let cwd {
            baseParams["cwd"] = AnyCodable(cwd)
        }

        let methods = ["session/load", "session/resume"]
        var lastError: ACTransportError?
        var sawKnownLoadMethod = false

        for method in methods {
            do {
                _ = try await requestJSON(method: method, params: baseParams)
                loadedACPSessionIDs.insert(sessionKey)
                return
            } catch ACTransportError.serverError(let code, _) where code == -32601 {
                continue
            } catch let error as ACTransportError {
                sawKnownLoadMethod = true
                lastError = error
                continue
            }
        }

        if !sawKnownLoadMethod {
            loadedACPSessionIDs.insert(sessionKey)
            return
        }

        if let lastError {
            if case ACTransportError.serverError(let code, let message) = lastError,
               code == -32602,
               cwd == nil {
                throw ACTransportError.serverError(
                    code,
                    "ACP load/resume requires an absolute cwd (\(message)). Set Working Dir in Settings."
                )
            }
            throw lastError
        }
    }

    private func loadACPHistory(sessionKey: String) async throws -> [CanvasEvent] {
        var params: [String: AnyCodable] = ["sessionId": AnyCodable(sessionKey)]
        if let cwd = resolvedACPCwd(for: sessionKey) {
            params["cwd"] = AnyCodable(cwd)
        }

        let methods = ["session/load", "session/resume"]
        var lastError: ACTransportError?

        for method in methods {
            do {
                let result = try await requestJSON(method: method, params: params)
                loadedACPSessionIDs.insert(sessionKey)
                let messages = Self.mapACPHistory(from: result, sessionKey: sessionKey)
                if !messages.isEmpty {
                    return messages
                }
                let replayUpdates = Self.mapACPReplayUpdates(from: result, sessionKey: sessionKey)
                return replayUpdates
            } catch ACTransportError.serverError(let code, _) where code == -32601 {
                continue
            } catch let error as ACTransportError {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        return []
    }

    private func ensureCodexThreadResumed(sessionKey: String) async throws {
        guard settings.serverProtocol == .codex else { return }
        guard !loadedCodexThreadIDs.contains(sessionKey) else { return }

        _ = try await requestJSON(
            method: "thread/resume",
            params: ["threadId": AnyCodable(sessionKey)]
        )
        loadedCodexThreadIDs.insert(sessionKey)
    }

    private func trackCodexTurnLifecycle(method: String, params: [String: AnyCodable]?) {
        guard settings.serverProtocol == .codex else { return }
        let root = params ?? [:]

        switch method {
        case "turn/started":
            let threadID = root["threadId"]?.stringValue
                ?? root["turn"]?.dictValue?["threadId"]?.stringValue
            let turnID = root["turnId"]?.stringValue
                ?? root["turn"]?.dictValue?["id"]?.stringValue
            if let threadID, let turnID {
                activeCodexTurnByThread[threadID] = turnID
            }

        case "turn/completed":
            if let threadID = root["threadId"]?.stringValue
                ?? root["turn"]?.dictValue?["threadId"]?.stringValue {
                activeCodexTurnByThread.removeValue(forKey: threadID)
            }

        case "thread/started":
            if let threadID = root["threadId"]?.stringValue
                ?? root["thread"]?.dictValue?["id"]?.stringValue {
                loadedCodexThreadIDs.insert(threadID)
            }

        default:
            break
        }
    }

    // MARK: - Parsing helpers

    private func parseACPSessions(from result: AnyCodable?) -> [ACSessionEntry] {
        var candidates: [AnyCodable] = []

        if let dict = result?.dictValue {
            if let sessions = dict["sessions"]?.arrayValue {
                candidates = sessions
            } else if let data = dict["data"]?.arrayValue {
                candidates = data
            }
        } else if let arr = result?.arrayValue {
            candidates = arr
        }

        var parsed: [ACSessionEntry] = []
        parsed.reserveCapacity(candidates.count)
        for candidate in candidates {
            guard let session = candidate.dictValue else { continue }
            let key = session["id"]?.stringValue
                ?? session["sessionId"]?.stringValue
                ?? session["session_id"]?.stringValue
                ?? session["session"]?.stringValue
                ?? session["key"]?.stringValue
            guard let key else { continue }

            let status = statusText(from: session)
            let updatedAt = dateFrom(session["updatedAt"])
                ?? dateFrom(session["startTime"])
                ?? dateFrom(session["mtime"])
            let createdAt = dateFrom(session["createdAt"])
                ?? updatedAt
                ?? .now
            let preview = session["preview"]?.stringValue
                ?? session["prompt"]?.stringValue
                ?? session["lastMessage"]?.stringValue
            let name = bestDisplayName(
                candidates: [
                    session["title"]?.stringValue,
                    session["name"]?.stringValue,
                    session["prompt"]?.stringValue,
                    preview,
                ],
                fallback: key
            )

            parsed.append(
                ACSessionEntry(
                    key: key,
                    name: name,
                    window: "0",
                    pane: "0",
                    running: runningState(from: status),
                    promoted: false,
                    createdAt: createdAt,
                    cwd: acpCwd(from: session),
                    preview: preview,
                    statusText: status,
                    updatedAt: updatedAt
                )
            )
        }

        return parsed.sorted { lhs, rhs in
            let lhsDate = lhs.updatedAt ?? lhs.createdAt
            let rhsDate = rhs.updatedAt ?? rhs.createdAt
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.key < rhs.key
        }
    }

    private func parseACPSession(from result: AnyCodable?) -> ACSessionEntry? {
        let root = result?.dictValue ?? [:]
        let session = root["session"]?.dictValue ?? root
        let key = session["id"]?.stringValue
            ?? session["sessionId"]?.stringValue
            ?? session["session_id"]?.stringValue
            ?? root["sessionId"]?.stringValue
            ?? root["id"]?.stringValue
        guard let key else { return nil }

        let status = statusText(from: session)
        let updatedAt = dateFrom(session["updatedAt"])
            ?? dateFrom(session["startTime"])
            ?? dateFrom(session["mtime"])
        let createdAt = dateFrom(session["createdAt"])
            ?? updatedAt
            ?? .now
        let preview = session["preview"]?.stringValue
            ?? session["prompt"]?.stringValue
            ?? root["_meta"]?.dictValue?["piAcp"]?.dictValue?["startupInfo"]?.stringValue
        let name = bestDisplayName(
            candidates: [
                session["title"]?.stringValue,
                session["name"]?.stringValue,
                session["prompt"]?.stringValue,
                preview,
            ],
            fallback: key
        )

        return ACSessionEntry(
            key: key,
            name: name,
            window: "0",
            pane: "0",
            running: runningState(from: status),
            promoted: false,
            createdAt: createdAt,
            cwd: acpCwd(from: session, root: root),
            preview: preview,
            statusText: status,
            updatedAt: updatedAt
        )
    }

    private func parseCodexThreads(from result: AnyCodable?) -> [ACSessionEntry] {
        CodexProtocolParser.parseThreadList(from: result).map(sessionEntry(from:))
    }

    private func parseCodexThread(from result: AnyCodable?) -> ACSessionEntry? {
        guard let thread = CodexProtocolParser.parseThread(from: result) else { return nil }
        return sessionEntry(from: thread)
    }

    private func sessionEntry(from thread: CodexThreadSummary) -> ACSessionEntry {
        ACSessionEntry(
            key: thread.id,
            name: bestDisplayName(
                candidates: [thread.name, thread.preview],
                fallback: thread.id
            ),
            window: "0",
            pane: "0",
            running: thread.isRunning,
            promoted: false,
            createdAt: thread.createdAt ?? .now,
            cwd: thread.cwd,
            preview: thread.preview,
            statusText: thread.statusType,
            updatedAt: thread.updatedAt
        )
    }

    private func parseCodexHistory(from result: AnyCodable?) -> [CanvasEvent] {
        Self.mapCodexHistory(from: result)
    }

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

    private static func parseCodexHistoryItem(_ item: CodexItemSnapshot, threadKey: String) -> [CanvasEvent] {
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

    private static func codexReasoningEventID(
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

    private static func mapACPToolStatus(from parsed: ACPUpdateContext, default fallback: ToolStatus) -> ToolStatus {
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

    private func commandText(from item: [String: AnyCodable]) -> String {
        if let array = item["command"]?.arrayValue {
            let parts = array.compactMap(\.stringValue)
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        return item["command"]?.stringValue ?? "command"
    }

    private static func historyMessageText(from message: [String: AnyCodable]) -> String {
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

    private func upsertApprovalRequest(_ request: ACPendingApprovalRequest) {
        if let index = pendingApprovalRequests.firstIndex(where: { $0.id == request.id }) {
            pendingApprovalRequests[index] = request
        } else {
            pendingApprovalRequests.append(request)
        }
        pendingApprovalRequests.sort { $0.receivedAt < $1.receivedAt }
    }

    private func upsertUserInputRequest(_ request: ACPendingUserInputRequest) {
        if let index = pendingUserInputRequests.firstIndex(where: { $0.id == request.id }) {
            pendingUserInputRequests[index] = request
        } else {
            pendingUserInputRequests.append(request)
        }
        pendingUserInputRequests.sort { $0.receivedAt < $1.receivedAt }
    }

    private func parseUserInputQuestions(from root: [String: AnyCodable]) -> [ACUserInputQuestion] {
        guard let rawQuestions = root["questions"]?.arrayValue else { return [] }
        var parsedQuestions: [ACUserInputQuestion] = []
        parsedQuestions.reserveCapacity(rawQuestions.count)

        for (index, questionAny) in rawQuestions.enumerated() {
            guard let question = questionAny.dictValue else { continue }
            let id = question["id"]?.stringValue ?? "q_\(index + 1)"
            let header = question["header"]?.stringValue ?? "Question \(index + 1)"
            let prompt = question["question"]?.stringValue
                ?? question["prompt"]?.stringValue
                ?? ""
            let allowsMultipleSelections = question["multiSelect"]?.boolValue
                ?? question["multi_select"]?.boolValue
                ?? false

            let rawOptions = question["options"]?.arrayValue ?? []
            var options: [ACUserInputOption] = []
            options.reserveCapacity(rawOptions.count)
            for (optionIndex, optionAny) in rawOptions.enumerated() {
                guard let option = optionAny.dictValue else { continue }
                let label = option["label"]?.stringValue
                    ?? option["value"]?.stringValue
                    ?? "Option \(optionIndex + 1)"
                options.append(
                    ACUserInputOption(
                        id: "\(id)_\(optionIndex)",
                        label: label,
                        details: option["description"]?.stringValue,
                        isOther: option["isOther"]?.boolValue ?? option["is_other"]?.boolValue ?? false,
                        isSecret: option["isSecret"]?.boolValue ?? option["is_secret"]?.boolValue ?? false
                    )
                )
            }

            parsedQuestions.append(
                ACUserInputQuestion(
                    id: id,
                    header: header,
                    prompt: prompt,
                    options: options,
                    allowsMultipleSelections: allowsMultipleSelections
                )
            )
        }

        return parsedQuestions
    }

    private func bestDisplayName(candidates: [String?], fallback: String) -> String {
        for candidate in candidates {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  value != "<undecodable>"
            else { continue }
            return value
        }
        return fallback
    }

    private func statusText(from session: [String: AnyCodable]) -> String? {
        session["status"]?.dictValue?["type"]?.stringValue
            ?? session["status"]?.stringValue
            ?? session["state"]?.stringValue
    }

    private func runningState(from status: String?) -> Bool {
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

    private func dateFrom(_ value: AnyCodable?) -> Date? {
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

    private func normalizeUnixTimestampToSeconds(_ raw: Double) -> TimeInterval {
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

    private func normalizedAbsoluteCwd(_ candidate: String?) -> String? {
        guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty else { return nil }
        guard candidate.hasPrefix("/") else { return nil }
        return candidate
    }

    private func acpCwd(from session: [String: AnyCodable], root: [String: AnyCodable]? = nil) -> String? {
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

    nonisolated static func genUIActionMethodCandidates(for protocolMode: ACServerProtocol) -> [String] {
        switch protocolMode {
        case .acp:
            return [
                "genui/action",
                "genui/submitAction",
                "gen_ui/action",
                "session/genui/action",
                "session/gen_ui/action",
            ]
        case .codex:
            return [
                "genui/action",
                "genui/submitAction",
                "gen_ui/action",
                "item/genui/action",
                "item/gen_ui/action",
            ]
        }
    }

    nonisolated static func negotiateGenUIActionMethod(
        for protocolMode: ACServerProtocol,
        advertisedMethods: Set<String>
    ) -> String? {
        let candidates = genUIActionMethodCandidates(for: protocolMode)
        guard !advertisedMethods.isEmpty else {
            return protocolMode == .acp ? candidates.first : nil
        }

        let normalizedLookup = Dictionary(
            uniqueKeysWithValues: advertisedMethods.map {
                ($0.lowercased(), $0)
            }
        )
        for candidate in candidates {
            if let matched = normalizedLookup[candidate.lowercased()] {
                return matched
            }
        }
        return nil
    }

    nonisolated static func resolveGenUIActionMethod(
        for protocolMode: ACServerProtocol,
        advertisedMethods: Set<String>
    ) -> String? {
        if let negotiated = negotiateGenUIActionMethod(
            for: protocolMode,
            advertisedMethods: advertisedMethods
        ) {
            return negotiated
        }
        if protocolMode == .acp, advertisedMethods.isEmpty {
            return genUIActionMethodCandidates(for: protocolMode).first ?? "genui/action"
        }
        return nil
    }

    nonisolated static func advertisedMethods(fromInitializeResult result: AnyCodable?) -> Set<String> {
        guard let root = result?.dictValue else { return [] }
        var methods: Set<String> = []
        collectAdvertisedMethods(from: root, into: &methods, depth: 0)
        return methods
    }

    private nonisolated static func collectAdvertisedMethods(
        from dictionary: [String: AnyCodable],
        into methods: inout Set<String>,
        depth: Int
    ) {
        guard depth < 8 else { return }
        for (key, value) in dictionary {
            if key.contains("/") {
                methods.insert(key)
            }

            if let text = value.stringValue,
               text.contains("/") {
                methods.insert(text)
            }

            if let array = value.arrayValue {
                for item in array {
                    if let method = item.stringValue,
                       method.contains("/") {
                        methods.insert(method)
                    } else if let dict = item.dictValue {
                        if let method = dict["name"]?.stringValue, method.contains("/") {
                            methods.insert(method)
                        }
                        collectAdvertisedMethods(from: dict, into: &methods, depth: depth + 1)
                    }
                }
            }

            if let nested = value.dictValue {
                if let method = nested["method"]?.stringValue, method.contains("/") {
                    methods.insert(method)
                }
                if let method = nested["name"]?.stringValue, method.contains("/") {
                    methods.insert(method)
                }
                collectAdvertisedMethods(from: nested, into: &methods, depth: depth + 1)
            }
        }
    }

    private func validatedGenUIActionPayload(from event: GenUIEvent) throws -> [String: AnyCodable] {
        var payload = event.actionPayload
        if payload.isEmpty, let actionLabel = event.actionLabel {
            let fallback = actionLabel
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                payload["actionId"] = AnyCodable(fallback)
                payload["label"] = AnyCodable(actionLabel)
            }
        }

        let actionLabelFallback = event.actionLabel?
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let directActionID = payload["actionId"]?.stringValue
        let underscoredActionID = payload["action_id"]?.stringValue
        let idField = payload["id"]?.stringValue
        let typeField = payload["type"]?.stringValue
        let kindField = payload["kind"]?.stringValue
        let actionID = firstNonEmptyString(
            directActionID,
            underscoredActionID,
            idField,
            typeField,
            kindField,
            actionLabelFallback
        )

        guard let actionID,
              !actionID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        else {
            throw ACTransportError.invalidRequest("GenUI action missing actionId/type")
        }

        payload["actionId"] = AnyCodable(actionID)
        if payload["surfaceId"] == nil {
            payload["surfaceId"] = AnyCodable(event.surfaceID)
        }
        if payload["schemaVersion"] == nil {
            payload["schemaVersion"] = AnyCodable(event.schemaVersion)
        }
        if payload["revision"] == nil {
            payload["revision"] = AnyCodable(event.revision)
        }
        if payload["mode"] == nil {
            payload["mode"] = AnyCodable(event.mode == .patch ? "patch" : "snapshot")
        }
        if payload["context"] == nil, !event.contextPayload.isEmpty {
            payload["context"] = AnyCodable(event.contextPayload)
        }
        if payload["correlationId"] == nil, let correlationID = event.correlationID {
            payload["correlationId"] = AnyCodable(correlationID)
        }

        let rawPayload = ACPProtocolParser.compactJSONString(from: payload)
        if rawPayload.count > 32_000 {
            throw ACTransportError.invalidRequest("GenUI action payload too large")
        }
        return payload
    }

    private func firstNonEmptyString(_ values: String?...) -> String? {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

public enum ACTransportError: Error, LocalizedError {
    case serverError(Int, String)
    case timeout(String)
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .timeout(let method): return "Request timeout for \(method)"
        case .invalidRequest(let message): return message
        }
    }
}
