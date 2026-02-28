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

    func testACPToolCallUpdateInProgressStaysRunning() {
        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .acp,
            method: "session/update",
            params: [
                "sessionId": AnyCodable("acp-1"),
                "update": AnyCodable([
                    "toolCallId": AnyCodable("tool-77"),
                    "kind": AnyCodable("tool_call_update"),
                    "toolName": AnyCodable("Read"),
                    "status": AnyCodable("in_progress"),
                    "result": AnyCodable("streaming output")
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        guard case let .toolUse(event)? = mapped?.event else {
            return XCTFail("Expected ACP tool_call_update to map to tool card")
        }

        XCTAssertEqual(event.phase, .start)
        XCTAssertEqual(event.status, .running)
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

    func testCodexItemCompletedUsesTurnScopedIDWhenTurnPresent() {
        let first = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/completed",
            params: [
                "threadId": AnyCodable("thread-1"),
                "turnId": AnyCodable("turn-1"),
                "item": AnyCodable([
                    "id": AnyCodable("item-1"),
                    "type": AnyCodable("agent_message"),
                    "text": AnyCodable("Hello")
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )
        let second = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/completed",
            params: [
                "threadId": AnyCodable("thread-1"),
                "turnId": AnyCodable("turn-1"),
                "item": AnyCodable([
                    "id": AnyCodable("item-2"),
                    "type": AnyCodable("agent_message"),
                    "text": AnyCodable("Hello again")
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        guard case let .reasoning(firstReasoning)? = first?.event,
              case let .reasoning(secondReasoning)? = second?.event else {
            return XCTFail("Expected reasoning events for codex item/completed")
        }

        XCTAssertEqual(firstReasoning.id, secondReasoning.id)
        XCTAssertEqual(firstReasoning.id, "codex/thread-1/turn/turn-1/agentMessage")
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

        guard case let .rawOutput(raw)? = mapped?.event else {
            return XCTFail("Expected unsupported schema to degrade to raw output")
        }
        XCTAssertTrue(raw.text.localizedCaseInsensitiveContains("unsupported schema"))
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

    func testGenUIRevisionCorrelationAndContextMapping() {
        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "genui/update",
            params: [
                "threadId": AnyCodable("thread-1"),
                "correlationId": AnyCodable("corr-17"),
                "genUI": AnyCodable([
                    "id": AnyCodable("surface-42"),
                    "schemaVersion": AnyCodable("v0"),
                    "mode": AnyCodable("patch"),
                    "revision": AnyCodable(7),
                    "title": AnyCodable("Build"),
                    "text": AnyCodable("Updated"),
                    "context": AnyCodable([
                        "channel": AnyCodable("assistant"),
                        "priority": AnyCodable("high")
                    ])
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        guard case let .genUI(event)? = mapped?.event else {
            return XCTFail("Expected GenUI event")
        }

        XCTAssertEqual(event.surfaceID, "surface-42")
        XCTAssertEqual(event.revision, 7)
        XCTAssertEqual(event.correlationID, "corr-17")
        XCTAssertEqual(event.contextPayload["channel"]?.stringValue, "assistant")
    }

    func testCodexAgentMessageWithEmbeddedGenUIFenceMapsToGenUIEvent() {
        let embedded = """
        Here is your interactive card:
        ```genui
        {"id":"surface-inline-1","schemaVersion":"v0","mode":"snapshot","title":"Deploy Gate","text":"Build passed","context":{"channel":"assistant"},"action":{"actionId":"continue","label":"Continue"}}
        ```
        """

        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/completed",
            params: [
                "threadId": AnyCodable("thread-1"),
                "turnId": AnyCodable("turn-9"),
                "item": AnyCodable([
                    "id": AnyCodable("item-1"),
                    "type": AnyCodable("agent_message"),
                    "text": AnyCodable(embedded)
                ])
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        guard case let .genUI(event)? = mapped?.event else {
            return XCTFail("Expected embedded GenUI fence to map to GenUI event")
        }

        XCTAssertEqual(mapped?.sessionKey, "thread-1")
        XCTAssertEqual(event.surfaceID, "surface-inline-1")
        XCTAssertEqual(event.schemaVersion, "v0")
        XCTAssertEqual(event.mode, .snapshot)
        XCTAssertEqual(event.title, "Deploy Gate")
        XCTAssertEqual(event.body, "Build passed")
        XCTAssertEqual(event.contextPayload["channel"]?.stringValue, "assistant")
        XCTAssertEqual(event.contextPayload["__sourceText"]?.stringValue, embedded)
        XCTAssertEqual(event.actionPayload["actionId"]?.stringValue, "continue")
    }

    func testCodexAgentMessageChecklistSynthesizesImplicitGenUIEvent() {
        let message = """
        Sprint status:
        - [x] Build and test
        - [ ] Ship release
        Progress now at 50%.
        """

        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/completed",
            params: [
                "threadId": AnyCodable("thread-1"),
                "item": AnyCodable([
                    "id": AnyCodable("item-implicit-1"),
                    "type": AnyCodable("agent_message"),
                    "text": AnyCodable(message)
                ])
            ],
            genuiEnabled: true,
            implicitGenUIFromTextEnabled: true,
            fallbackSessionKey: nil
        )

        guard case let .genUI(event)? = mapped?.event else {
            return XCTFail("Expected checklist text to synthesize implicit GenUI")
        }

        XCTAssertEqual(event.surfaceID, "implicit-checklist")
        XCTAssertEqual(event.title, "Checklist 1/2")
        XCTAssertEqual(event.body, "- [x] Build and test\n- [ ] Ship release")
        XCTAssertEqual(event.contextPayload["__sourceText"]?.stringValue, message)
        XCTAssertEqual(event.contextPayload["__implicitFromText"]?.boolValue, true)
        XCTAssertEqual(event.contextPayload["__implicitHeuristic"]?.stringValue, "checklist")
        XCTAssertEqual(event.contextPayload["progressPercent"]?.intValue, 50)
        XCTAssertEqual(event.surfacePayload["components"]?.arrayValue?.count, 2)
    }

    func testCodexAgentMessageProgressSynthesizesImplicitGenUIEvent() {
        let message = "Release status: 65% complete after integration tests."

        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/completed",
            params: [
                "threadId": AnyCodable("thread-1"),
                "item": AnyCodable([
                    "id": AnyCodable("item-implicit-2"),
                    "type": AnyCodable("agent_message"),
                    "text": AnyCodable(message)
                ])
            ],
            genuiEnabled: true,
            implicitGenUIFromTextEnabled: true,
            fallbackSessionKey: nil
        )

        guard case let .genUI(event)? = mapped?.event else {
            return XCTFail("Expected progress text to synthesize implicit GenUI")
        }

        XCTAssertEqual(event.title, "Progress 65%")
        XCTAssertEqual(event.body, message)
        XCTAssertEqual(event.contextPayload["__sourceText"]?.stringValue, message)
        XCTAssertEqual(event.contextPayload["__implicitFromText"]?.boolValue, true)
        XCTAssertEqual(event.contextPayload["__implicitHeuristic"]?.stringValue, "progress")
        XCTAssertEqual(event.contextPayload["progressPercent"]?.intValue, 65)
        XCTAssertEqual(event.surfaceID, "implicit-progress")
        XCTAssertEqual(event.surfacePayload["components"]?.arrayValue?.count, 2)
    }

    func testImplicitGenUISynthesisDisabledFallsBackToReasoning() {
        let message = """
        - [x] Build and test
        - [ ] Ship release
        """

        let mapped = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/completed",
            params: [
                "threadId": AnyCodable("thread-1"),
                "item": AnyCodable([
                    "id": AnyCodable("item-implicit-3"),
                    "type": AnyCodable("agent_message"),
                    "text": AnyCodable(message)
                ])
            ],
            genuiEnabled: true,
            implicitGenUIFromTextEnabled: false,
            fallbackSessionKey: nil
        )

        guard case let .reasoning(event)? = mapped?.event else {
            return XCTFail("Expected reasoning fallback when implicit synthesis is disabled")
        }
        XCTAssertEqual(event.text, message)
    }
}
