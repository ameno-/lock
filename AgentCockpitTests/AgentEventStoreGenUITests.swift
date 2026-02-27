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

    func testGenUIPatchMergesSurfaceComponentsByIdentity() {
        let store = AgentEventStore()
        let snapshot = GenUIEvent(
            id: "genui-3",
            schemaVersion: "v0",
            mode: .snapshot,
            title: "Plan",
            body: "Initial state",
            surfacePayload: [
                "components": AnyCodable([
                    AnyCodable([
                        "id": AnyCodable("summary"),
                        "type": AnyCodable("text"),
                        "text": AnyCodable("Baseline summary")
                    ]),
                    AnyCodable([
                        "id": AnyCodable("progress"),
                        "type": AnyCodable("progress"),
                        "value": AnyCodable(0.2)
                    ]),
                    AnyCodable([
                        "id": AnyCodable("checklist"),
                        "type": AnyCodable("checklist"),
                        "items": AnyCodable([
                            AnyCodable(["id": AnyCodable("ui"), "done": AnyCodable(false)]),
                            AnyCodable(["id": AnyCodable("acp"), "done": AnyCodable(false)])
                        ])
                    ])
                ])
            ]
        )

        let patch = GenUIEvent(
            id: "genui-3",
            schemaVersion: "v0",
            mode: .patch,
            title: "",
            body: "Progress updated",
            surfacePayload: [
                "components": AnyCodable([
                    AnyCodable([
                        "id": AnyCodable("progress"),
                        "type": AnyCodable("progress"),
                        "value": AnyCodable(0.9)
                    ]),
                    AnyCodable([
                        "id": AnyCodable("checklist"),
                        "type": AnyCodable("checklist"),
                        "items": AnyCodable([
                            AnyCodable(["id": AnyCodable("acp"), "done": AnyCodable(true)])
                        ])
                    ])
                ])
            ]
        )

        store.ingest(event: .genUI(snapshot), sessionKey: "s1")
        store.ingest(event: .genUI(patch), sessionKey: "s1")

        guard case let .genUI(merged)? = store.events(for: "s1").last,
              let components = merged.surfacePayload["components"]?.arrayValue else {
            return XCTFail("Expected merged GenUI event with components")
        }

        let componentByID: [String: [String: AnyCodable]] = Dictionary(
            uniqueKeysWithValues: components.compactMap { componentAny in
                guard let dict = componentAny.dictValue,
                      let id = dict["id"]?.stringValue else {
                    return nil
                }
                return (id, dict)
            }
        )

        XCTAssertEqual(componentByID["summary"]?["text"]?.stringValue, "Baseline summary")
        let progressValue = componentByID["progress"]?["value"]?.doubleValue
        XCTAssertNotNil(progressValue)
        XCTAssertEqual(progressValue ?? -1, 0.9, accuracy: 0.0001)

        let checklistItems = componentByID["checklist"]?["items"]?.arrayValue ?? []
        let checklistByID: [String: [String: AnyCodable]] = Dictionary(
            uniqueKeysWithValues: checklistItems.compactMap { itemAny in
                guard let dict = itemAny.dictValue,
                      let id = dict["id"]?.stringValue else {
                    return nil
                }
                return (id, dict)
            }
        )

        XCTAssertEqual(checklistByID["ui"]?["done"]?.boolValue, false)
        XCTAssertEqual(checklistByID["acp"]?["done"]?.boolValue, true)
    }

    func testCodexGenUILifecycleFromAdapterToStore() {
        let store = AgentEventStore()

        let snapshotMapped = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/completed",
            params: [
                "threadId": AnyCodable("thread-1"),
                "item": AnyCodable([
                    "id": AnyCodable("surface-1"),
                    "type": AnyCodable("genui/card"),
                    "schemaVersion": AnyCodable("v0"),
                    "title": AnyCodable("Build Panel"),
                    "text": AnyCodable("Initial snapshot"),
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("summary"),
                            "type": AnyCodable("text"),
                            "text": AnyCodable("Initial state")
                        ]),
                        AnyCodable([
                            "id": AnyCodable("progress"),
                            "type": AnyCodable("progress"),
                            "value": AnyCodable(0.1)
                        ])
                    ])
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        let patchMapped = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "genui/update",
            params: [
                "threadId": AnyCodable("thread-1"),
                "genUI": AnyCodable([
                    "id": AnyCodable("surface-1"),
                    "schemaVersion": AnyCodable("v0"),
                    "mode": AnyCodable("patch"),
                    "title": AnyCodable("Build Panel"),
                    "text": AnyCodable("Patch update"),
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("progress"),
                            "type": AnyCodable("progress"),
                            "value": AnyCodable(0.75)
                        ])
                    ])
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        guard let snapshotMapped,
              let patchMapped else {
            return XCTFail("Expected mapped snapshot and patch events")
        }

        store.ingest(event: snapshotMapped.event, sessionKey: snapshotMapped.sessionKey)
        store.ingest(event: patchMapped.event, sessionKey: patchMapped.sessionKey)

        guard case let .genUI(merged)? = store.events(for: "thread-1").last,
              let components = merged.surfacePayload["components"]?.arrayValue else {
            return XCTFail("Expected merged GenUI event for thread-1")
        }

        let componentByID: [String: [String: AnyCodable]] = Dictionary(
            uniqueKeysWithValues: components.compactMap { componentAny in
                guard let dict = componentAny.dictValue,
                      let id = dict["id"]?.stringValue else {
                    return nil
                }
                return (id, dict)
            }
        )

        XCTAssertEqual(merged.mode, .patch)
        XCTAssertEqual(merged.title, "Build Panel")
        XCTAssertEqual(merged.body, "Patch update")
        XCTAssertEqual(componentByID["summary"]?["text"]?.stringValue, "Initial state")
        let progressValue = componentByID["progress"]?["value"]?.doubleValue
        XCTAssertNotNil(progressValue)
        XCTAssertEqual(progressValue ?? -1, 0.75, accuracy: 0.0001)
    }

    func testGenUIStalePatchRevisionIsIgnored() {
        let store = AgentEventStore()
        let snapshot = GenUIEvent(
            id: "genui-4",
            schemaVersion: "v0",
            mode: .snapshot,
            surfaceID: "surface-4",
            revision: 3,
            title: "Status",
            body: "Current body"
        )
        let stalePatch = GenUIEvent(
            id: "genui-4",
            schemaVersion: "v0",
            mode: .patch,
            surfaceID: "surface-4",
            revision: 2,
            title: "Status",
            body: "Stale body"
        )

        store.ingest(event: .genUI(snapshot), sessionKey: "s1")
        store.ingest(event: .genUI(stalePatch), sessionKey: "s1")

        guard case let .genUI(merged)? = store.events(for: "s1").last else {
            return XCTFail("Expected merged GenUI event")
        }

        XCTAssertEqual(merged.revision, 3)
        XCTAssertEqual(merged.body, "Current body")
    }
}
