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
    private let connection: ACGatewayConnection
    private let settings: ACSettingsStore

    private var pendingJSONRequests: [String: CheckedContinuation<AnyCodable?, Error>] = [:]
    private var requestCounter = 0
    private var didInitializeJSONRPC = false
    private var loadedACPSessionIDs: Set<String> = []
    private var loadedCodexThreadIDs: Set<String> = []
    private var acpSessionDirectories: [String: String] = [:]
    private var activeCodexTurnByThread: [String: String] = [:]
    public private(set) var pendingApprovalRequests: [ACPendingApprovalRequest] = []
    public private(set) var pendingUserInputRequests: [ACPendingUserInputRequest] = []

    public init(connection: ACGatewayConnection, settings: ACSettingsStore) {
        self.connection = connection
        self.settings = settings
    }

    public func resetConnectionLifecycle() {
        didInitializeJSONRPC = false
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
                params: params.isEmpty ? nil : params
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
        guard !event.actionPayload.isEmpty else { return }
        let surfaceID = event.id.split(separator: "/").last.map(String.init) ?? event.id

        var payload = event.actionPayload
        payload["surfaceId"] = AnyCodable(surfaceID)
        payload["schemaVersion"] = AnyCodable(event.schemaVersion)

        switch settings.serverProtocol {
        case .acp:
            try await ensureACPSessionLoaded(sessionKey: sessionKey)
            payload["sessionId"] = AnyCodable(sessionKey)
            try await requestFirstAvailable(
                methods: ["genui/action", "gen_ui/action", "session/genui/action"],
                params: payload
            )

        case .codex:
            try await ensureCodexThreadResumed(sessionKey: sessionKey)
            payload["threadId"] = AnyCodable(sessionKey)
            try await requestFirstAvailable(
                methods: ["genui/action", "gen_ui/action", "item/genui/action"],
                params: payload
            )
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

    private func requestFirstAvailable(
        methods: [String],
        params: [String: AnyCodable]
    ) async throws {
        var lastError: ACTransportError?
        for method in methods {
            do {
                _ = try await requestJSON(method: method, params: params)
                return
            } catch ACTransportError.serverError(let code, _) where code == -32601 {
                continue
            } catch let error as ACTransportError {
                lastError = error
                break
            }
        }

        if let lastError {
            throw lastError
        }
        throw ACTransportError.serverError(-32601, "No supported GenUI action method found")
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

        _ = try await sendJSONRequest(method: "initialize", params: initParams)
        connection.send(ACJSONRPCNotificationMessage(method: "initialized", params: [:]))
        if settings.serverProtocol == .codex {
            connection.send(ACJSONRPCNotificationMessage(method: "notifications/initialized", params: [:]))
        }
        didInitializeJSONRPC = true
    }

    private func cacheACPSessionDirectories(from sessions: [ACSessionEntry]) {
        for session in sessions {
            guard let cwd = session.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !cwd.isEmpty
            else { continue }
            acpSessionDirectories[session.key] = cwd
        }
    }

    private func resolvedACPCwd(for sessionKey: String) -> String? {
        if let cached = acpSessionDirectories[sessionKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty {
            return cached
        }

        let configured = settings.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configured.isEmpty else { return nil }
        guard configured.hasPrefix("/") else { return nil }
        return configured
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
                return Self.mapACPHistory(from: result, sessionKey: sessionKey)
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
                    cwd: session["cwd"]?.stringValue
                        ?? session["workingDirectory"]?.stringValue
                        ?? session["working_directory"]?.stringValue,
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
            cwd: session["cwd"]?.stringValue
                ?? session["workingDirectory"]?.stringValue
                ?? session["working_directory"]?.stringValue,
            preview: preview,
            statusText: status,
            updatedAt: updatedAt
        )
    }

    private func parseCodexThreads(from result: AnyCodable?) -> [ACSessionEntry] {
        guard let dict = result?.dictValue else { return [] }
        guard let rows = dict["data"]?.arrayValue else { return [] }
        return rows.compactMap { parseCodexThreadFromListRow($0.dictValue) }
    }

    private func parseCodexThread(from result: AnyCodable?) -> ACSessionEntry? {
        let dict = result?.dictValue ?? [:]
        let thread = dict["thread"]?.dictValue ?? dict
        let key = thread["id"]?.stringValue
        guard let key else { return nil }
        let statusType = thread["status"]?.dictValue?["type"]?.stringValue
            ?? thread["status"]?.stringValue
        let name = bestDisplayName(
            candidates: [thread["name"]?.stringValue, thread["preview"]?.stringValue],
            fallback: key
        )
        return ACSessionEntry(
            key: key,
            name: name,
            window: "0",
            pane: "0",
            running: statusType == "active" || statusType == nil,
            promoted: false,
            createdAt: dateFrom(thread["createdAt"]) ?? .now,
            preview: thread["preview"]?.stringValue,
            statusText: statusType,
            updatedAt: dateFrom(thread["updatedAt"])
        )
    }

    private func parseCodexThreadFromListRow(_ row: [String: AnyCodable]?) -> ACSessionEntry? {
        guard let row else { return nil }
        guard let key = row["id"]?.stringValue else { return nil }
        let statusType = row["status"]?.dictValue?["type"]?.stringValue
        return ACSessionEntry(
            key: key,
            name: bestDisplayName(
                candidates: [row["name"]?.stringValue, row["preview"]?.stringValue],
                fallback: key
            ),
            window: "0",
            pane: "0",
            running: statusType == "active" || statusType == nil,
            promoted: false,
            createdAt: dateFrom(row["createdAt"]) ?? .now,
            preview: row["preview"]?.stringValue,
            statusText: statusType,
            updatedAt: dateFrom(row["updatedAt"])
        )
    }

    private func parseCodexHistory(from result: AnyCodable?) -> [CanvasEvent] {
        let root = result?.dictValue ?? [:]
        let thread = root["thread"]?.dictValue ?? root
        let threadKey = thread["id"]?.stringValue ?? "codex"
        let turns = thread["turns"]?.arrayValue
            ?? root["turns"]?.arrayValue
            ?? root["data"]?.dictValue?["turns"]?.arrayValue
            ?? []

        var history: [CanvasEvent] = []
        for turnAny in turns {
            guard let turn = turnAny.dictValue else { continue }
            let items = turn["items"]?.arrayValue ?? []
            for itemAny in items {
                guard let item = itemAny.dictValue else { continue }
                history.append(contentsOf: parseCodexHistoryItem(item, threadKey: threadKey))
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

    private func parseCodexHistoryItem(_ item: [String: AnyCodable], threadKey: String) -> [CanvasEvent] {
        let itemType = canonicalCodexItemType(item["type"]?.stringValue ?? "")
        let itemID = item["id"]?.stringValue ?? UUID().uuidString

        if itemType == "userMessage" {
            let text = userMessageText(from: item)
            guard !text.isEmpty else { return [] }
            return [
                .rawOutput(
                    RawOutputEvent(
                        id: "codex/\(threadKey)/user/\(itemID)",
                        text: "You: \(text)",
                        hookEvent: "history/userMessage"
                    )
                )
            ]
        }

        if itemType == "agentMessage" {
            let text = agentMessageText(from: item)
            guard !text.isEmpty else { return [] }
            return [.reasoning(ReasoningEvent(id: "codex/\(threadKey)/\(itemID)", text: text, isThinking: false))]
        }

        if itemType == "reasoning" {
            let text = reasoningText(from: item)
            guard !text.isEmpty else { return [] }
            return [.reasoning(ReasoningEvent(id: "codex/\(threadKey)/\(itemID)", text: text, isThinking: true))]
        }

        if itemType == "commandExecution" {
            let command = commandText(from: item)
            let status: ToolStatus = switch item["status"]?.stringValue {
            case "failed", "declined": .error
            case "completed": .done
            default: .running
            }
            let output = item["aggregatedOutput"]?.stringValue
                ?? item["stderr"]?.stringValue
                ?? item["stdout"]?.stringValue
            return [
                .toolUse(
                    ToolUseEvent(
                        id: "codex/\(threadKey)/tool/\(itemID)",
                        toolName: "command",
                        phase: status == .running ? .start : .result,
                        input: command,
                        result: output,
                        status: status
                    )
                )
            ]
        }

        if itemType == "fileChange",
           let changes = item["changes"]?.arrayValue,
           let first = changes.first?.dictValue,
           let path = first["path"]?.stringValue {
            let kind = first["kind"]?.stringValue?.lowercased() ?? ""
            let operation: FileOperation = switch kind {
            case "delete", "deleted": .delete
            case "create", "created", "add", "added": .write
            default: .edit
            }
            return [.fileEdit(FileEditEvent(id: "codex/\(threadKey)/tool/\(itemID)", filePath: path, operation: operation))]
        }

        return []
    }

    private func canonicalCodexItemType(_ rawType: String) -> String {
        let normalized = rawType.replacingOccurrences(of: "-", with: "_").lowercased()
        switch normalized {
        case "user_message":
            return "userMessage"
        case "agent_message":
            return "agentMessage"
        case "command_execution":
            return "commandExecution"
        case "file_change":
            return "fileChange"
        case "mcp_tool_call":
            return "mcpToolCall"
        case "collab_tool_call":
            return "collabToolCall"
        default:
            return rawType
        }
    }

    private func commandText(from item: [String: AnyCodable]) -> String {
        if let array = item["command"]?.arrayValue {
            let parts = array.compactMap(\.stringValue)
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        return item["command"]?.stringValue ?? "command"
    }

    private func userMessageText(from item: [String: AnyCodable]) -> String {
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
                if payload["type"]?.stringValue == "text",
                   let text = payload["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
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

    private func agentMessageText(from item: [String: AnyCodable]) -> String {
        if let text = item["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        if let content = item["content"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }
        if let message = item["message"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
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

    private func reasoningText(from item: [String: AnyCodable]) -> String {
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
}

public enum ACTransportError: Error, LocalizedError {
    case serverError(Int, String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .timeout(let method): return "Request timeout for \(method)"
        }
    }
}
