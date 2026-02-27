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

    func testMapACPReplayUpdatesParsesChunksAndToolLifecycle() {
        let payload = AnyCodable([
            "updates": AnyCodable([
                AnyCodable([
                    "sessionUpdate": AnyCodable("user_message_chunk"),
                    "content": AnyCodable([
                        "type": AnyCodable("text"),
                        "text": AnyCodable("hello")
                    ])
                ]),
                AnyCodable([
                    "sessionUpdate": AnyCodable("agent_message_chunk"),
                    "content": AnyCodable([
                        "type": AnyCodable("text"),
                        "text": AnyCodable("hi from replay")
                    ])
                ]),
                AnyCodable([
                    "sessionUpdate": AnyCodable("tool_call"),
                    "toolCallId": AnyCodable("tool-1"),
                    "title": AnyCodable("Read"),
                    "rawInput": AnyCodable([
                        "path": AnyCodable("README.md")
                    ])
                ]),
                AnyCodable([
                    "sessionUpdate": AnyCodable("tool_call_update"),
                    "toolCallId": AnyCodable("tool-1"),
                    "status": AnyCodable("completed"),
                    "result": AnyCodable("ok")
                ])
            ])
        ])

        let events = ACSessionTransport.mapACPReplayUpdates(from: payload, sessionKey: "session-1")

        XCTAssertEqual(events.count, 4)
        guard case let .rawOutput(user) = events[0],
              case let .reasoning(assistant) = events[1],
              case let .toolUse(toolStart) = events[2],
              case let .toolUse(toolResult) = events[3] else {
            return XCTFail("Unexpected replay event mapping")
        }

        XCTAssertEqual(user.text, "You: hello")
        XCTAssertEqual(assistant.text, "hi from replay")
        XCTAssertEqual(toolStart.phase, .start)
        XCTAssertEqual(toolResult.phase, .result)
        XCTAssertEqual(toolResult.status, .done)
    }
}
