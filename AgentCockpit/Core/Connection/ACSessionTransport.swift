// ACSessionTransport.swift — Typed request/response methods across legacy gateway, ACP, and Codex app-server
import Foundation

@Observable
@MainActor
public final class ACSessionTransport {
    private let connection: ACGatewayConnection
    private let settings: ACSettingsStore

    private var pendingLegacyRequests: [String: CheckedContinuation<ACResult, Error>] = [:]
    private var pendingJSONRequests: [String: CheckedContinuation<AnyCodable?, Error>] = [:]
    private var requestCounter = 0
    private var didInitializeJSONRPC = false
    private var loadedCodexThreadIDs: Set<String> = []

    public init(connection: ACGatewayConnection, settings: ACSettingsStore) {
        self.connection = connection
        self.settings = settings
    }

    public func resetConnectionLifecycle() {
        didInitializeJSONRPC = false
        loadedCodexThreadIDs.removeAll()
    }

    // Called by AppModel when a message arrives
    public func handleMessage(_ msg: ACServerMessage) {
        switch msg {
        case .response(let id, let result):
            if let continuation = pendingLegacyRequests.removeValue(forKey: id) {
                continuation.resume(returning: result)
            }

        case .jsonrpcResponse(let id, let result, let error):
            if let continuation = pendingJSONRequests.removeValue(forKey: id) {
                if let error {
                    continuation.resume(throwing: ACTransportError.serverError(error.code, error.message))
                } else {
                    continuation.resume(returning: result)
                }
            }

        default:
            break
        }
    }

