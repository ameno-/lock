// WorkViewModel.swift — Manages active session + canvas events for the Work view
import Foundation

@Observable
@MainActor
final class WorkViewModel {
    private let appModel: AppModel
    private var activateTask: Task<Void, Never>?
    private var lastActivatedSessionKey: String?
    private var loadedContextSessionKeys: Set<String> = []
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
        Task {
            do {
                try await appModel.transport.submitGenUIAction(sessionKey: key, event: event)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
                try await self.appModel.transport.subscribe(sessionKey: key)

                // Backfill thread history once per session selection lifecycle.
                if !self.loadedContextSessionKeys.contains(key) {
                    let history = try await self.appModel.transport.loadSessionContext(sessionKey: key)
                    for event in history {
                        self.appModel.eventStore.ingest(event: event, sessionKey: key)
                    }
                    self.loadedContextSessionKeys.insert(key)
                }
            } catch {
                // Allow retry for the same session if activation failed.
                self.lastActivatedSessionKey = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
