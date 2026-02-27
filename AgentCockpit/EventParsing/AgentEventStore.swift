// AgentEventStore.swift — @Observable per-session event log, bounded to 2000 items
import Foundation

public struct SessionTokenUsage: Sendable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let updatedAt: Date

    public init(
        inputTokens: Int?,
        outputTokens: Int?,
        totalTokens: Int?,
        updatedAt: Date = .now
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.updatedAt = updatedAt
    }
}

public struct SessionDigest: Sendable {
    public var lastEventAt: Date?
    public var previewText: String?
    public var status: String?
    public var tokenUsage: SessionTokenUsage?

    public init(
        lastEventAt: Date? = nil,
        previewText: String? = nil,
        status: String? = nil,
        tokenUsage: SessionTokenUsage? = nil
    ) {
        self.lastEventAt = lastEventAt
        self.previewText = previewText
        self.status = status
        self.tokenUsage = tokenUsage
    }
}

@Observable
@MainActor
public final class AgentEventStore {
    private static let maxEvents = 2000

    // All events across all sessions
    public private(set) var allEvents: [CanvasEvent] = []

    // Running sub-agents (for ticker bar)
    public private(set) var runningSubAgents: [SubAgentEvent] = []

    // Per-session event maps
    private var sessionEvents: [String: [CanvasEvent]] = [:]
    private var sessionDigests: [String: SessionDigest] = [:]

    // MARK: - Ingestion

    public func ingest(_ frame: ACEventFrame) {
        guard let event = AgentEventParser.parse(frame) else { return }
        ingest(event: event, sessionKey: frame.sessionKey)
    }

    public func ingest(event: CanvasEvent, sessionKey: String) {
        allEvents = upserting(event: event, into: allEvents)
        allEvents = bounded(events: allEvents)

        var sessionList = sessionEvents[sessionKey] ?? []
        sessionList = upserting(event: event, into: sessionList)
        sessionList = bounded(events: sessionList)
        sessionEvents[sessionKey] = sessionList

        updateDigest(for: sessionKey, event: event)

        if case .subAgent(let subEvent) = event {
            updateRunningSubAgents(subEvent)
        }
    }

    public func touchSession(_ sessionKey: String, at timestamp: Date = .now) {
        var digest = sessionDigests[sessionKey] ?? SessionDigest()
        if digest.lastEventAt == nil || digest.lastEventAt! < timestamp {
            digest.lastEventAt = timestamp
        }
        sessionDigests[sessionKey] = digest
    }

    public func updateSessionStatus(_ status: String, sessionKey: String, at timestamp: Date = .now) {
        var digest = sessionDigests[sessionKey] ?? SessionDigest()
        digest.status = status
        if digest.lastEventAt == nil || digest.lastEventAt! < timestamp {
            digest.lastEventAt = timestamp
        }
        sessionDigests[sessionKey] = digest
    }

    public func updateTokenUsage(_ usage: SessionTokenUsage, sessionKey: String) {
        var digest = sessionDigests[sessionKey] ?? SessionDigest()
        digest.tokenUsage = usage
        if digest.lastEventAt == nil || digest.lastEventAt! < usage.updatedAt {
            digest.lastEventAt = usage.updatedAt
        }
        sessionDigests[sessionKey] = digest
    }

    // MARK: - Queries

    public func events(for sessionKey: String) -> [CanvasEvent] {
        sessionEvents[sessionKey] ?? []
    }

    public func recentEvents(for sessionKey: String, limit: Int = 50) -> [CanvasEvent] {
        let all = sessionEvents[sessionKey] ?? []
        return Array(all.suffix(limit))
    }

    public func digest(for sessionKey: String) -> SessionDigest? {
        sessionDigests[sessionKey]
    }

