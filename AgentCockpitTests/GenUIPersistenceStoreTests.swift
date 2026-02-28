import XCTest
@testable import AgentCockpit

@MainActor
final class GenUIPersistenceStoreTests: XCTestCase {
    func testPersistenceStoreRoundTripsSurfacesAndPendingActions() {
        let store = GenUIPersistenceStore()
        store.clear()

        let event = GenUIEvent(
            id: "persist/genui/surface-1",
            schemaVersion: "v0",
            mode: .patch,
            surfaceID: "surface-1",
            revision: 4,
            correlationID: "corr-1",
            title: "Persisted",
            body: "Body",
            surfacePayload: [
                "components": AnyCodable([
                    AnyCodable([
                        "id": AnyCodable("summary"),
                        "type": AnyCodable("text"),
                        "text": AnyCodable("snapshot")
                    ])
                ])
            ],
            contextPayload: [
                "source": AnyCodable("test")
            ],
            actionLabel: "Continue",
            actionPayload: ["actionId": AnyCodable("continue")]
        )

        let pending = PendingGenUIActionEnvelope(
            id: "pending-1",
            sessionKey: "session-1",
            event: event,
            enqueuedAt: .now,
            attemptCount: 2,
            lastAttemptAt: .now,
            lastError: "timeout"
        )

        store.save(
            GenUIPersistenceSnapshot(
                surfacesBySession: ["session-1": [event]],
                pendingActions: [pending]
            )
        )

        let loaded = store.load()

        XCTAssertEqual(loaded.surfacesBySession["session-1"]?.count, 1)
        XCTAssertEqual(loaded.pendingActions.count, 1)
        XCTAssertEqual(loaded.pendingActions.first?.id, "pending-1")
        XCTAssertEqual(loaded.pendingActions.first?.event.surfaceID, "surface-1")
        XCTAssertEqual(loaded.pendingActions.first?.event.revision, 4)

        store.clear()
    }
}
