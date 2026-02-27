import XCTest
@testable import AgentCockpit

@MainActor
final class AgentEventStoreGenUITests: XCTestCase {
    func testGenUIPatchMergesIntoExistingSnapshot() {
        let store = AgentEventStore()
        let snapshot = GenUIEvent(
            id: "genui-1",
            schemaVersion: "v0",
            mode: .snapshot,
            title: "Checklist",
            body: "Step 1",
            actionLabel: "Open",
            actionPayload: ["route": AnyCodable("detail")]
        )
        let patch = GenUIEvent(
            id: "genui-1",
            schemaVersion: "v0",
            mode: .patch,
            title: "",
            body: "Step 1 completed",
            actionLabel: nil,
            actionPayload: ["step": AnyCodable(2)]
        )

        store.ingest(event: .genUI(snapshot), sessionKey: "s1")
        store.ingest(event: .genUI(patch), sessionKey: "s1")

        guard case let .genUI(merged)? = store.events(for: "s1").last else {
            return XCTFail("Expected merged GenUI event")
        }

        XCTAssertEqual(merged.title, "Checklist")
        XCTAssertEqual(merged.body, "Step 1 completed")
        XCTAssertEqual(merged.actionLabel, "Open")
        XCTAssertEqual(merged.mode, .patch)
        XCTAssertEqual(merged.actionPayload["route"]?.stringValue, "detail")
        XCTAssertEqual(merged.actionPayload["step"]?.intValue, 2)
    }

    func testGenUISnapshotReplacesPatchContent() {
        let store = AgentEventStore()

        store.ingest(
            event: .genUI(
                GenUIEvent(
                    id: "genui-2",
                    schemaVersion: "v0",
                    mode: .patch,
                    title: "Old",
                    body: "Old body"
                )
            ),
            sessionKey: "s1"
        )

        store.ingest(
            event: .genUI(
                GenUIEvent(
                    id: "genui-2",
                    schemaVersion: "v0",
                    mode: .snapshot,
                    title: "Fresh",
                    body: "Fresh body"
                )
            ),
            sessionKey: "s1"
        )

        guard case let .genUI(merged)? = store.events(for: "s1").last else {
            return XCTFail("Expected merged GenUI event")
        }

        XCTAssertEqual(merged.title, "Fresh")
        XCTAssertEqual(merged.body, "Fresh body")
        XCTAssertEqual(merged.mode, .snapshot)
    }
}
