import Foundation

struct PendingGenUIActionEnvelope: Identifiable, Codable, Sendable {
    let id: String
    let sessionKey: String
    let event: GenUIEvent
    let enqueuedAt: Date
    var attemptCount: Int
    var lastAttemptAt: Date?
    var lastError: String?

    init(
        id: String,
        sessionKey: String,
        event: GenUIEvent,
        enqueuedAt: Date = .now,
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.sessionKey = sessionKey
        self.event = event
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }
}

struct GenUIPersistenceSnapshot: Codable, Sendable {
    var surfacesBySession: [String: [GenUIEvent]]
    var pendingActions: [PendingGenUIActionEnvelope]

    static let empty = GenUIPersistenceSnapshot(surfacesBySession: [:], pendingActions: [])
}

@MainActor
final class GenUIPersistenceStore {
    private let key = "agentcockpit.genui.persistence.v1"

    func load() -> GenUIPersistenceSnapshot {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(GenUIPersistenceSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    func save(_ snapshot: GenUIPersistenceSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
