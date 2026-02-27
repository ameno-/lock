import XCTest
@testable import AgentCockpit

final class CodexProtocolParserTests: XCTestCase {
    func testParseThreadListMapsRows() {
        let payload = AnyCodable([
            "data": AnyCodable([
                AnyCodable([
                    "id": AnyCodable("thread-1"),
                    "name": AnyCodable("Alpha"),
                    "preview": AnyCodable("Latest update"),
                    "status": AnyCodable([
                        "type": AnyCodable("active")
                    ]),
                    "createdAt": AnyCodable("2026-02-26T00:00:00Z"),
                    "updatedAt": AnyCodable("2026-02-26T01:00:00Z")
                ])
            ])
        ])

        let threads = CodexProtocolParser.parseThreadList(from: payload)

        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].id, "thread-1")
        XCTAssertEqual(threads[0].name, "Alpha")
        XCTAssertEqual(threads[0].preview, "Latest update")
        XCTAssertEqual(threads[0].statusType, "active")
        XCTAssertTrue(threads[0].isRunning)
        XCTAssertNotNil(threads[0].createdAt)
        XCTAssertNotNil(threads[0].updatedAt)
    }

    func testParseThreadReadsThreadEnvelope() {
        let payload = AnyCodable([
            "thread": AnyCodable([
                "id": AnyCodable("thread-started"),
                "preview": AnyCodable("New thread"),
                "status": AnyCodable("idle"),
                "createdAt": AnyCodable(1_708_000_000)
            ])
        ])

        let thread = CodexProtocolParser.parseThread(from: payload)

        XCTAssertEqual(thread?.id, "thread-started")
        XCTAssertEqual(thread?.preview, "New thread")
        XCTAssertEqual(thread?.statusType, "idle")
        XCTAssertEqual(thread?.isRunning, false)
        XCTAssertNotNil(thread?.createdAt)
    }

    func testParseHistoryNormalizesItemTypesAndText() {
        let payload = AnyCodable([
            "thread": AnyCodable([
                "id": AnyCodable("thread-1"),
                "turns": AnyCodable([
                    AnyCodable([
                        "id": AnyCodable("turn-1"),
                        "items": AnyCodable([
                            AnyCodable([
                                "id": AnyCodable("u1"),
                                "type": AnyCodable("user_message"),
                                "content": AnyCodable([
                                    AnyCodable([
                                        "type": AnyCodable("text"),
                                        "text": AnyCodable("hello")
                                    ])
                                ])
                            ]),
                            AnyCodable([
                                "id": AnyCodable("a1"),
                                "type": AnyCodable("agent-message"),
                                "content": AnyCodable([
                                    AnyCodable([
                                        "text": AnyCodable("hi")
                                    ])
                                ])
                            ]),
                            AnyCodable([
                                "id": AnyCodable("r1"),
                                "type": AnyCodable("reasoning"),
                                "summary": AnyCodable([
                                    AnyCodable([
                                        "text": AnyCodable("thinking...")
                                    ])
                                ])
                            ]),
                            AnyCodable([
                                "id": AnyCodable("c1"),
                                "type": AnyCodable("command_execution"),
                                "command": AnyCodable([AnyCodable("ls"), AnyCodable("-la")]),
                                "status": AnyCodable("completed"),
                                "stdout": AnyCodable("ok")
                            ]),
                            AnyCodable([
                                "id": AnyCodable("f1"),
                                "type": AnyCodable("file_change"),
                                "changes": AnyCodable([
                                    AnyCodable([
                                        "path": AnyCodable("README.md"),
                                        "kind": AnyCodable("edit")
                                    ])
                                ])
                            ])
                        ])
                    ])
                ])
            ])
        ])

        let history = CodexProtocolParser.parseHistory(from: payload)

        XCTAssertEqual(history.threadID, "thread-1")
        XCTAssertEqual(history.turns.count, 1)
        XCTAssertEqual(history.turns[0].items.count, 5)

        XCTAssertEqual(history.turns[0].items[0].type, .userMessage)
        XCTAssertEqual(history.turns[0].items[0].text, "hello")

        XCTAssertEqual(history.turns[0].items[1].type, .agentMessage)
        XCTAssertEqual(history.turns[0].items[1].text, "hi")

        XCTAssertEqual(history.turns[0].items[2].type, .reasoning)
        XCTAssertEqual(history.turns[0].items[2].text, "thinking...")

        XCTAssertEqual(history.turns[0].items[3].type, .commandExecution)
        XCTAssertEqual(history.turns[0].items[3].commandText, "ls -la")
        XCTAssertEqual(history.turns[0].items[3].commandOutput, "ok")

        XCTAssertEqual(history.turns[0].items[4].type, .fileChange)
        XCTAssertEqual(history.turns[0].items[4].fileChanges.first?.path, "README.md")
    }

    func testParseItemUsesFallbackTurnAndToolArguments() {
        let item: [String: AnyCodable] = [
            "id": AnyCodable("tool-1"),
            "type": AnyCodable("mcp_tool_call"),
            "status": AnyCodable("completed"),
            "tool": AnyCodable("search"),
            "arguments": AnyCodable([
                "query": AnyCodable("acp")
            ]),
            "result": AnyCodable("done")
        ]

        let parsed = CodexProtocolParser.parseItem(from: item, fallbackTurnID: "turn-fallback")

        XCTAssertEqual(parsed.type, .mcpToolCall)
        XCTAssertEqual(parsed.turnID, "turn-fallback")
        XCTAssertEqual(parsed.toolName, "search")
        XCTAssertEqual(parsed.toolResult, "done")
        XCTAssertEqual(parsed.toolArgumentsJSON, #"{"query":"acp"}"#)
    }
}
