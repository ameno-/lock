import XCTest
@testable import AgentCockpit

@MainActor
final class ACPSessionHistoryParsingTests: XCTestCase {
    func testMapACPHistoryParsesUserAssistantAndSystemMessages() {
        let payload = AnyCodable([
            "history": AnyCodable([
                AnyCodable([
                    "id": AnyCodable("m1"),
                    "role": AnyCodable("user"),
                    "content": AnyCodable("hello")
                ]),
                AnyCodable([
                    "id": AnyCodable("m2"),
                    "role": AnyCodable("assistant"),
                    "content": AnyCodable([
                        AnyCodable([
                            "type": AnyCodable("text"),
                            "text": AnyCodable("hi there")
                        ])
                    ])
                ]),
                AnyCodable([
                    "id": AnyCodable("m3"),
                    "role": AnyCodable("system"),
                    "text": AnyCodable("system note")
                ])
            ])
        ])

        let events = ACSessionTransport.mapACPHistory(from: payload, sessionKey: "session-1")

        XCTAssertEqual(events.count, 3)

        guard case let .rawOutput(userEvent) = events[0] else {
            return XCTFail("Expected user raw output event")
        }
        XCTAssertEqual(userEvent.text, "You: hello")

        guard case let .reasoning(assistantEvent) = events[1] else {
            return XCTFail("Expected assistant reasoning event")
        }
        XCTAssertEqual(assistantEvent.text, "hi there")

        guard case let .rawOutput(systemEvent) = events[2] else {
            return XCTFail("Expected system raw output event")
        }
        XCTAssertEqual(systemEvent.text, "system note")
    }
}
