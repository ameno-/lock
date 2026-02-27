import XCTest
@testable import AgentCockpit

@MainActor
final class CodexHistoryMergeTests: XCTestCase {
    func testCodexHistoryUsesTurnScopedReasoningIDs() {
        let payload = codexHistoryPayload(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-hydrated",
            text: "Hello from history"
        )

        let events = ACSessionTransport.mapCodexHistory(from: payload)

        guard let reasoning = firstReasoning(in: events) else {
            return XCTFail("Expected reasoning event from codex history")
        }

        XCTAssertEqual(reasoning.id, "codex/thread-1/turn/turn-1/agentMessage")
    }

    func testCodexHistoryAndDeltaShareReasoningIDForSameTurn() {
        let payload = codexHistoryPayload(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-hydrated",
            text: "Hello"
        )

        let historyEvents = ACSessionTransport.mapCodexHistory(from: payload)
        guard let historyReasoning = firstReasoning(in: historyEvents) else {
            return XCTFail("Expected history reasoning event")
        }

        let mappedDelta = JSONRPCEventAdapter.map(
            protocolMode: .codex,
            method: "item/agentMessage/delta",
            params: [
                "threadId": AnyCodable("thread-1"),
                "turnId": AnyCodable("turn-1"),
                "itemId": AnyCodable("item-delta"),
                "delta": AnyCodable(" world")
            ],
            genuiEnabled: true,
            fallbackSessionKey: nil
        )

        guard case let .reasoning(deltaReasoning)? = mappedDelta?.event else {
            return XCTFail("Expected delta reasoning event")
        }

        XCTAssertEqual(deltaReasoning.id, historyReasoning.id)
    }

    private func codexHistoryPayload(
        threadID: String,
        turnID: String,
        itemID: String,
        text: String
    ) -> AnyCodable {
        AnyCodable([
            "thread": AnyCodable([
                "id": AnyCodable(threadID),
                "turns": AnyCodable([
                    AnyCodable([
                        "id": AnyCodable(turnID),
                        "items": AnyCodable([
                            AnyCodable([
                                "id": AnyCodable(itemID),
                                "turnId": AnyCodable(turnID),
                                "type": AnyCodable("agent_message"),
                                "text": AnyCodable(text)
                            ])
                        ])
                    ])
                ])
            ])
        ])
    }

    private func firstReasoning(in events: [CanvasEvent]) -> ReasoningEvent? {
        for event in events {
            if case let .reasoning(reasoning) = event {
                return reasoning
            }
        }
        return nil
    }
}
