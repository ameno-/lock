import XCTest
@testable import AgentCockpit

final class WorkTranscriptMapperTests: XCTestCase {
    func testDisplayModeToPolicyMappingParity() {
        XCTAssertEqual(WorkTranscriptDisplayPolicy(displayMode: .standard), .standard)
        XCTAssertEqual(WorkTranscriptDisplayPolicy(displayMode: .debug), .debug)
        XCTAssertEqual(WorkTranscriptDisplayPolicy(displayMode: .textOnly), .textOnly)
    }

    func testMapsUserAssistantAndSystemMessages() {
        let events: [CanvasEvent] = [
            .rawOutput(RawOutputEvent(id: "u1", text: "You: hello", hookEvent: "session/update")),
            .reasoning(ReasoningEvent(id: "a1", text: "hi there", isThinking: false)),
            .rawOutput(RawOutputEvent(id: "s1", text: "session resumed", hookEvent: "session/info"))
        ]

        let entries = WorkTranscriptMapper.entries(from: events)

        XCTAssertEqual(entries.count, 3)
        guard case .message(let userMessage) = entries[0],
              case .message(let assistantMessage) = entries[1],
              case .message(let systemMessage) = entries[2] else {
            return XCTFail("Expected three message entries")
        }

        XCTAssertEqual(userMessage.role, .user)
        XCTAssertEqual(userMessage.text, "hello")
        XCTAssertEqual(assistantMessage.role, .assistant)
        XCTAssertEqual(systemMessage.role, .system)
    }

    func testMergesAdjacentAssistantMessagesWithinWindow() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [CanvasEvent] = [
            .reasoning(ReasoningEvent(id: "a1", text: "Line one", isThinking: false, timestamp: base)),
            .reasoning(ReasoningEvent(id: "a2", text: "Line two", isThinking: false, timestamp: base.addingTimeInterval(2)))
        ]

        let entries = WorkTranscriptMapper.entries(from: events)

