import XCTest
@testable import AgentCockpit

@MainActor
final class GenUIIntegrationReplayTests: XCTestCase {
    func testCodexReplayFixtureMaintainsLatestRevision() {
        let store = AgentEventStore()
        let fixture = codexFixture()

        replay(fixture, protocolMode: .codex, into: store)

        guard case let .genUI(event)? = store.events(for: "thread-fixture").last else {
            return XCTFail("Expected merged GenUI event")
        }

        XCTAssertEqual(event.surfaceID, "build-panel")
        XCTAssertEqual(event.revision, 2)
        XCTAssertEqual(event.body, "Patch rev2")
        XCTAssertEqual(event.contextPayload["phase"]?.stringValue, "verify")
    }

    func testACPReplayFixturePreservesContextAndCorrelation() {
        let store = AgentEventStore()
        let fixture = acpFixture()

        replay(fixture, protocolMode: .acp, into: store)

        guard case let .genUI(event)? = store.events(for: "acp-fixture").last else {
            return XCTFail("Expected ACP GenUI event")
        }

        XCTAssertEqual(event.surfaceID, "surface-acp")
        XCTAssertEqual(event.revision, 2)
        XCTAssertEqual(event.correlationID, "corr-acp-1")
        XCTAssertEqual(event.contextPayload["source"]?.stringValue, "acp")
    }

    func testPiACPReplayFixtureSupportsSnakeCaseVariants() {
        let store = AgentEventStore()
        let fixture = piAcpFixture()

        replay(fixture, protocolMode: .acp, into: store)

        guard case let .genUI(event)? = store.events(for: "pi-fixture").last else {
            return XCTFail("Expected pi-acp compatible GenUI event")
        }

        XCTAssertEqual(event.surfaceID, "pi-surface")
        XCTAssertEqual(event.revision, 3)
        XCTAssertEqual(event.correlationID, "pi-corr-7")
        XCTAssertEqual(event.contextPayload["source"]?.stringValue, "pi-acp")
        XCTAssertEqual(event.contextPayload["channel"]?.stringValue, "assistant")
    }

    private typealias FixtureStep = (method: String, params: [String: AnyCodable])

    private func replay(
        _ steps: [FixtureStep],
        protocolMode: ACServerProtocol,
        into store: AgentEventStore
    ) {
        for step in steps {
            guard let mapped = JSONRPCEventAdapter.map(
                protocolMode: protocolMode,
                method: step.method,
                params: step.params,
                genuiEnabled: true,
                fallbackSessionKey: nil
            ) else {
                continue
            }
            store.ingest(event: mapped.event, sessionKey: mapped.sessionKey)
        }
    }

    private func codexFixture() -> [FixtureStep] {
        [
            (
                method: "item/completed",
                params: [
                    "threadId": AnyCodable("thread-fixture"),
                    "item": AnyCodable([
                        "id": AnyCodable("build-panel"),
                        "type": AnyCodable("genui/card"),
                        "schemaVersion": AnyCodable("v0"),
                        "revision": AnyCodable(1),
                        "title": AnyCodable("Build Panel"),
                        "text": AnyCodable("Snapshot rev1"),
                        "context": AnyCodable([
                            "phase": AnyCodable("plan")
                        ])
                    ])
                ]
            ),
            (
                method: "genui/update",
                params: [
                    "threadId": AnyCodable("thread-fixture"),
                    "genUI": AnyCodable([
                        "id": AnyCodable("build-panel"),
                        "schemaVersion": AnyCodable("v0"),
                        "mode": AnyCodable("patch"),
                        "revision": AnyCodable(2),
                        "title": AnyCodable("Build Panel"),
                        "text": AnyCodable("Patch rev2"),
                        "context": AnyCodable([
                            "phase": AnyCodable("verify")
                        ])
                    ])
                ]
            ),
            (
                method: "genui/update",
                params: [
                    "threadId": AnyCodable("thread-fixture"),
                    "genUI": AnyCodable([
                        "id": AnyCodable("build-panel"),
                        "schemaVersion": AnyCodable("v0"),
                        "mode": AnyCodable("patch"),
                        "revision": AnyCodable(1),
                        "title": AnyCodable("Build Panel"),
                        "text": AnyCodable("Stale patch"),
                        "context": AnyCodable([
                            "phase": AnyCodable("stale")
                        ])
                    ])
                ]
            )
        ]
    }

    private func acpFixture() -> [FixtureStep] {
        [
            (
                method: "session/update",
                params: [
                    "sessionId": AnyCodable("acp-fixture"),
                    "update": AnyCodable([
                        "sessionUpdate": AnyCodable("genui/update"),
                        "genUI": AnyCodable([
                            "id": AnyCodable("surface-acp"),
                            "schemaVersion": AnyCodable("v0"),
                            "revision": AnyCodable(1),
                            "title": AnyCodable("ACP Surface"),
                            "text": AnyCodable("Snapshot"),
                            "correlationId": AnyCodable("corr-acp-1"),
                            "context": AnyCodable([
                                "source": AnyCodable("acp")
                            ])
                        ])
                    ])
                ]
            ),
            (
                method: "session/update",
                params: [
                    "sessionId": AnyCodable("acp-fixture"),
                    "update": AnyCodable([
                        "sessionUpdate": AnyCodable("genui/update"),
                        "genUI": AnyCodable([
                            "id": AnyCodable("surface-acp"),
                            "schemaVersion": AnyCodable("v0"),
                            "mode": AnyCodable("patch"),
                            "revision": AnyCodable(2),
                            "title": AnyCodable("ACP Surface"),
                            "text": AnyCodable("Patch"),
                            "correlationId": AnyCodable("corr-acp-1"),
                            "context": AnyCodable([
                                "source": AnyCodable("acp")
                            ])
                        ])
                    ])
                ]
            )
        ]
    }

    private func piAcpFixture() -> [FixtureStep] {
        [
            (
                method: "session/update",
                params: [
                    "sessionId": AnyCodable("pi-fixture"),
                    "update": AnyCodable([
                        "sessionUpdate": AnyCodable("genui/update"),
                        "gen_ui": AnyCodable([
                            "surface_id": AnyCodable("pi-surface"),
                            "schema_version": AnyCodable("v0"),
                            "update_mode": AnyCodable("patch"),
                            "update_revision": AnyCodable(3),
                            "title": AnyCodable("Pi Panel"),
                            "text": AnyCodable("Patch rev3"),
                            "correlation_id": AnyCodable("pi-corr-7"),
                            "callback_context": AnyCodable([
                                "source": AnyCodable("pi-acp"),
                                "channel": AnyCodable("assistant")
                            ])
                        ])
                    ])
                ]
            )
        ]
    }
}
