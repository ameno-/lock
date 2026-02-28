import XCTest
@testable import AgentCockpit

final class GenUIRenderingEngineTests: XCTestCase {
    func testDefaultParserProducesTypedComponents() {
        let parser = DefaultGenUISurfaceParser()

        let components = parser.parse(
            surfacePayload: [
                "components": AnyCodable([
                    AnyCodable([
                        "id": AnyCodable("summary"),
                        "type": AnyCodable("text"),
                        "text": AnyCodable("Plan summary")
                    ]),
                    AnyCodable([
                        "id": AnyCodable("progress"),
                        "type": AnyCodable("progress"),
                        "value": AnyCodable(0.45)
                    ]),
                    AnyCodable([
                        "id": AnyCodable("actions"),
                        "type": AnyCodable("actions"),
                        "actions": AnyCodable([
                            AnyCodable([
                                "actionId": AnyCodable("open_logs"),
                                "label": AnyCodable("Open logs"),
                                "channel": AnyCodable("assistant")
                            ])
                        ])
                    ])
                ])
            ]
        )

        XCTAssertEqual(components.count, 3)

        guard case let .text(text)? = components.first else {
            return XCTFail("Expected first component to be text")
        }
        XCTAssertEqual(text.id, "summary")
        XCTAssertEqual(text.value, "Plan summary")

        guard case let .actions(actions)? = components.last else {
            return XCTFail("Expected last component to be actions")
        }
        XCTAssertEqual(actions.items.count, 1)
        XCTAssertEqual(actions.items[0].id, "open_logs")
        XCTAssertEqual(actions.items[0].label, "Open logs")
        XCTAssertEqual(actions.items[0].payload["channel"]?.stringValue, "assistant")
    }

    func testDefaultEngineUsesParserOutput() {
        let engine = DefaultGenUIRenderingEngine()
        let event = GenUIEvent(
            id: "genui/test/surface-1",
            schemaVersion: "v0",
            mode: .snapshot,
            title: "Panel",
            body: "Body",
            surfacePayload: [
                "components": AnyCodable([
                    AnyCodable([
                        "id": AnyCodable("metric-1"),
                        "type": AnyCodable("metric"),
                        "label": AnyCodable("Tokens"),
                        "value": AnyCodable("12k")
                    ])
                ])
            ]
        )

        let components = engine.components(for: event)
        XCTAssertEqual(components.count, 1)

        guard case let .metric(metric)? = components.first else {
            return XCTFail("Expected metric component")
        }
        XCTAssertEqual(metric.id, "metric-1")
        XCTAssertEqual(metric.label, "Tokens")
        XCTAssertEqual(metric.value, "12k")
    }
}