        XCTAssertEqual(entries.count, 1)
        guard case .message(let assistant) = entries[0] else {
            return XCTFail("Expected merged assistant message")
        }
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertTrue(assistant.text.contains("Line one"))
        XCTAssertTrue(assistant.text.contains("Line two"))
    }

    func testDoesNotMergeAcrossRolesOrUserMessages() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [CanvasEvent] = [
            .reasoning(ReasoningEvent(id: "a1", text: "One", isThinking: false, timestamp: base)),
            .rawOutput(RawOutputEvent(id: "u1", text: "You: two", hookEvent: "session/update", timestamp: base.addingTimeInterval(1))),
            .reasoning(ReasoningEvent(id: "a2", text: "Three", isThinking: false, timestamp: base.addingTimeInterval(2)))
        ]

        let entries = WorkTranscriptMapper.entries(from: events)

        XCTAssertEqual(entries.count, 3)
    }

    func testKeepsToolEventsAsEventRows() {
        let events: [CanvasEvent] = [
            .toolUse(ToolUseEvent(id: "t1", toolName: "Read", phase: .start, input: "README.md", status: .running))
        ]

        let entries = WorkTranscriptMapper.entries(from: events)
        XCTAssertEqual(entries.count, 1)
        guard case .event(let rowEvent) = entries[0] else {
            return XCTFail("Expected non-message event row")
        }

        if case .toolUse = rowEvent {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected tool event")
        }
    }

    func testStandardPolicySuppressesNearbyTaggedAssistantScaffold() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let scaffold = """
        ```genui
        {"title":"Plan","text":"Use GenUI"}
        ```
        """
        let events: [CanvasEvent] = [
            .reasoning(ReasoningEvent(id: "a1", text: scaffold, isThinking: false, timestamp: base)),
            .genUI(makeGenUIEvent(id: "g1", title: "Plan", body: "Use GenUI", timestamp: base.addingTimeInterval(1)))
        ]

        let entries = WorkTranscriptMapper.entries(from: events, policy: .standard)

        XCTAssertEqual(entries.count, 1)
        guard case .event(let event) = entries[0], case .genUI(let genUI) = event else {
            return XCTFail("Expected only GenUI event row in standard mode")
        }
        XCTAssertEqual(genUI.id, "g1")
    }

    func testStandardPolicyKeepsTaggedAssistantTextWhenNotNearGenUI() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let scaffold = "<genui>{\"title\":\"Plan\"}</genui>"
        let events: [CanvasEvent] = [
            .reasoning(ReasoningEvent(id: "a1", text: scaffold, isThinking: false, timestamp: base)),
            .genUI(makeGenUIEvent(id: "g1", title: "Plan", body: "Use GenUI", timestamp: base.addingTimeInterval(30)))
        ]

        let entries = WorkTranscriptMapper.entries(from: events, policy: .standard)

        XCTAssertEqual(entries.count, 2)
        guard case .message(let assistant) = entries[0] else {
            return XCTFail("Expected scaffold text to remain when distant from GenUI")
        }
        XCTAssertEqual(assistant.role, .assistant)
        guard case .event(let event) = entries[1], case .genUI = event else {
            return XCTFail("Expected GenUI event row")
        }
    }

    func testTextOnlyPolicySuppressesNearbyTaggedAssistantScaffold() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let scaffold = """
        ```genui
        {"title":"Plan","text":"Use GenUI"}
        ```
        """
        let events: [CanvasEvent] = [
            .reasoning(ReasoningEvent(id: "a1", text: scaffold, isThinking: false, timestamp: base)),
            .genUI(
                makeGenUIEvent(
                    id: "g1",
                    title: "Plan",
                    body: "Use GenUI",
                    contextPayload: ["__sourceText": AnyCodable("From source")],
                    timestamp: base.addingTimeInterval(1)
                )
            )
        ]

        let entries = WorkTranscriptMapper.entries(from: events, policy: .textOnly)

        XCTAssertEqual(entries.count, 1)
        guard case .message(let assistant) = entries[0] else {
            return XCTFail("Expected only fallback text row in textOnly mode")
        }
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.text, "From source")
    }

    func testDebugPolicyShowsGenUIEventAndContextSourceText() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [CanvasEvent] = [
            .genUI(
                makeGenUIEvent(
                    id: "g1",
                    title: "Plan",
                    body: "Use GenUI",
                    contextPayload: ["__sourceText": AnyCodable("Assistant source text")],
                    timestamp: base
                )
            )
        ]

        let entries = WorkTranscriptMapper.entries(from: events, policy: .debug)

        XCTAssertEqual(entries.count, 2)
        guard case .event(let event) = entries[0], case .genUI(let genUI) = event else {
            return XCTFail("Expected GenUI event row")
        }
        XCTAssertEqual(genUI.id, "g1")
        guard case .message(let source) = entries[1] else {
            return XCTFail("Expected assistant source text message")
        }
        XCTAssertEqual(source.role, .assistant)
        XCTAssertEqual(source.text, "Assistant source text")
        XCTAssertEqual(source.sourceEventIDs, ["g1"])
    }

    func testDebugPolicyKeepsNearbyTaggedAssistantScaffold() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let scaffold = "<genui>{\"title\":\"Plan\"}</genui>"
        let events: [CanvasEvent] = [
            .reasoning(ReasoningEvent(id: "a1", text: scaffold, isThinking: false, timestamp: base)),
            .genUI(makeGenUIEvent(id: "g1", title: "Plan", body: "Use GenUI", timestamp: base.addingTimeInterval(1)))
        ]

        let entries = WorkTranscriptMapper.entries(from: events, policy: .debug)

        XCTAssertEqual(entries.count, 2)
        guard case .message(let scaffoldMessage) = entries[0] else {
            return XCTFail("Expected scaffold text message to remain in debug mode")
        }
        XCTAssertEqual(scaffoldMessage.role, .assistant)
        guard case .event(let event) = entries[1], case .genUI = event else {
            return XCTFail("Expected GenUI event row")
        }
    }

    func testTextOnlyPolicyPrefersSourceTextAndFallsBackToTitleBody() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [CanvasEvent] = [
            .genUI(
                makeGenUIEvent(
                    id: "g1",
                    title: "Card Title",
                    body: "Card Body",
                    contextPayload: ["__sourceText": AnyCodable("From source")],
                    timestamp: base
                )
            ),
            .genUI(
                makeGenUIEvent(
                    id: "g2",
                    title: "Fallback Title",
                    body: "Fallback Body",
                    timestamp: base.addingTimeInterval(8)
                )
            )
        ]

        let entries = WorkTranscriptMapper.entries(from: events, policy: .textOnly)

        XCTAssertEqual(entries.count, 2)
        guard case .message(let first) = entries[0],
              case .message(let second) = entries[1] else {
            return XCTFail("Expected two message rows in textOnly mode")
        }

        XCTAssertEqual(first.role, .assistant)
        XCTAssertEqual(first.text, "From source")
        XCTAssertEqual(second.role, .assistant)
        XCTAssertEqual(second.text, "Fallback Title\n\nFallback Body")
    }

    func testActivityGenUIStandardMapsToolUseIntoGenUICard() {
        let events: [CanvasEvent] = [
            .toolUse(
                ToolUseEvent(
                    id: "tool-1",
                    toolName: "bash",
                    phase: .result,
                    input: "ls -la",
                    result: "README.md",
                    status: .done
                )
            )
        ]

        let entries = WorkTranscriptMapper.entries(
            from: events,
            policy: .standard,
            activityGenUIEnabled: true
        )

        XCTAssertEqual(entries.count, 1)
        guard case .event(let mappedEvent) = entries[0],
              case .genUI(let genUI) = mappedEvent else {
            return XCTFail("Expected synthesized GenUI event")
        }

        XCTAssertEqual(genUI.contextPayload["__synthetic"]?.boolValue, true)
        XCTAssertEqual(genUI.contextPayload["__activitySource"]?.stringValue, "tool_use")
        XCTAssertEqual(genUI.title, "Tool: bash")
        XCTAssertEqual(genUI.surfacePayload["components"]?.arrayValue?.count, 6)
    }

    func testActivityGenUIStandardMapsThinkingIntoGenUICard() {
        let events: [CanvasEvent] = [
            .reasoning(
                ReasoningEvent(
                    id: "think-1",
                    text: "Evaluating file layout and command output.",
                    isThinking: true
                )
            )
        ]

        let entries = WorkTranscriptMapper.entries(
            from: events,
            policy: .standard,
            activityGenUIEnabled: true
        )

        XCTAssertEqual(entries.count, 1)
        guard case .event(let mappedEvent) = entries[0],
              case .genUI(let genUI) = mappedEvent else {
            return XCTFail("Expected synthesized GenUI thinking card")
        }
        XCTAssertEqual(genUI.title, "Thinking")
        XCTAssertEqual(genUI.contextPayload["__activitySource"]?.stringValue, "thinking")
    }

    func testActivityGenUIDebugKeepsUnderlyingMessageAlongsideCard() {
        let events: [CanvasEvent] = [
            .reasoning(
                ReasoningEvent(
                    id: "reply-1",
                    text: "Done. Build is green.",
                    isThinking: false
                )
            )
        ]

        let entries = WorkTranscriptMapper.entries(
            from: events,
            policy: .debug,
            activityGenUIEnabled: true
        )

        XCTAssertEqual(entries.count, 2)
        guard case .event(let mappedEvent) = entries[0],
              case .genUI = mappedEvent else {
            return XCTFail("Expected synthesized GenUI event first")
        }
        guard case .message(let message) = entries[1] else {
            return XCTFail("Expected original message row in debug mode")
        }
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.text, "Done. Build is green.")
    }

    func testActivityGenUITextOnlySkipsSynthesis() {
        let events: [CanvasEvent] = [
            .reasoning(
                ReasoningEvent(
                    id: "reply-2",
                    text: "Done. Build is green.",
                    isThinking: false
                )
            )
        ]

        let entries = WorkTranscriptMapper.entries(
            from: events,
            policy: .textOnly,
            activityGenUIEnabled: true
        )

        XCTAssertEqual(entries.count, 1)
        guard case .message(let message) = entries[0] else {
            return XCTFail("Expected plain message row in text-only mode")
        }
        XCTAssertEqual(message.role, .assistant)
    }

    func testActivityGenUIStandardMapsUserAcknowledgementIntoGenUICard() {
        let events: [CanvasEvent] = [
            .rawOutput(
                RawOutputEvent(
                    id: "user-ack-1",
                    text: "You: summarize latest failures",
                    hookEvent: "session/update"
                )
            )
        ]

        let entries = WorkTranscriptMapper.entries(
            from: events,
            policy: .standard,
            activityGenUIEnabled: true
        )

        XCTAssertEqual(entries.count, 1)
        guard case .event(let mappedEvent) = entries[0],
              case .genUI(let genUI) = mappedEvent else {
            return XCTFail("Expected synthesized user acknowledgement GenUI event")
        }
        XCTAssertEqual(genUI.title, "Message Acknowledged")
        XCTAssertEqual(genUI.contextPayload["__activitySource"]?.stringValue, "user_ack")
    }

    private func makeGenUIEvent(
        id: String,
        title: String,
        body: String,
        contextPayload: [String: AnyCodable] = [:],
        timestamp: Date
    ) -> GenUIEvent {
        GenUIEvent(
            id: id,
            title: title,
            body: body,
            contextPayload: contextPayload,
            timestamp: timestamp
        )
    }
}
