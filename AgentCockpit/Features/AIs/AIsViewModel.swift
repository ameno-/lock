// AIsViewModel.swift — Polls sessions.list every 5s
import Foundation

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
    var isLoading = false
    var error: String? = nil

    init(appModel: AppModel) {
        self.appModel = appModel
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
            appModel.promoteSession(created.key)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func promote(session: ACSessionEntry) {
        appModel.promoteSession(session.key)
    }

    func rowSummary(for session: ACSessionEntry, isPromoted: Bool) -> SessionRowSummary {
        let digest = appModel.eventStore.digest(for: session.key)
        let location = locationText(for: session)
        let preview = preferredPreview(for: session, digest: digest, location: location)
        let isRunning = sessionIsRunning(session: session, digest: digest)
        let statusLabel = statusText(session: session, digest: digest, isRunning: isRunning)
        let lastActivity = digest?.lastEventAt ?? session.updatedAt ?? normalizedCreatedAt(session.createdAt)
        return SessionRowSummary(
            id: session.key,
            title: session.name,
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
            return value
        }
        return location
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
}
