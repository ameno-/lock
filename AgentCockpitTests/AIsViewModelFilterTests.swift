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
}
