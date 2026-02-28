import XCTest
@testable import AgentCockpit

@MainActor
final class AppModelGenUIPersistenceTests: XCTestCase {
    func testPendingActionsAndSurfacesRestoreAcrossModelRecreation() {
        let persistence = GenUIPersistenceStore()
        persistence.clear()

        let model1 = AppModel()
        let event = GenUIEvent(
            id: "persist/genui/surface-9",
            schemaVersion: "v0",
            mode: .patch,
            surfaceID: "surface-9",
            revision: 9,
            correlationID: "corr-9",
            title: "Persisted Surface",
            body: "Body",
            surfacePayload: [
                "components": AnyCodable([
                    AnyCodable([
                        "id": AnyCodable("summary"),
                        "type": AnyCodable("text"),
                        "text": AnyCodable("hello")
                    ])
                ])
            ],
            contextPayload: [
                "source": AnyCodable("appmodel-test")
            ],
            actionLabel: "Continue",
            actionPayload: ["actionId": AnyCodable("continue")]
        )

        model1.eventStore.ingest(event: .genUI(event), sessionKey: "session-9")
        let pendingID = model1.enqueuePendingGenUIAction(sessionKey: "session-9", event: event)
        model1.markPendingGenUIActionAttempt(id: pendingID)
        model1.persistGenUIStateNow()

        let model2 = AppModel()
        let restoredPending = model2.pendingGenUIActions(for: "session-9")
        let restoredSurfaces = model2.eventStore.exportGenUISurfacesBySession()["session-9"]

        XCTAssertEqual(restoredPending.count, 1)
        XCTAssertEqual(restoredPending.first?.id, pendingID)
        XCTAssertEqual(restoredPending.first?.event.revision, 9)

        XCTAssertEqual(restoredSurfaces?.count, 1)
        XCTAssertEqual(restoredSurfaces?.first?.surfaceID, "surface-9")
        XCTAssertEqual(restoredSurfaces?.first?.revision, 9)

        persistence.clear()
    }
}