    public func exportGenUISurfacesBySession() -> [String: [GenUIEvent]] {
        var output: [String: [GenUIEvent]] = [:]

        for (sessionKey, events) in sessionEvents {
            var latestBySurface: [String: GenUIEvent] = [:]

            for event in events {
                guard case .genUI(let genui) = event else { continue }
                if let existing = latestBySurface[genui.surfaceID] {
                    if genui.revision > existing.revision
                        || (genui.revision == existing.revision && genui.timestamp >= existing.timestamp) {
                        latestBySurface[genui.surfaceID] = genui
                    }
                } else {
                    latestBySurface[genui.surfaceID] = genui
                }
            }

            if !latestBySurface.isEmpty {
                output[sessionKey] = latestBySurface.values
                    .sorted { lhs, rhs in
                        if lhs.revision != rhs.revision {
                            return lhs.revision < rhs.revision
                        }
                        return lhs.timestamp < rhs.timestamp
                    }
            }
        }

        return output
    }

    public func restoreGenUISurfacesBySession(_ surfacesBySession: [String: [GenUIEvent]]) {
        for (sessionKey, events) in surfacesBySession {
            for event in events.sorted(by: { lhs, rhs in
                if lhs.revision != rhs.revision {
                    return lhs.revision < rhs.revision
                }
                return lhs.timestamp < rhs.timestamp
            }) {
                ingest(event: .genUI(event), sessionKey: sessionKey)
            }
        }
    }

    public func clear(sessionKey: String) {
        sessionEvents.removeValue(forKey: sessionKey)
        sessionDigests.removeValue(forKey: sessionKey)
    }

    public func clearAll() {
        allEvents = []
        sessionEvents = [:]
        sessionDigests = [:]
        runningSubAgents = []
    }

    // MARK: - Event upsert

    private func upserting(event: CanvasEvent, into events: [CanvasEvent]) -> [CanvasEvent] {
        var mutable = events
        if let index = mutable.lastIndex(where: { $0.id == event.id }) {
            mutable[index] = merge(existing: mutable[index], incoming: event)
            return mutable
        }

        mutable.append(event)
        return mutable
    }

    private func bounded(events: [CanvasEvent]) -> [CanvasEvent] {
        guard events.count > Self.maxEvents else { return events }
        return Array(events.suffix(Self.maxEvents))
    }

    private func merge(existing: CanvasEvent, incoming: CanvasEvent) -> CanvasEvent {
        switch (existing, incoming) {
        case let (.reasoning(old), .reasoning(new)):
            return .reasoning(
                ReasoningEvent(
                    id: old.id,
                    text: mergeReasoningText(current: old.text, incoming: new.text),
                    isThinking: new.isThinking,
                    timestamp: new.timestamp
                )
            )
        case let (.genUI(old), .genUI(new)):
            if new.revision < old.revision {
                return .genUI(old)
            }
            return .genUI(
                GenUIEvent(
                    id: old.id,
                    schemaVersion: new.schemaVersion,
                    mode: new.mode,
                    surfaceID: mergedText(current: old.surfaceID, incoming: new.surfaceID, preferIncoming: true),
                    revision: max(old.revision, new.revision),
                    correlationID: new.correlationID ?? old.correlationID,
                    title: mergedText(current: old.title, incoming: new.title, preferIncoming: true),
                    body: mergedText(current: old.body, incoming: new.body, preferIncoming: true),
                    surfacePayload: mergeSurfacePayload(current: old.surfacePayload, incoming: new.surfacePayload, mode: new.mode),
                    contextPayload: mergeContextPayload(current: old.contextPayload, incoming: new.contextPayload),
                    actionLabel: new.actionLabel ?? old.actionLabel,
                    actionPayload: mergeActionPayload(current: old.actionPayload, incoming: new.actionPayload),
                    timestamp: new.timestamp
                )
            )
        default:
            return incoming
        }
    }

    private func mergeActionPayload(
        current: [String: AnyCodable],
        incoming: [String: AnyCodable]
    ) -> [String: AnyCodable] {
        guard !incoming.isEmpty else { return current }
        var merged = current
        for (key, value) in incoming {
            merged[key] = value
        }
        return merged
    }

    private func mergeSurfacePayload(
        current: [String: AnyCodable],
        incoming: [String: AnyCodable],
        mode: GenUIEvent.UpdateMode
    ) -> [String: AnyCodable] {
        guard !incoming.isEmpty else { return current }
        if mode == .snapshot {
            return incoming
        }
        return mergeDictionaryPatch(current: current, incoming: incoming)
    }

