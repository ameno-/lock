// WorkViewModel.swift — Manages active session + canvas events for the Work view
import Foundation
import SwiftUI

@Observable
@MainActor
final class WorkViewModel {
    typealias SubscribeHandler = @MainActor (String) async throws -> Void
    typealias SendHandler = @MainActor (String, String) async throws -> Void
    private static let commonAgentTokens = ["codex", "claude", "gemini", "gpt", "acp"]

    private let appModel: AppModel
    private let subscribeToSession: SubscribeHandler
    private let sendToSession: SendHandler
    private var activateTask: Task<Void, Never>?
    private var lastActivatedSessionKey: String?
    private var loadedContextSessionKeys: Set<String> = []
    private var recoveredPendingActionsSessionKeys: Set<String> = []
    private var genUIActionStatesByKey: [String: GenUIActionDispatchState] = [:]
    private var snippetStack: [String] = []
    var inputText = ""
    var errorMessage: String? = nil

    init(
        appModel: AppModel,
        subscribeToSession: SubscribeHandler? = nil,
        sendToSession: SendHandler? = nil
    ) {
        self.appModel = appModel
        self.subscribeToSession = subscribeToSession ?? { sessionKey in
            try await appModel.transport.subscribe(sessionKey: sessionKey)
        }
        self.sendToSession = sendToSession ?? { sessionKey, text in
            try await appModel.transport.send(sessionKey: sessionKey, text: text)
        }
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

    nonisolated private static let promotedSurfacePrefixes = [
        "session.plan",
        "session.progress",
        "session.decision",
        "session.result",
        "session.approval",
        "session.reorientation",
    ]

    var promotedSurfaces: [GenUIEvent] {
        guard let key = activeSessionKey else { return approvalSurfaces }
        let surfaces = appModel.eventStore.exportGenUISurfacesBySession()[key] ?? []
        let promoted = surfaces.filter { Self.isPromotedSurface($0) }
        return approvalSurfaces + promoted
    }

    private var approvalSurfaces: [GenUIEvent] {
        pendingApprovalRequests.map { ApprovalSurfaceSynthesizer.synthesize(from: $0) }
    }

    nonisolated static func isPromotedSurface(_ event: GenUIEvent) -> Bool {
        if event.contextPayload["pinned"]?.boolValue == true {
            return true
        }
        let sid = event.surfaceID
        return promotedSurfacePrefixes.contains { sid.hasPrefix($0) }
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

    var quickReplyChips: [QuickReplyChip] {
        var chips: [QuickReplyChip] = []

        for request in pendingApprovalRequests.prefix(2) {
            chips.append(QuickReplyChip(
                id: "approve-\(request.id)",
                label: "Accept",
                icon: "checkmark.circle",
                tint: .green,
                kind: .approvalDecision(requestID: request.id, decision: .accept)
            ))
            chips.append(QuickReplyChip(
                id: "decline-\(request.id)",
                label: "Decline",
                icon: "xmark.circle",
                tint: .red,
                kind: .approvalDecision(requestID: request.id, decision: .decline)
            ))
        }

        let hasApprovals = !pendingApprovalRequests.isEmpty
        if !hasApprovals {
            let defaults: [(String, String?, Color)] = [
                ("continue", "play.fill", .blue),
                ("yes", nil, .green),
                ("no", nil, .red),
                ("abort", "stop.fill", .red),
            ]
            for (label, icon, tint) in defaults {
                chips.append(QuickReplyChip(
                    id: "quick-\(label)",
                    label: label,
                    icon: icon,
                    tint: tint,
                    kind: .text(label)
                ))
            }
        }

        return chips
    }

    var snippetContext: SnippetContext {
        resolveSnippetContext(for: activeSessionKey)
    }

    var snippetCategories: [SnippetCategory] {
        SnippetLoader.shared.categories(for: snippetContext)
    }

    var snippetStackCount: Int {
        snippetStack.count
    }

    var stackedSnippetPayload: String? {
        guard !snippetStack.isEmpty else { return nil }
        return snippetStack.joined(separator: "\n\n")
    }

    // MARK: - Actions

    @discardableResult
    func send(text: String) -> Task<Void, Never> {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return Task {} }
        return sendPrompt(prompt, clearStackOnSuccess: true)
    }

    func queueSnippetForInsert(_ snippet: String) {
        let normalizedSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSnippet.isEmpty else { return }

        inputText = Self.appendSnippet(normalizedSnippet, to: inputText)
        snippetStack.append(normalizedSnippet)
    }

    func clearSnippetStack() {
        snippetStack.removeAll()
    }

    @discardableResult
    func executeSnippetStack() -> Task<Void, Never> {
        guard let payload = stackedSnippetPayload else { return Task {} }
        return sendPrompt(payload, clearStackOnSuccess: true)
    }

    func abort() {
        guard let key = activeSessionKey else {
            return
        }
        Task {
            do {
                try await appModel.transport.cancel(sessionKey: key)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func performGenUIAction(_ event: GenUIEvent) {
        if event.contextPayload["__reorientation"]?.boolValue == true {
            if let key = activeSessionKey {
                appModel.eventStore.removeGenUISurface(surfaceID: "session.reorientation", sessionKey: key)
            }
            return
        }

        if let approvalRequestID = event.contextPayload["__approvalRequestId"]?.stringValue {
            let actionID = event.actionPayload["actionId"]?.stringValue ?? "accept"
            let decision: ACApprovalDecision = switch actionID {
            case "decline": .decline
            case "cancel": .cancel
            default: .accept
            }
            decideApproval(requestID: approvalRequestID, decision: decision)
            return
        }

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
                self.synthesizeReorientationSurface(for: key)
            } catch {
                // Allow retry for the same session if activation failed.
                self.lastActivatedSessionKey = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func sendPrompt(_ prompt: String, clearStackOnSuccess: Bool) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let key = self.activeSessionKey else {
                self.errorMessage = "No active session. Open AIs and use + to create or promote a session."
                return
            }

            do {
                try await self.subscribeToSession(key)
                try await self.sendToSession(key, prompt)
                if clearStackOnSuccess {
                    self.clearSnippetStack()
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func resolveSnippetContext(for sessionKey: String?) -> SnippetContext {
        let metadata = appModel.sessionMetadata(for: sessionKey)

        var harnessSlug = metadata.flatMap(resolveHarnessSlug(from:))
        if harnessSlug == nil {
            harnessSlug = appModel.settings.serverProtocol.rawValue
        }

        var agentSlug = metadata.flatMap(resolveAgentSlug(from:))
        if agentSlug == nil {
            agentSlug = appModel.settings.snippetAgentSlug
        }
        if agentSlug?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            agentSlug = harnessSlug
        }

        return SnippetContext(agentSlug: agentSlug, harnessSlug: harnessSlug)
    }

    private func resolveHarnessSlug(from metadata: AppModel.SessionMetadataSnapshot) -> String? {
        if let explicit = firstMarkedValue(
            in: metadata.metadataText,
            markers: ["harness", "protocol", "backend"]
        ) {
            return explicit
        }
        return inferToken(from: metadata)
    }

    private func resolveAgentSlug(from metadata: AppModel.SessionMetadataSnapshot) -> String? {
        if let explicit = firstMarkedValue(
            in: metadata.metadataText,
            markers: ["agent", "model"]
        ) {
            return explicit
        }
        return inferToken(from: metadata)
    }

    private func firstMarkedValue(in metadataText: String, markers: [String]) -> String? {
        for marker in markers {
            let escapedMarker = NSRegularExpression.escapedPattern(for: marker)
            let pattern = #"(?i)\b\#(escapedMarker)\b\s*[:=]\s*([A-Za-z0-9._/-]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(metadataText.startIndex..<metadataText.endIndex, in: metadataText)
            guard let match = regex.firstMatch(in: metadataText, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: metadataText) else {
                continue
            }
            if let normalized = normalizedExplicitSlug(String(metadataText[valueRange])) {
                return normalized
            }
        }
        return nil
    }

    private func normalizedExplicitSlug(_ value: String) -> String? {
        let leading = CharacterSet(charactersIn: "\"'`([{<")
        let trailing = CharacterSet(charactersIn: "\"'`)]}>.,;")
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: leading)
            .trimmingCharacters(in: trailing)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func inferToken(from metadata: AppModel.SessionMetadataSnapshot) -> String? {
        let candidates: [String] = [
            metadata.name,
            metadata.preview,
            metadata.cwd,
            metadata.statusText,
            metadata.sessionKey
        ].compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for token in Self.commonAgentTokens {
            if candidates.contains(where: { containsToken(token, in: $0) }) {
                return token
            }
        }
        return nil
    }

    private func containsToken(_ token: String, in text: String) -> Bool {
        let words = text.lowercased().split { character in
            !character.isLetter && !character.isNumber
        }
        return words.contains { word in
            word.hasPrefix(token)
        }
    }

    static func appendSnippet(_ snippet: String, to existing: String) -> String {
        guard !snippet.isEmpty else { return existing }
        guard !existing.isEmpty else { return snippet }

        if existing.hasSuffix("\n\n") {
            return existing + snippet
        }
        if existing.hasSuffix("\n") {
            return existing + "\n" + snippet
        }
        return existing + "\n\n" + snippet
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

    private var reorientationSynthesizedSessionKeys: Set<String> = []

    private func synthesizeReorientationSurface(for sessionKey: String) {
        guard !reorientationSynthesizedSessionKeys.contains(sessionKey) else { return }
        reorientationSynthesizedSessionKeys.insert(sessionKey)

        let digest = appModel.eventStore.digest(for: sessionKey)
        let recent = appModel.eventStore.recentEvents(for: sessionKey, limit: 8)
        guard let surface = SessionReorientationSynthesizer.synthesize(
            sessionKey: sessionKey,
            digest: digest,
            recentEvents: recent
        ) else { return }

        appModel.eventStore.ingest(event: .genUI(surface), sessionKey: sessionKey)
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
