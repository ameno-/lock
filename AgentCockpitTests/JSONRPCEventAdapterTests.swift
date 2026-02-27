import XCTest
@testable import AgentCockpit

final class JSONRPCEventAdapterTests: XCTestCase {
    func testACPUserMessageMapsToRawOutput() {
        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .acp,
            method: "session/update",
            params: [
                "sessionId": AnyCodable("acp-1"),
                "update": AnyCodable([
                    "id": AnyCodable("msg-1"),
                    "sessionUpdate": AnyCodable("user_message"),
                    "text": AnyCodable("hello")
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        XCTAssertEqual(mapped?.sessionKey, "acp-1")
        guard case let .rawOutput(event)? = mapped?.event else {
            return XCTFail("Expected ACP user_message to map to raw output")
        }
        XCTAssertEqual(event.id, "acp/acp-1/user/msg-1")
        XCTAssertEqual(event.text, "You: hello")
    }

    func testACPToolCallUpdateMapsToResultToolCard() {
        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .acp,
            method: "session/update",
            params: [
                "sessionId": AnyCodable("acp-1"),
                "update": AnyCodable([
                    "toolCallId": AnyCodable("tool-77"),
                    "kind": AnyCodable("tool_call_update"),
                    "toolName": AnyCodable("Read"),
                    "result": AnyCodable("ok")
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        guard case let .toolUse(event)? = mapped?.event else {
            return XCTFail("Expected ACP tool_call_update to map to tool card")
        }

        XCTAssertEqual(event.id, "acp/acp-1/tool/tool-77")
        XCTAssertEqual(event.toolName, "Read")
        XCTAssertEqual(event.phase, .result)
        XCTAssertEqual(event.result, "ok")
        XCTAssertEqual(event.status, .done)
    }

    func testCodexDeltaUsesTurnScopedIDToAvoidFragmentation() {
        let first = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/agentMessage/delta",
            params: [
                "threadId": AnyCodable("thread-1"),
                "turnId": AnyCodable("turn-1"),
                "itemId": AnyCodable("item-1"),
                "delta": AnyCodable("Hello")
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )
        let second = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/agentMessage/delta",
            params: [
                "threadId": AnyCodable("thread-1"),
                "turnId": AnyCodable("turn-1"),
                "itemId": AnyCodable("item-2"),
                "delta": AnyCodable(" world")
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        guard case let .reasoning(firstReasoning)? = first?.event,
              case let .reasoning(secondReasoning)? = second?.event else {
            return XCTFail("Expected reasoning events for codex deltas")
        }

        XCTAssertEqual(firstReasoning.id, secondReasoning.id)
    }

    func testGenUIDisabledFallsBackToRawOutput() {
        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .acp,
            method: "session/update",
            params: [
                "sessionId": AnyCodable("s1"),
                "update": AnyCodable([
                    "sessionUpdate": AnyCodable("genui/update"),
                    "genUI": AnyCodable([
                        "id": AnyCodable("surface-1"),
                        "schemaVersion": AnyCodable("v0"),
                        "title": AnyCodable("Widget"),
                        "text": AnyCodable("Hello")
                    ])
                ])
            ],
            genuiEnabled: false,
            fallbackSessionKey: nil
        )

        guard case let .rawOutput(raw)? = mapped?.event else {
            return XCTFail("Expected raw output fallback when GenUI is disabled")
        }

        XCTAssertTrue(raw.text.localizedCaseInsensitiveContains("disabled"))
    }

    func testGenUIRequiresSupportedSchemaVersion() {
        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/completed",
            params: [
                "threadId": AnyCodable("thread-1"),
                "item": AnyCodable([
                    "id": AnyCodable("item-1"),
                    "type": AnyCodable("genui/card"),
                    "schemaVersion": AnyCodable("v2"),
                    "title": AnyCodable("Unsupported"),
                    "text": AnyCodable("Payload")
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        guard let mapped else {
            return XCTFail("Expected non-nil fallback mapping")
        }

        if case .genUI = mapped.event {
            XCTFail("Unsupported schema should not map to GenUI event")
        }
    }

    func testGenUIPatchModeMapping() {
        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/completed",
            params: [
                "threadId": AnyCodable("thread-1"),
                "item": AnyCodable([
                    "id": AnyCodable("item-1"),
                    "type": AnyCodable("genui/card"),
                    "schemaVersion": AnyCodable("v0"),
                    "mode": AnyCodable("patch"),
                    "title": AnyCodable("Checklist"),
                    "text": AnyCodable("Step updated")
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        guard case let .genUI(event)? = mapped?.event else {
            return XCTFail("Expected GenUI event")
        }

        XCTAssertEqual(event.schemaVersion, "v0")
        XCTAssertEqual(event.mode, .patch)
    }
}
