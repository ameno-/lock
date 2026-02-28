// AIsViewModel.swift — Polls sessions.list every 5s
import Foundation

enum SessionListFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case idle
    case actionRequired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .active:
            "Active"
        case .idle:
            "Idle"
        case .actionRequired:
            "Needs Action"
        }
    }
}

struct SessionRowSummary: Identifiable, Sendable {
    let id: String
    let title: String
    let preview: String
    let location: String
    let statusLabel: String
    let isRunning: Bool
    let isPromoted: Bool
    let protocolLabel: String
    let lastActivityLabel: String
    let tokenUsageLabel: String?
}

@Observable
@MainActor
final class AIsViewModel {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private let appModel: AppModel
    private var pollTask: Task<Void, Never>?

    var sessions: [ACSessionEntry] = []
    var selectedFilter: SessionListFilter = .all
    var searchQuery: String = ""
    var isLoading = false
    var error: String? = nil

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var visibleSessions: [ACSessionEntry] {
        let sorted = sessions.sorted { lhs, rhs in
            let lhsDate = appModel.eventStore.digest(for: lhs.key)?.lastEventAt
                ?? lhs.updatedAt
                ?? normalizedCreatedAt(lhs.createdAt)
                ?? .distantPast
            let rhsDate = appModel.eventStore.digest(for: rhs.key)?.lastEventAt
                ?? rhs.updatedAt
                ?? normalizedCreatedAt(rhs.createdAt)
                ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.key < rhs.key
        }

        return sorted.filter { session in
            matchesSearch(session) && matchesFilter(session)
        }
    }

    var hasActiveFilters: Bool {
        selectedFilter != .all || !trimmedSearchQuery.isEmpty
    }

