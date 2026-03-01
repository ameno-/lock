// ACSessionTransport+ACP.swift — ACP-specific methods
import Foundation

@MainActor
extension ACSessionTransport {
    func listSessionsForACP() async throws -> [ACSessionEntry] {
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
    }

    func createSessionForACP() async throws -> ACSessionEntry? {
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
    }

    func subscribeForACP(sessionKey: String) async throws {
        try await ensureACPSessionLoaded(sessionKey: sessionKey)
    }

    func sendForACP(sessionKey: String, text: String) async throws {
        try await ensureACPSessionLoaded(sessionKey: sessionKey)
        let params: [String: AnyCodable] = [
            "sessionId": AnyCodable(sessionKey),
            "prompt": AnyCodable(text),
            "text": AnyCodable(text),
        ]
        _ = try await requestJSON(method: "session/prompt", params: params)
    }

    func loadACPHistory(sessionKey: String) async throws -> [CanvasEvent] {
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

    func ensureACPSessionLoaded(sessionKey: String) async throws {
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

    func parseACPSessions(from result: AnyCodable?) -> [ACSessionEntry] {
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

            let status = Self.statusText(from: session)
            let updatedAt = Self.dateFrom(session["updatedAt"])
                ?? Self.dateFrom(session["startTime"])
                ?? Self.dateFrom(session["mtime"])
            let createdAt = Self.dateFrom(session["createdAt"])
                ?? updatedAt
                ?? .now
            let preview = session["preview"]?.stringValue
                ?? session["prompt"]?.stringValue
                ?? session["lastMessage"]?.stringValue
            let name = Self.bestDisplayName(
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
                    running: Self.runningState(from: status),
                    promoted: false,
                    createdAt: createdAt,
                    cwd: Self.acpCwd(from: session),
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

    func parseACPSession(from result: AnyCodable?) -> ACSessionEntry? {
        let root = result?.dictValue ?? [:]
        let session = root["session"]?.dictValue ?? root
        let key = session["id"]?.stringValue
            ?? session["sessionId"]?.stringValue
            ?? session["session_id"]?.stringValue
            ?? root["sessionId"]?.stringValue
            ?? root["id"]?.stringValue
        guard let key else { return nil }

        let status = Self.statusText(from: session)
        let updatedAt = Self.dateFrom(session["updatedAt"])
            ?? Self.dateFrom(session["startTime"])
            ?? Self.dateFrom(session["mtime"])
        let createdAt = Self.dateFrom(session["createdAt"])
            ?? updatedAt
            ?? .now
        let preview = session["preview"]?.stringValue
            ?? session["prompt"]?.stringValue
            ?? root["_meta"]?.dictValue?["piAcp"]?.dictValue?["startupInfo"]?.stringValue
        let name = Self.bestDisplayName(
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
            running: Self.runningState(from: status),
            promoted: false,
            createdAt: createdAt,
            cwd: Self.acpCwd(from: session, root: root),
            preview: preview,
            statusText: status,
            updatedAt: updatedAt
        )
    }

    func cacheACPSessionDirectories(from sessions: [ACSessionEntry]) {
        for session in sessions {
            guard let cwd = Self.normalizedAbsoluteCwd(session.cwd)
            else { continue }
            acpSessionDirectories[session.key] = cwd
        }
    }

    func resolvedACPCwd(for sessionKey: String) -> String? {
        if let cached = acpSessionDirectories[sessionKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty {
            return cached
        }

        return Self.normalizedAbsoluteCwd(settings.workingDirectory)
    }
}
