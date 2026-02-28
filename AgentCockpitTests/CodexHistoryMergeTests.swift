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

@MainActor
final class SnippetLoaderTests: XCTestCase {
    func testMergeLayersHigherLayerOverridesTemplateTextByID() throws {
        let low = [
            category(
                id: "shell",
                name: "Shell",
                templates: [
                    template(id: "list", name: "List", text: "ls"),
                    template(id: "pwd", name: "Pwd", text: "pwd")
                ]
            )
        ]
        let high = [
            category(
                id: "shell",
                name: "Shell override",
                templates: [
                    template(id: "list", name: "List", text: "ls -la")
                ]
            )
        ]

        let merged = SnippetLoader.mergeLayers([low, high])

        let mergedShell = try XCTUnwrap(merged.first(where: { $0.id == "shell" }))
        let listTemplate = try XCTUnwrap(mergedShell.templates.first(where: { $0.id == "list" }))
        XCTAssertEqual(listTemplate.text, "ls -la")
    }

    func testMergeLayersKeepsCategoryOrderByFirstSeenAcrossLayers() {
        let first = [
            category(id: "b", name: "B", templates: [template(id: "b1", name: "b1", text: "b1")]),
            category(id: "a", name: "A", templates: [template(id: "a1", name: "a1", text: "a1")])
        ]
        let second = [
            category(id: "c", name: "C", templates: [template(id: "c1", name: "c1", text: "c1")]),
            category(id: "b", name: "B override", templates: [template(id: "b2", name: "b2", text: "b2")])
        ]
        let third = [
            category(id: "a", name: "A override", templates: [template(id: "a2", name: "a2", text: "a2")]),
            category(id: "d", name: "D", templates: [template(id: "d1", name: "d1", text: "d1")])
        ]

        let merged = SnippetLoader.mergeLayers([first, second, third])

        XCTAssertEqual(merged.map(\.id), ["b", "a", "c", "d"])
    }

    func testMergeLayersKeepsTemplateOrderByFirstSeenAndUsesOverrideContent() throws {
        let low = [
            category(
                id: "shell",
                name: "Shell",
                templates: [
                    template(id: "t1", name: "T1", text: "low-1"),
                    template(id: "t2", name: "T2", text: "low-2")
                ]
            )
        ]
        let high = [
            category(
                id: "shell",
                name: "Shell",
                templates: [
                    template(id: "t2", name: "T2", text: "high-2"),
                    template(id: "t3", name: "T3", text: "high-3"),
                    template(id: "t1", name: "T1", text: "high-1")
                ]
            )
        ]

        let merged = SnippetLoader.mergeLayers([low, high])
        let shell = try XCTUnwrap(merged.first(where: { $0.id == "shell" }))

        XCTAssertEqual(shell.templates.map(\.id), ["t1", "t2", "t3"])
        XCTAssertEqual(shell.templates.first(where: { $0.id == "t1" })?.text, "high-1")
        XCTAssertEqual(shell.templates.first(where: { $0.id == "t2" })?.text, "high-2")
    }

    func testSnippetContextNormalizationTrimsLowercasesAndConvertsEmptyToNil() {
        let normalized = SnippetContext(
            agentSlug: "  Agent-Alpha \n",
            harnessSlug: "\t HARNESS-beta  "
        )
        XCTAssertEqual(normalized.agentSlug, "agent-alpha")
        XCTAssertEqual(normalized.harnessSlug, "harness-beta")

        let empties = SnippetContext(agentSlug: " \n\t ", harnessSlug: "")
        XCTAssertNil(empties.agentSlug)
        XCTAssertNil(empties.harnessSlug)
    }

    func testFilesystemLayersResolveDefaultsHarnessThenAgentWithExpectedMerge() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnippetLoaderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("harness", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("agent", isDirectory: true),
            withIntermediateDirectories: true
        )

        try writeCategories(
            [
                category(
                    id: "shell",
                    name: "Shell",
                    templates: [template(id: "list", name: "List", text: "ls")]
                ),
                category(
                    id: "defaults-only",
                    name: "Defaults only",
                    templates: [template(id: "base", name: "Base", text: "base")]
                )
            ],
            to: rootURL.appendingPathComponent("defaults.json")
        )
        try writeCategories(
            [
                category(
                    id: "shell",
                    name: "Shell Harness",
                    templates: [
                        template(id: "list", name: "List", text: "ls -la"),
                        template(id: "h-only", name: "Harness only", text: "echo harness")
                    ]
                )
            ],
            to: rootURL
                .appendingPathComponent("harness", isDirectory: true)
                .appendingPathComponent("harness-a.json")
        )
        try writeCategories(
            [
                category(
                    id: "shell",
                    name: "Shell Agent",
                    templates: [
                        template(id: "list", name: "List", text: "exa"),
                        template(id: "a-only", name: "Agent only", text: "echo agent")
                    ]
                )
            ],
            to: rootURL
                .appendingPathComponent("agent", isDirectory: true)
                .appendingPathComponent("agent-a.json")
        )

        let loader = SnippetLoader(
            fileManager: .default,
            bundle: Bundle(for: SnippetLoaderTests.self),
            snippetsRootURL: rootURL
        )

        let categories = loader.categories(
            for: SnippetContext(agentSlug: "  AGENT-A  ", harnessSlug: " HARNESS-A ")
        )
        let shell = try XCTUnwrap(categories.first(where: { $0.id == "shell" }))

        XCTAssertEqual(shell.templates.map(\.id), ["list", "h-only", "a-only"])
        XCTAssertEqual(shell.templates.first(where: { $0.id == "list" })?.text, "exa")
        XCTAssertNotNil(categories.first(where: { $0.id == "defaults-only" }))
    }

    private func writeCategories(_ categories: [SnippetCategory], to url: URL) throws {
        let data = try JSONEncoder().encode(categories)
        try data.write(to: url, options: [.atomic])
    }

    private func category(id: String, name: String, templates: [SnippetTemplate]) -> SnippetCategory {
        SnippetCategory(id: id, name: name, templates: templates)
    }

    private func template(id: String, name: String, text: String) -> SnippetTemplate {
        SnippetTemplate(id: id, name: name, text: text, variables: [])
    }
}
