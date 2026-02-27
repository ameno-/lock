import XCTest
@testable import AgentCockpit

final class ACPProtocolParserTests: XCTestCase {
    func testParseSessionUpdateUserMessage() {
        let context = ACPProtocolParser.parseSessionUpdate(
            params: [
                "sessionId": AnyCodable("session-1"),
                "update": AnyCodable([
                    "id": AnyCodable("m-1"),
                    "sessionUpdate": AnyCodable("user_message"),
                    "text": AnyCodable("hello")
                ])
            ],
            fallbackSessionID: nil
        )

        XCTAssertEqual(context.sessionID, "session-1")
        XCTAssertEqual(context.type, .userMessage)
        XCTAssertEqual(context.updateID, "m-1")
        XCTAssertEqual(context.text, "hello")
    }

    func testParseSessionUpdateToolCallAndUpdate() {
        let startContext = ACPProtocolParser.parseSessionUpdate(
            params: [
                "sessionId": AnyCodable("session-1"),
                "update": AnyCodable([
                    "toolCallId": AnyCodable("tool-1"),
                    "kind": AnyCodable("tool_call"),
                    "toolName": AnyCodable("Read"),
                    "arguments": AnyCodable([
                        "path": AnyCodable("README.md")
                    ])
                ])
            ],
            fallbackSessionID: nil
        )

        XCTAssertEqual(startContext.type, .toolCall)
        XCTAssertEqual(startContext.toolName, "Read")
        XCTAssertEqual(startContext.toolCallID, "tool-1")
        XCTAssertEqual(startContext.toolInput, #"{"path":"README.md"}"#)

        let updateContext = ACPProtocolParser.parseSessionUpdate(
            params: [
                "sessionId": AnyCodable("session-1"),
                "update": AnyCodable([
                    "toolCallId": AnyCodable("tool-1"),
                    "kind": AnyCodable("tool_call_update_error"),
                    "toolName": AnyCodable("Read"),
                    "result": AnyCodable("permission denied")
                ])
            ],
            fallbackSessionID: nil
        )

        XCTAssertEqual(updateContext.type, .toolCallUpdate)
        XCTAssertEqual(updateContext.toolResult, "permission denied")
        XCTAssertTrue(updateContext.isError)
    }

    func testParseSessionUpdateDetectsGenUIFromMarker() {
        let context = ACPProtocolParser.parseSessionUpdate(
            params: [
                "sessionId": AnyCodable("session-1"),
                "update": AnyCodable([
                    "sessionUpdate": AnyCodable("genui/update"),
                    "title": AnyCodable("Checklist"),
                    "text": AnyCodable("Step complete")
                ])
            ],
            fallbackSessionID: nil
        )

        XCTAssertEqual(context.type, .genUI)
    }

    func testParseSessionUpdateUsesFallbackSessionID() {
        let context = ACPProtocolParser.parseSessionUpdate(
            params: [
                "update": AnyCodable([
                    "sessionUpdate": AnyCodable("agent_message"),
                    "text": AnyCodable("ready")
                ])
            ],
            fallbackSessionID: "fallback-session"
        )

        XCTAssertEqual(context.sessionID, "fallback-session")
        XCTAssertEqual(context.type, .agentMessage)
        XCTAssertEqual(context.text, "ready")
    }
}
