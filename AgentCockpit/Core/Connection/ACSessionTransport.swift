// ACSessionTransport.swift — Core transport class with shared state
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

    let connection: ACGatewayConnection
    let settings: ACSettingsStore

    var pendingJSONRequests: [String: CheckedContinuation<AnyCodable?, Error>] = [:]
    var requestCounter = 0
    var didInitializeJSONRPC = false
    var serverAdvertisedMethods: Set<String> = []
    var negotiatedGenUIActionMethodByProtocol: [ACServerProtocol: String] = [:]
    var loadedACPSessionIDs: Set<String> = []
    var loadedCodexThreadIDs: Set<String> = []
    var acpSessionDirectories: [String: String] = [:]
    var activeCodexTurnByThread: [String: String] = [:]
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
            return try await listSessionsForACP()
        case .codex:
            return try await listSessionsForCodex()
        }
    }

    public func createSession() async throws -> ACSessionEntry? {
        switch settings.serverProtocol {
        case .acp:
            return try await createSessionForACP()
        case .codex:
            return try await createSessionForCodex()
        }
    }

    public func subscribe(sessionKey: String) async throws {
        switch settings.serverProtocol {
        case .acp:
            try await subscribeForACP(sessionKey: sessionKey)
        case .codex:
            try await subscribeForCodex(sessionKey: sessionKey)
        }
    }

    public func send(sessionKey: String, text: String) async throws {
        switch settings.serverProtocol {
        case .acp:
            try await sendForACP(sessionKey: sessionKey, text: text)
        case .codex:
            try await sendForCodex(sessionKey: sessionKey, text: text)
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

    public func promote(sessionKey: String) async throws {
        switch settings.serverProtocol {
        case .acp, .codex:
            break
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
            return Self.mapCodexHistory(from: result)
        }
    }

    public func submitGenUIAction(sessionKey: String, event: GenUIEvent) async throws {
        try await submitGenUIActionInternal(sessionKey: sessionKey, event: event)
    }

    // MARK: - Internal request helpers

    func requestJSON(method: String, params: [String: AnyCodable]? = nil) async throws -> AnyCodable? {
        try await ensureJSONRPCInitializedIfNeeded()
        return try await sendJSONRequest(method: method, params: params)
    }

    func sendJSONRequest(
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

    func ensureJSONRPCInitializedIfNeeded() async throws {
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

    func configureServerCapabilities(fromInitializeResult result: AnyCodable?) {
        let advertised = Self.advertisedMethods(fromInitializeResult: result)
        serverAdvertisedMethods = advertised
        if let negotiated = Self.negotiateGenUIActionMethod(
            for: settings.serverProtocol,
            advertisedMethods: advertised
        ) {
            negotiatedGenUIActionMethodByProtocol[settings.serverProtocol] = negotiated
        }
    }

    func upsertApprovalRequest(_ request: ACPendingApprovalRequest) {
        if let index = pendingApprovalRequests.firstIndex(where: { $0.id == request.id }) {
            pendingApprovalRequests[index] = request
        } else {
            pendingApprovalRequests.append(request)
        }
        pendingApprovalRequests.sort { $0.receivedAt < $1.receivedAt }
    }

    func upsertUserInputRequest(_ request: ACPendingUserInputRequest) {
        if let index = pendingUserInputRequests.firstIndex(where: { $0.id == request.id }) {
            pendingUserInputRequests[index] = request
        } else {
            pendingUserInputRequests.append(request)
        }
        pendingUserInputRequests.sort { $0.receivedAt < $1.receivedAt }
    }

    func parseUserInputQuestions(from root: [String: AnyCodable]) -> [ACUserInputQuestion] {
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

    func commandText(from item: [String: AnyCodable]) -> String {
        if let array = item["command"]?.arrayValue {
            let parts = array.compactMap(\.stringValue)
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        return item["command"]?.stringValue ?? "command"
    }
}
