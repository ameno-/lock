// ACSessionTransport+Codex.swift — Codex-specific methods
import Foundation

@MainActor
extension ACSessionTransport {
    func listSessionsForCodex() async throws -> [ACSessionEntry] {
        let result = try await requestJSON(
            method: "thread/list",
            params: ["limit": AnyCodable(100)]
        )
        return parseCodexThreads(from: result)
    }

    func createSessionForCodex() async throws -> ACSessionEntry? {
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

    func subscribeForCodex(sessionKey: String) async throws {
        try await ensureCodexThreadResumed(sessionKey: sessionKey)
    }

    func sendForCodex(sessionKey: String, text: String) async throws {
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

    func ensureCodexThreadResumed(sessionKey: String) async throws {
        guard settings.serverProtocol == .codex else { return }
        guard !loadedCodexThreadIDs.contains(sessionKey) else { return }

        _ = try await requestJSON(
            method: "thread/resume",
            params: ["threadId": AnyCodable(sessionKey)]
        )
        loadedCodexThreadIDs.insert(sessionKey)
    }

    func trackCodexTurnLifecycle(method: String, params: [String: AnyCodable]?) {
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

    func parseCodexThreads(from result: AnyCodable?) -> [ACSessionEntry] {
        CodexProtocolParser.parseThreadList(from: result).map(sessionEntry(from:))
    }

    func parseCodexThread(from result: AnyCodable?) -> ACSessionEntry? {
        guard let thread = CodexProtocolParser.parseThread(from: result) else { return nil }
        return sessionEntry(from: thread)
    }

    func sessionEntry(from thread: CodexThreadSummary) -> ACSessionEntry {
        ACSessionEntry(
            key: thread.id,
            name: Self.bestDisplayName(
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
}