    func resetFilters() {
        selectedFilter = .all
        searchQuery = ""
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard appModel.connection.state == .connected else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appModel.transport.listSessions()
            sessions = result
            appModel.cacheSessionMetadata(for: result)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createSession() async {
        do {
            guard let created = try await appModel.transport.createSession() else {
                error = "Session creation is only supported for ACP and Codex endpoints."
                return
            }
            appModel.cacheSessionMetadata(for: created)
            appModel.promoteSession(created.key)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func promote(session: ACSessionEntry) {
        appModel.cacheSessionMetadata(for: session)
        appModel.promoteSession(session.key)
    }

    func rowSummary(for session: ACSessionEntry, isPromoted: Bool) -> SessionRowSummary {
        let digest = appModel.eventStore.digest(for: session.key)
        let location = locationText(for: session)
        let preview = preferredPreview(for: session, digest: digest, location: location)
        let title = normalizedTitle(session.name, fallback: session.key)
        let isRunning = sessionIsRunning(session: session, digest: digest)
        let statusLabel = statusText(session: session, digest: digest, isRunning: isRunning)
        let lastActivity = digest?.lastEventAt ?? session.updatedAt ?? normalizedCreatedAt(session.createdAt)
        return SessionRowSummary(
            id: session.key,
            title: title,
            preview: preview,
            location: location,
            statusLabel: statusLabel,
            isRunning: isRunning,
            isPromoted: isPromoted,
            protocolLabel: protocolLabel,
            lastActivityLabel: lastActivityText(from: lastActivity),
            tokenUsageLabel: tokenUsageText(from: digest?.tokenUsage)
        )
    }

    private var protocolLabel: String {
        switch appModel.settings.serverProtocol {
        case .acp: "ACP"
        case .codex: "Codex"
        }
    }

    private func locationText(for session: ACSessionEntry) -> String {
        if let cwd = session.cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty {
            return cwd
        }
        let hasPane = session.window != "0" || session.pane != "0"
        if hasPane {
            return "window \(session.window) • pane \(session.pane)"
        }
        let shortKey = session.key.count > 14 ? "\(session.key.prefix(14))…" : session.key
        return "id \(shortKey)"
    }

    private func preferredPreview(for session: ACSessionEntry, digest: SessionDigest?, location: String) -> String {
        let candidates: [String?] = [
            digest?.previewText,
            session.preview,
            session.name == session.key ? nil : session.name,
            location,
        ]
        for candidate in candidates {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            return normalizedSessionPreview(value)
        }
        return location
    }

    private func normalizedTitle(_ raw: String, fallback: String) -> String {
        let compact = raw
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = compact.isEmpty ? fallback : compact
        guard candidate.count > 72 else { return candidate }
        let limit = candidate.index(candidate.startIndex, offsetBy: 72)
        return "\(candidate[..<limit])..."
    }

    private func normalizedSessionPreview(_ text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > 160 else { return compact }
        let limit = compact.index(compact.startIndex, offsetBy: 160)
        return "\(compact[..<limit])..."
    }

    private func sessionIsRunning(session: ACSessionEntry, digest: SessionDigest?) -> Bool {
        let normalizedStatus = (digest?.status ?? session.statusText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedStatus.isEmpty { return session.running }
        return ["active", "running", "live", "in_progress", "in-progress"].contains(normalizedStatus)
    }

    private func statusText(session: ACSessionEntry, digest: SessionDigest?, isRunning: Bool) -> String {
        if let status = (digest?.status ?? session.statusText)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !status.isEmpty {
            return status.replacingOccurrences(of: "_", with: " ")
        }
        return isRunning ? "live" : "idle"
    }

    private func lastActivityText(from date: Date?) -> String {
        guard let date else { return "activity unknown" }
        return "updated \(Self.relativeFormatter.localizedString(for: date, relativeTo: .now))"
    }

    private func normalizedCreatedAt(_ date: Date) -> Date? {
        date.timeIntervalSince1970 > 1000 ? date : nil
    }

    private func tokenUsageText(from usage: SessionTokenUsage?) -> String? {
        guard let usage else { return nil }
        if let total = usage.totalTokens {
            return "\(compact(total)) tok"
        }
        if let input = usage.inputTokens, let output = usage.outputTokens {
            return "\(compact(input))/\(compact(output)) tok"
        }
        if let input = usage.inputTokens {
            return "\(compact(input)) in tok"
        }
        if let output = usage.outputTokens {
            return "\(compact(output)) out tok"
        }
        return nil
    }

    private func compact(_ value: Int) -> String {
        if value >= 1_000_000 {
            let formatted = String(format: "%.1f", Double(value) / 1_000_000)
            return "\(formatted.replacingOccurrences(of: ".0", with: ""))m"
        }
        if value >= 1_000 {
            let formatted = String(format: "%.1f", Double(value) / 1_000)
            return "\(formatted.replacingOccurrences(of: ".0", with: ""))k"
        }
        return "\(value)"
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesSearch(_ session: ACSessionEntry) -> Bool {
        let query = trimmedSearchQuery
        guard !query.isEmpty else { return true }

        let digest = appModel.eventStore.digest(for: session.key)
        let location = locationText(for: session)
        let haystack = [
            session.key,
            session.name,
            session.preview ?? "",
            digest?.previewText ?? "",
            location
        ].joined(separator: "\n")
        return haystack.localizedCaseInsensitiveContains(query)
    }

    private func matchesFilter(_ session: ACSessionEntry) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .active:
            return sessionIsRunning(session: session, digest: appModel.eventStore.digest(for: session.key))
        case .idle:
            return !sessionIsRunning(session: session, digest: appModel.eventStore.digest(for: session.key))
        case .actionRequired:
            return requiresAction(sessionKey: session.key)
        }
    }

    private func requiresAction(sessionKey: String) -> Bool {
        appModel.pendingApprovalRequests.contains { request in
            request.threadId == sessionKey
        } || appModel.pendingUserInputRequests.contains { request in
            request.threadId == sessionKey
        }
    }
}