    public func handleServerRequest(id: String, method: String, params: [String: AnyCodable]?) {
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            connection.send(ACJSONRPCResponseMessage(id: id, result: AnyCodable("accept")))

        case "item/tool/requestUserInput", "tool/requestUserInput":
            let result: [String: AnyCodable] = [
                "answers": AnyCodable([String: AnyCodable]())
            ]
            connection.send(ACJSONRPCResponseMessage(id: id, result: AnyCodable(result)))

        default:
            let error = ACJSONRPCErrorPayload(code: -32601, message: "Method not handled in AgentCockpit")
            connection.send(ACJSONRPCResponseMessage(id: id, error: error))
        }
    }

    // MARK: - Public request methods

    public func listSessions() async throws -> [ACSessionEntry] {
        switch settings.serverProtocol {
        case .gatewayLegacy:
            let result = try await requestLegacy(method: "sessions.list")
            if case .sessions(let sessions) = result { return sessions }
            if case .error(let code, let msg) = result { throw ACTransportError.serverError(code, msg) }
            return []

        case .acp:
            let result = try await requestJSON(method: "session/list")
            return parseACPSessions(from: result)

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
        case .gatewayLegacy:
            return nil

        case .acp:
            var params: [String: AnyCodable] = [:]
            if !settings.workingDirectory.isEmpty {
                params["cwd"] = AnyCodable(settings.workingDirectory)
            }
            let result = try await requestJSON(
                method: "session/new",
                params: params.isEmpty ? nil : params
            )
            return parseACPSession(from: result)

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
        case .gatewayLegacy:
            let result = try await requestLegacy(method: "session.subscribe", params: .sessionKey(sessionKey))
            if case .error(let code, let msg) = result { throw ACTransportError.serverError(code, msg) }

        case .acp:
            break

        case .codex:
            try await ensureCodexThreadResumed(sessionKey: sessionKey)
        }
    }

    public func send(sessionKey: String, text: String) async throws {
        switch settings.serverProtocol {
        case .gatewayLegacy:
            let result = try await requestLegacy(
                method: "session.send",
                params: .sessionSend(sessionKey: sessionKey, text: text)
            )
            if case .error(let code, let msg) = result { throw ACTransportError.serverError(code, msg) }

        case .acp:
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
        case .gatewayLegacy, .acp:
            return []

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

    public func promote(sessionKey: String) async throws {
        switch settings.serverProtocol {
        case .gatewayLegacy:
            let result = try await requestLegacy(method: "session.promote", params: .sessionKey(sessionKey))
            if case .error(let code, let msg) = result { throw ACTransportError.serverError(code, msg) }

        case .acp, .codex:
            break
        }
    }

    // MARK: - Internal request helpers

    private func requestLegacy(method: String, params: ACParams? = nil) async throws -> ACResult {
        requestCounter += 1
        let id = "req-\(requestCounter)"
        let msg = ACRequestMessage(id: id, method: method, params: params)

        return try await withCheckedThrowingContinuation { continuation in
            pendingLegacyRequests[id] = continuation
            connection.send(msg)

            Task { @MainActor in
                try await Task.sleep(nanoseconds: 10_000_000_000)
                if let c = self.pendingLegacyRequests.removeValue(forKey: id) {
                    c.resume(throwing: ACTransportError.timeout(method))
                }
            }
        }
    }

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
        guard settings.serverProtocol != .gatewayLegacy else { return }
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

        case .gatewayLegacy:
            [:]
        }

        _ = try await sendJSONRequest(method: "initialize", params: initParams)
        connection.send(ACJSONRPCNotificationMessage(method: "initialized", params: [:]))
        if settings.serverProtocol == .codex {
            connection.send(ACJSONRPCNotificationMessage(method: "notifications/initialized", params: [:]))
        }
        didInitializeJSONRPC = true
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

        return candidates.compactMap { candidate in
            guard let session = candidate.dictValue else { return nil }
            let key = session["id"]?.stringValue
                ?? session["sessionId"]?.stringValue
                ?? session["session_id"]?.stringValue
                ?? session["key"]?.stringValue
            guard let key else { return nil }

            let name = session["title"]?.stringValue
                ?? session["name"]?.stringValue
                ?? key

            return ACSessionEntry(
                key: key,
                name: name,
                window: "0",
                pane: "0",
                running: true,
                promoted: false,
                createdAt: dateFrom(session["createdAt"]) ?? .now,
                preview: session["preview"]?.stringValue,
                statusText: session["status"]?.stringValue,
                updatedAt: dateFrom(session["updatedAt"])
            )
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

        let name = session["title"]?.stringValue
            ?? session["name"]?.stringValue
            ?? key

        return ACSessionEntry(
            key: key,
            name: name,
            window: "0",
            pane: "0",
            running: true,
            promoted: false,
            createdAt: dateFrom(session["createdAt"]) ?? .now,
            preview: session["preview"]?.stringValue,
            statusText: session["status"]?.stringValue,
            updatedAt: dateFrom(session["updatedAt"])
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
        let turns = thread["turns"]?.arrayValue ?? []

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

    private func parseCodexHistoryItem(_ item: [String: AnyCodable], threadKey: String) -> [CanvasEvent] {
        let itemType = item["type"]?.stringValue ?? ""
        let itemID = item["id"]?.stringValue ?? UUID().uuidString

        if itemType == "userMessage" {
            let content = item["content"]?.arrayValue ?? []
            return content.enumerated().compactMap { index, entry in
                guard let payload = entry.dictValue,
                      payload["type"]?.stringValue == "text",
                      let text = payload["text"]?.stringValue,
                      !text.isEmpty
                else { return nil }
                return .rawOutput(
                    RawOutputEvent(
                        id: "codex/\(threadKey)/user/\(itemID)/\(index)",
                        text: "You: \(text)",
                        hookEvent: "history/userMessage"
                    )
                )
            }
        }

        if itemType == "agentMessage" {
            guard let text = item["text"]?.stringValue, !text.isEmpty else { return [] }
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

    private func commandText(from item: [String: AnyCodable]) -> String {
        if let array = item["command"]?.arrayValue {
            let parts = array.compactMap(\.stringValue)
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        return item["command"]?.stringValue ?? "command"
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
