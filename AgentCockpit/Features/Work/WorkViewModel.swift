// WorkViewModel.swift — Manages active session + canvas events for the Work view
import Foundation

@Observable
@MainActor
final class WorkViewModel {
    private let appModel: AppModel
    private var activateTask: Task<Void, Never>?
    private var lastActivatedSessionKey: String?
    private var loadedContextSessionKeys: Set<String> = []
    private var recoveredPendingActionsSessionKeys: Set<String> = []
    private var genUIActionStatesByKey: [String: GenUIActionDispatchState] = [:]
    var inputText = ""
    var errorMessage: String? = nil

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var activeSessionKey: String? {
        appModel.promotedSessionKey
    }

    var canvasEvents: [CanvasEvent] {
        guard let key = activeSessionKey else {
            // Show all events if no session is promoted
            return appModel.eventStore.allEvents
        }
        return appModel.eventStore.events(for: key)
    }

    var runningSubAgents: [SubAgentEvent] {
        appModel.eventStore.runningSubAgents
    }

    var connectionState: ACConnectionState {
        appModel.connection.state
    }

    var pendingApprovalRequests: [ACPendingApprovalRequest] {
        appModel.pendingApprovalRequests
    }

    var pendingUserInputRequests: [ACPendingUserInputRequest] {
        appModel.pendingUserInputRequests
    }

    var snippetCategories: [SnippetCategory] {
        SnippetLoader.shared.categories
    }

    // MARK: - Actions

    func send(text: String) {
        guard let key = activeSessionKey else {
            errorMessage = "No active session. Open AIs and use + to create or promote a session."
            return
        }
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        Task {
            do {
                try await appModel.transport.subscribe(sessionKey: key)
                try await appModel.transport.send(sessionKey: key, text: prompt)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func abort() {
        guard let key = activeSessionKey else { return }
        Task {
            do {
                try await appModel.transport.cancel(sessionKey: key)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func performGenUIAction(_ event: GenUIEvent) {
        guard let key = activeSessionKey else {
            errorMessage = "No active session for GenUI action."
            return
        }
        let actionID = event.actionPayload["actionId"]?.stringValue
            ?? event.actionPayload["action_id"]?.stringValue
            ?? event.actionLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
            ?? "action"
        let pendingID = appModel.enqueuePendingGenUIAction(sessionKey: key, event: event)
        appModel.markPendingGenUIActionAttempt(id: pendingID)
        setGenUIActionState(
            sessionKey: key,
            surfaceID: event.surfaceID,
            actionID: actionID,
            state: GenUIActionDispatchState(status: .sending)
        )
        Task {
            do {
                try await appModel.transport.submitGenUIAction(sessionKey: key, event: event)
                appModel.markPendingGenUIActionCompleted(id: pendingID)
                setGenUIActionState(
                    sessionKey: key,
                    surfaceID: event.surfaceID,
                    actionID: actionID,
                    state: GenUIActionDispatchState(status: .succeeded)
                )
            } catch {
                appModel.markPendingGenUIActionFailed(id: pendingID, errorMessage: error.localizedDescription)
                setGenUIActionState(
                    sessionKey: key,
                    surfaceID: event.surfaceID,
                    actionID: actionID,
                    state: GenUIActionDispatchState(
                        status: .failed,
                        message: error.localizedDescription
                    )
                )
                errorMessage = error.localizedDescription
            }
        }
    }

    func genUIActionState(surfaceID: String, actionID: String) -> GenUIActionDispatchState? {
        guard let key = activeSessionKey else { return nil }
        return genUIActionStatesByKey[genUIActionStateKey(sessionKey: key, surfaceID: surfaceID, actionID: actionID)]
    }

    func decideApproval(requestID: String, decision: ACApprovalDecision) {
        appModel.respondToApprovalRequest(id: requestID, decision: decision)
    }

    func submitUserInput(requestID: String, answers: [String: [String]]) {
        appModel.submitUserInputRequest(id: requestID, answers: answers)
    }

    func dismissUserInput(requestID: String) {
        appModel.dismissUserInputRequest(id: requestID)
    }

    func subscribeToActive() {
        activateSessionIfNeeded()
    }

    func activateSessionIfNeeded() {
        guard let key = activeSessionKey else { return }
        guard lastActivatedSessionKey != key else { return }
        lastActivatedSessionKey = key

        activateTask?.cancel()
        activateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.clearGenUIActionStates(for: key)
                try await self.appModel.transport.subscribe(sessionKey: key)

                // Backfill thread history once per session selection lifecycle.
                if !self.loadedContextSessionKeys.contains(key) {
                    let history = try await self.appModel.transport.loadSessionContext(sessionKey: key)
                    for event in history {
                        self.appModel.eventStore.ingest(event: event, sessionKey: key)
                    }
                    self.appModel.persistGenUIStateNow()
                    self.loadedContextSessionKeys.insert(key)
                }

                await self.recoverPendingGenUIActionsIfNeeded(for: key)
            } catch {
                // Allow retry for the same session if activation failed.
                self.lastActivatedSessionKey = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func setGenUIActionState(
        sessionKey: String,
        surfaceID: String,
        actionID: String,
        state: GenUIActionDispatchState
    ) {
        genUIActionStatesByKey[genUIActionStateKey(sessionKey: sessionKey, surfaceID: surfaceID, actionID: actionID)] = state
    }

    private func genUIActionStateKey(sessionKey: String, surfaceID: String, actionID: String) -> String {
        "\(sessionKey)|\(surfaceID)|\(actionID)"
    }

    private func clearGenUIActionStates(for sessionKey: String) {
        let prefix = "\(sessionKey)|"
        genUIActionStatesByKey = genUIActionStatesByKey.filter { !$0.key.hasPrefix(prefix) }
    }

    private func recoverPendingGenUIActionsIfNeeded(for sessionKey: String) async {
        guard !recoveredPendingActionsSessionKeys.contains(sessionKey) else { return }
        recoveredPendingActionsSessionKeys.insert(sessionKey)

        let pending = appModel.pendingGenUIActions(for: sessionKey)
        guard !pending.isEmpty else { return }

        for item in pending {
            let actionID = item.event.actionPayload["actionId"]?.stringValue
                ?? item.event.actionPayload["action_id"]?.stringValue
                ?? item.event.actionLabel?
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                ?? "action"

            appModel.markPendingGenUIActionAttempt(id: item.id)
            setGenUIActionState(
                sessionKey: sessionKey,
                surfaceID: item.event.surfaceID,
                actionID: actionID,
                state: GenUIActionDispatchState(status: .sending)
            )

            do {
                try await appModel.transport.submitGenUIAction(sessionKey: sessionKey, event: item.event)
                appModel.markPendingGenUIActionCompleted(id: item.id)
                setGenUIActionState(
                    sessionKey: sessionKey,
                    surfaceID: item.event.surfaceID,
                    actionID: actionID,
                    state: GenUIActionDispatchState(status: .succeeded)
                )
            } catch {
                appModel.markPendingGenUIActionFailed(id: item.id, errorMessage: error.localizedDescription)
                setGenUIActionState(
                    sessionKey: sessionKey,
                    surfaceID: item.event.surfaceID,
                    actionID: actionID,
                    state: GenUIActionDispatchState(status: .failed, message: error.localizedDescription)
                )
            }
        }
    }
}
