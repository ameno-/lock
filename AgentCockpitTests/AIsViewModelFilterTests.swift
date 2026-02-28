import XCTest
@testable import AgentCockpit

@MainActor
final class AIsViewModelFilterTests: XCTestCase {
    func testVisibleSessionsFiltersByRunningState() {
        let appModel = AppModel()
        let viewModel = AIsViewModel(appModel: appModel)

        viewModel.sessions = [
            ACSessionEntry(
                key: "active-1",
                name: "Active Session",
                window: "0",
                pane: "0",
                running: true,
                promoted: false,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            ACSessionEntry(
                key: "idle-1",
                name: "Idle Session",
                window: "0",
                pane: "0",
                running: false,
                promoted: false,
                createdAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        ]

        viewModel.selectedFilter = .active
        XCTAssertEqual(viewModel.visibleSessions.map(\.key), ["active-1"])

        viewModel.selectedFilter = .idle
        XCTAssertEqual(viewModel.visibleSessions.map(\.key), ["idle-1"])
    }

    func testVisibleSessionsFiltersBySearchQuery() {
        let appModel = AppModel()
        let viewModel = AIsViewModel(appModel: appModel)

        viewModel.sessions = [
            ACSessionEntry(
                key: "s-1",
                name: "Pi ACP Integration",
                window: "0",
                pane: "0",
                running: true,
                promoted: false,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                preview: "Compare with Agmente"
            ),
            ACSessionEntry(
                key: "s-2",
                name: "Random Thread",
                window: "0",
                pane: "0",
                running: true,
                promoted: false,
                createdAt: Date(timeIntervalSince1970: 1_700_000_050),
                preview: "Something else"
            )
        ]

        viewModel.searchQuery = "agmente"
        XCTAssertEqual(viewModel.visibleSessions.map(\.key), ["s-1"])
    }

    func testActionRequiredFilterUsesPendingRequestQueues() {
        let appModel = AppModel()
        let viewModel = AIsViewModel(appModel: appModel)

        viewModel.sessions = [
            ACSessionEntry(
                key: "session-needs-input",
                name: "Needs input",
                window: "0",
                pane: "0",
                running: true,
                promoted: false,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            ACSessionEntry(
                key: "session-clean",
                name: "Clean",
                window: "0",
                pane: "0",
                running: true,
                promoted: false,
                createdAt: Date(timeIntervalSince1970: 1_700_000_050)
            )
        ]

        appModel.transport.handleServerRequest(
            id: "req-1",
            method: "item/tool/requestUserInput",
            params: [
                "threadId": AnyCodable("session-needs-input"),
                "questions": AnyCodable([AnyCodable([
                    "id": AnyCodable("q1"),
                    "question": AnyCodable("Continue?"),
                    "options": AnyCodable([AnyCodable([
                        "label": AnyCodable("Yes")
                    ])])
                ])])
            ]
        )

        viewModel.selectedFilter = .actionRequired
        XCTAssertEqual(viewModel.visibleSessions.map(\.key), ["session-needs-input"])
    }

    func testRowSummaryCompactsLongPreviewText() {
        let appModel = AppModel()
        let viewModel = AIsViewModel(appModel: appModel)
        let longPreview = """
        This is a very long preview line that should be compacted into a safer size for mobile cards.
        It includes newlines and extra spacing so the summary logic can normalize it properly.
        """

        let session = ACSessionEntry(
            key: "session-long-preview",
            name: "Long Preview Session title that also needs to be compacted for readable mobile rows with accessibility labels",
            window: "0",
            pane: "0",
            running: true,
            promoted: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            preview: longPreview
        )

        let summary = viewModel.rowSummary(for: session, isPromoted: false)
        XCTAssertLessThanOrEqual(summary.title.count, 75) // 72 + optional ellipsis
        XCTAssertLessThanOrEqual(summary.preview.count, 163) // 160 + optional ellipsis
        XCTAssertFalse(summary.preview.contains("\n"))
    }
}

@MainActor
final class WorkViewModelSnippetStackTests: XCTestCase {
    func testQueueSnippetForInsertAppendsInputAndQueuesStackPayload() {
        let appModel = AppModel()
        let viewModel = WorkViewModel(appModel: appModel)

        viewModel.queueSnippetForInsert("First snippet")
        viewModel.queueSnippetForInsert("Second snippet")

        XCTAssertEqual(viewModel.inputText, "First snippet\n\nSecond snippet")
        XCTAssertEqual(viewModel.snippetStackCount, 2)
        XCTAssertEqual(viewModel.stackedSnippetPayload, "First snippet\n\nSecond snippet")
    }

    func testQueueSnippetForInsertIgnoresWhitespaceOnlySnippets() {
        let appModel = AppModel()
        let viewModel = WorkViewModel(appModel: appModel)

        viewModel.queueSnippetForInsert("   \n\t  ")

        XCTAssertEqual(viewModel.inputText, "")
        XCTAssertEqual(viewModel.snippetStackCount, 0)
        XCTAssertNil(viewModel.stackedSnippetPayload)
    }

    func testClearSnippetStackRemovesQueuedSnippets() {
        let appModel = AppModel()
        let viewModel = WorkViewModel(appModel: appModel)

        viewModel.queueSnippetForInsert("Snippet A")
        viewModel.queueSnippetForInsert("Snippet B")
        viewModel.clearSnippetStack()

        XCTAssertEqual(viewModel.snippetStackCount, 0)
        XCTAssertNil(viewModel.stackedSnippetPayload)
    }

    func testExecuteSnippetStackSendsJoinedPayloadAndClearsOnSuccess() async {
        let appModel = AppModel()
        appModel.promotedSessionKey = "session-1"
        var sentPayload: String?

        let viewModel = WorkViewModel(
            appModel: appModel,
            subscribeToSession: { _ in },
            sendToSession: { _, text in sentPayload = text }
        )

        viewModel.queueSnippetForInsert("Snippet A")
        viewModel.queueSnippetForInsert("Snippet B")
        let task = viewModel.executeSnippetStack()
        await task.value

        XCTAssertEqual(sentPayload, "Snippet A\n\nSnippet B")
        XCTAssertEqual(viewModel.snippetStackCount, 0)
    }

    func testExecuteSnippetStackKeepsQueueOnFailure() async {
        enum TestError: Error { case sendFailed }

        let appModel = AppModel()
        appModel.promotedSessionKey = "session-1"

        let viewModel = WorkViewModel(
            appModel: appModel,
            subscribeToSession: { _ in },
            sendToSession: { _, _ in throw TestError.sendFailed }
        )

        viewModel.queueSnippetForInsert("Snippet A")
        let task = viewModel.executeSnippetStack()
        await task.value

        XCTAssertEqual(viewModel.snippetStackCount, 1)
    }

    func testManualSendClearsSnippetStackOnSuccess() async {
        let appModel = AppModel()
        appModel.promotedSessionKey = "session-1"
        var sentPayload: String?

        let viewModel = WorkViewModel(
            appModel: appModel,
            subscribeToSession: { _ in },
            sendToSession: { _, text in sentPayload = text }
        )

        viewModel.queueSnippetForInsert("Snippet A")
        let task = viewModel.send(text: "manual prompt")
        await task.value

        XCTAssertEqual(sentPayload, "manual prompt")
        XCTAssertEqual(viewModel.snippetStackCount, 0)
    }
}

@MainActor
final class WorkViewModelSnippetContextTests: XCTestCase {
    func testSnippetContextPrefersExplicitMetadataMarkers() {
        let appModel = AppModel()
        appModel.settings.serverProtocol = .codex
        appModel.settings.snippetAgentSlug = "settings-agent"

        let session = makeSession(
            key: "session-explicit",
            preview: "backend: acp model: claude-sonnet-4"
        )
        appModel.cacheSessionMetadata(for: session)
        appModel.promotedSessionKey = session.key

        let viewModel = WorkViewModel(appModel: appModel)
        let context = viewModel.snippetContext

        XCTAssertEqual(context.harnessSlug, "acp")
        XCTAssertEqual(context.agentSlug, "claude-sonnet-4")
    }

    func testSnippetContextInfersFromMetadataTokensWhenMarkersMissing() {
        let appModel = AppModel()
        appModel.settings.serverProtocol = .acp
        appModel.settings.snippetAgentSlug = "settings-agent"

        let session = makeSession(
            key: "session-token",
            name: "Codex Workspace",
            preview: "Investigate terminal renderer",
            cwd: "/tmp/codex-runner"
        )
        appModel.cacheSessionMetadata(for: session)
        appModel.promotedSessionKey = session.key

        let viewModel = WorkViewModel(appModel: appModel)
        let context = viewModel.snippetContext

        XCTAssertEqual(context.harnessSlug, "codex")
        XCTAssertEqual(context.agentSlug, "codex")
    }

    func testSnippetContextFallsBackToSettingsWhenMetadataMissing() {
        let appModel = AppModel()
        appModel.settings.serverProtocol = .acp
        appModel.settings.snippetAgentSlug = "custom-agent"
        appModel.promotedSessionKey = "missing-session"

        let viewModel = WorkViewModel(appModel: appModel)
        let context = viewModel.snippetContext

        XCTAssertEqual(context.harnessSlug, "acp")
        XCTAssertEqual(context.agentSlug, "custom-agent")
    }

    func testSnippetContextFallsBackToHarnessForAgentWhenSettingsAgentMissing() {
        let appModel = AppModel()
        appModel.settings.serverProtocol = .codex
        appModel.settings.snippetAgentSlug = " \n\t "
        appModel.promotedSessionKey = "missing-session"

        let viewModel = WorkViewModel(appModel: appModel)
        let context = viewModel.snippetContext

        XCTAssertEqual(context.harnessSlug, "codex")
        XCTAssertEqual(context.agentSlug, "codex")
    }

    func testPromoteCachesSessionMetadataForSnippetResolution() {
        let appModel = AppModel()
        appModel.settings.serverProtocol = .codex
        appModel.settings.snippetAgentSlug = ""

        let session = makeSession(
            key: "session-promote",
            preview: "protocol=acp agent=gemini-2.0-pro"
        )

        let aisViewModel = AIsViewModel(appModel: appModel)
        aisViewModel.promote(session: session)

        XCTAssertNotNil(appModel.sessionMetadata(for: session.key))

        let workViewModel = WorkViewModel(appModel: appModel)
        let context = workViewModel.snippetContext
        XCTAssertEqual(context.harnessSlug, "acp")
        XCTAssertEqual(context.agentSlug, "gemini-2.0-pro")
    }

    private func makeSession(
        key: String,
        name: String = "Session",
        preview: String? = nil,
        cwd: String? = nil
    ) -> ACSessionEntry {
        ACSessionEntry(
            key: key,
            name: name,
            window: "0",
            pane: "0",
            running: true,
            promoted: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            cwd: cwd,
            preview: preview,
            statusText: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }
}