    private func mergeContextPayload(
        current: [String: AnyCodable],
        incoming: [String: AnyCodable]
    ) -> [String: AnyCodable] {
        guard !incoming.isEmpty else { return current }
        return mergeDictionaryPatch(current: current, incoming: incoming)
    }

    private func mergeDictionaryPatch(
        current: [String: AnyCodable],
        incoming: [String: AnyCodable]
    ) -> [String: AnyCodable] {
        var merged = current
        for (key, incomingValue) in incoming {
            guard let currentValue = merged[key] else {
                merged[key] = incomingValue
                continue
            }

            if let incomingDict = incomingValue.dictValue,
               let currentDict = currentValue.dictValue {
                merged[key] = AnyCodable(mergeDictionaryPatch(current: currentDict, incoming: incomingDict))
                continue
            }

            if let incomingArray = incomingValue.arrayValue,
               let currentArray = currentValue.arrayValue {
                merged[key] = AnyCodable(mergeArrayPatch(key: key, current: currentArray, incoming: incomingArray))
                continue
            }

            merged[key] = incomingValue
        }
        return merged
    }

    private func mergeArrayPatch(
        key: String,
        current: [AnyCodable],
        incoming: [AnyCodable]
    ) -> [AnyCodable] {
        guard !incoming.isEmpty else { return current }

        if key == "components" || key == "items" || key == "actions" || key == "buttons" {
            return mergeArrayOfObjectsByIdentity(current: current, incoming: incoming)
        }

        if canMergeArrayByIdentity(current: current, incoming: incoming) {
            return mergeArrayOfObjectsByIdentity(current: current, incoming: incoming)
        }

        return incoming
    }

    private func canMergeArrayByIdentity(current: [AnyCodable], incoming: [AnyCodable]) -> Bool {
        guard !incoming.isEmpty else { return false }
        let all = current + incoming
        return all.allSatisfy { value in
            guard let dict = value.dictValue else { return false }
            return dictionaryIdentity(dict) != nil
        }
    }

    private func mergeArrayOfObjectsByIdentity(
        current: [AnyCodable],
        incoming: [AnyCodable]
    ) -> [AnyCodable] {
        var result = current
        var indexByIdentity: [String: Int] = [:]

        for (index, value) in result.enumerated() {
            guard let dict = value.dictValue,
                  let identity = dictionaryIdentity(dict)
            else { continue }
            indexByIdentity[identity] = index
        }

        for incomingValue in incoming {
            guard let incomingDict = incomingValue.dictValue,
                  let identity = dictionaryIdentity(incomingDict)
            else {
                result.append(incomingValue)
                continue
            }

            if let existingIndex = indexByIdentity[identity],
               let existingDict = result[existingIndex].dictValue {
                result[existingIndex] = AnyCodable(
                    mergeDictionaryPatch(current: existingDict, incoming: incomingDict)
                )
            } else {
                indexByIdentity[identity] = result.count
                result.append(incomingValue)
            }
        }

        return result
    }

    private func dictionaryIdentity(_ dict: [String: AnyCodable]) -> String? {
        if let id = normalizedString(dict["id"]) { return "id:\(id)" }
        if let id = normalizedString(dict["actionId"]) { return "action:\(id)" }
        if let id = normalizedString(dict["action_id"]) { return "action:\(id)" }
        if let id = normalizedString(dict["key"]) { return "key:\(id)" }
        if let id = normalizedString(dict["name"]) { return "name:\(id)" }
        if let id = normalizedString(dict["type"]) { return "type:\(id)" }
        return nil
    }

    private func normalizedString(_ value: AnyCodable?) -> String? {
        guard let trimmed = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func mergedText(current: String, incoming: String, preferIncoming: Bool) -> String {
        let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedIncoming.isEmpty {
            return current
        }
        if preferIncoming {
            return incoming
        }
        return incoming.count >= current.count ? incoming : current
    }

    private func mergeReasoningText(current: String, incoming: String) -> String {
        guard !incoming.isEmpty else { return current }
        guard !current.isEmpty else { return incoming }

        let normalizedCurrent = normalizedReasoningText(current)
        let normalizedIncoming = normalizedReasoningText(incoming)
        let fingerprintCurrent = reasoningFingerprint(normalizedCurrent)
        let fingerprintIncoming = reasoningFingerprint(normalizedIncoming)

        if normalizedIncoming == normalizedCurrent {
            return incoming
        }
        if !fingerprintCurrent.isEmpty && fingerprintIncoming == fingerprintCurrent {
            return incoming
        }
        if normalizedIncoming.hasPrefix(normalizedCurrent) {
            return incoming
        }
        if normalizedCurrent.hasPrefix(normalizedIncoming) {
            return current
        }
        if !fingerprintCurrent.isEmpty && fingerprintIncoming.hasPrefix(fingerprintCurrent) {
            return incoming
        }
        if !fingerprintIncoming.isEmpty && fingerprintCurrent.hasPrefix(fingerprintIncoming) {
            return current
        }

        if incoming.hasPrefix(current) || (incoming.count > current.count && incoming.contains(current)) {
            return incoming
        }
        if current.hasPrefix(incoming) || current.hasSuffix(incoming) {
            return current
        }

        let lastScalar = current.unicodeScalars.last
        let firstScalar = incoming.unicodeScalars.first
        let needsSpace = (lastScalar.map(CharacterSet.whitespacesAndNewlines.contains) == false)
            && (firstScalar.map(CharacterSet.whitespacesAndNewlines.contains) == false)
        return needsSpace ? "\(current) \(incoming)" : "\(current)\(incoming)"
    }

    private func normalizedReasoningText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let punctuation = [".", ",", "?", "!", ";", ":"]
        for mark in punctuation {
            normalized = normalized.replacingOccurrences(of: " \(mark)", with: mark)
        }
        return normalized
    }

    private func reasoningFingerprint(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return text.unicodeScalars
            .filter { allowed.contains($0) }
            .map { Character($0) }
            .map { String($0).lowercased() }
            .joined()
    }

    // MARK: - Digest

    private func updateDigest(for sessionKey: String, event: CanvasEvent) {
        var digest = sessionDigests[sessionKey] ?? SessionDigest()
        digest.lastEventAt = event.timestamp
        if let preview = previewText(for: event) {
            digest.previewText = preview
        }
        sessionDigests[sessionKey] = digest
    }

    private func previewText(for event: CanvasEvent) -> String? {
        let raw: String
        switch event {
        case .reasoning(let e):
            raw = e.text
        case .toolUse(let e):
            raw = (e.result?.isEmpty == false ? e.result : nil) ?? e.input
        case .fileEdit(let e):
            raw = "\(e.operation.label): \(e.filePath)"
        case .genUI(let e):
            raw = "\(e.title): \(e.body)"
        case .gitDiff(let e):
            raw = e.filePath ?? "Git diff updated"
        case .subAgent(let e):
            raw = "Sub-agent \(e.subSessionKey) \(e.phase.label)"
        case .skillRun(let e):
            raw = "\(e.skillName) \(e.status.label)"
        case .rawOutput(let e):
            raw = e.text
        }
        return normalizedPreview(raw)
    }

    private func normalizedPreview(_ text: String) -> String? {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return nil }
        if compact.count <= 140 {
            return compact
        }
        let limit = compact.index(compact.startIndex, offsetBy: 140)
        return "\(compact[..<limit])..."
    }

    // MARK: - Sub-agent management

    private func updateRunningSubAgents(_ event: SubAgentEvent) {
        switch event.phase {
        case .spawned, .running:
            if !runningSubAgents.contains(where: { $0.subSessionKey == event.subSessionKey }) {
                runningSubAgents.append(event)
            }
        case .done, .failed:
            runningSubAgents.removeAll { $0.subSessionKey == event.subSessionKey }
        }
    }
}

private extension FileOperation {
    var label: String {
        switch self {
        case .read: "read"
        case .write: "write"
        case .edit: "edit"
        case .delete: "delete"
        }
    }
}

private extension SubAgentPhase {
    var label: String {
        switch self {
        case .spawned: "spawned"
        case .running: "running"
        case .done: "done"
        case .failed: "failed"
        }
    }
}

private extension SkillStatus {
    var label: String {
        switch self {
        case .running: "running"
        case .done: "done"
        case .failed: "failed"
        }
    }
}
