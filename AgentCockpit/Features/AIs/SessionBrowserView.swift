// SessionBrowserView.swift — Session browser with grouped list, search, and swipe actions
import SwiftUI

struct SessionBrowserView: View {
    @Environment(AppModel.self) private var appModel
    @State private var sessions: [ACSessionEntry] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var error: String? = nil

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let dateSectionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var filteredSessions: [ACSessionEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter { session in
            let haystack = [session.key, session.name, session.preview ?? ""].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }
    }

    var groupedSessions: [(date: Date, sessions: [ACSessionEntry])] {
        let sorted = filteredSessions.sorted { lhs, rhs in
            let lhsDate = lhs.updatedAt ?? lhs.createdAt
            let rhsDate = rhs.updatedAt ?? rhs.createdAt
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.key < rhs.key
        }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sorted) { session in
            calendar.startOfDay(for: session.updatedAt ?? session.createdAt)
        }

        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        List {
            ForEach(groupedSessions, id: \.date) { section in
                Section(header: Text(sectionTitle(for: section.date))) {
                    ForEach(section.sessions) { session in
                        SessionRow(
                            session: session,
                            isPromoted: appModel.promotedSessionKey == session.key
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteSession(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                loadSession(session)
                            } label: {
                                Label("Load", systemImage: "arrow.up.circle")
                            }
                            .tint(.blue)
                        }
                        .onTapGesture {
                            loadSession(session)
                        }
                    }
                }
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search sessions")
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    Task { await refreshSessions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh sessions")
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await createNewSession() }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(isLoading)
                .accessibilityLabel("Create new session")
            }
        }
        .overlay {
            if sessions.isEmpty && !isLoading {
                emptyState
            } else if filteredSessions.isEmpty && !searchText.isEmpty && !isLoading {
                noSearchResultsState
            }
        }
        .onAppear {
            Task { await refreshSessions() }
        }
        .alert("Error", isPresented: .init(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Sessions", systemImage: "ellipsis.message")
        } description: {
            Text(emptyDescription)
        } actions: {
            Button("Create Session") {
                Task { await createNewSession() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var noSearchResultsState: some View {
        ContentUnavailableView {
            Label("No Matches", systemImage: "magnifyingglass")
        } description: {
            Text("No sessions found for \"\(searchText)\".")
        } actions: {
            Button("Clear Search") {
                searchText = ""
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptyDescription: String {
        switch appModel.settings.serverProtocol {
        case .acp:
            return "No ACP sessions found. Create one to get started."
        case .codex:
            return "No Codex threads found. Create one to get started."
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return Self.dateSectionFormatter.string(from: date)
        }
    }

    private func refreshSessions() async {
        guard appModel.connection.state == .connected else {
            error = "Not connected to server"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await appModel.transport.listSessions()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createNewSession() async {
        do {
            guard let created = try await appModel.transport.createSession() else {
                let protocolName = switch appModel.settings.serverProtocol {
                case .acp: "ACP"
                case .codex: "Codex"
                }
                error = "\(protocolName) create returned no session/thread id."
                return
            }
            appModel.promoteSession(created.key)
            await refreshSessions()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadSession(_ session: ACSessionEntry) {
        appModel.promoteSession(session.key)
    }

    private func deleteSession(_ session: ACSessionEntry) {
        // Remove from local list immediately for UI feedback
        sessions.removeAll { $0.key == session.key }

        // TODO: Implement server-side delete when API is available
        // For now, we just remove from the local list
        print("Delete session: \(session.key) - server delete not yet implemented")
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: ACSessionEntry
    let isPromoted: Bool
    @Environment(\.colorScheme) private var colorScheme

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var displayName: String {
        session.name.isEmpty ? session.key : session.name
    }

    private var previewText: String {
        session.preview?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "No preview available"
    }

    private var statusText: String {
        session.statusText?.replacingOccurrences(of: "_", with: " ")
            ?? (session.running ? "active" : "idle")
    }

    private var updatedTimeText: String {
        guard let updatedAt = session.updatedAt else {
            return "created \(Self.relativeFormatter.localizedString(for: session.createdAt, relativeTo: .now))"
        }
        return Self.relativeFormatter.localizedString(for: updatedAt, relativeTo: .now)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                // Title row
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isPromoted {
                        StatusBadge(text: "Active", color: .green)
                    }

                    Spacer(minLength: 0)
                }

                // Preview text
                Text(previewText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Metadata row
                HStack(spacing: 10) {
                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(session.running ? .green : .secondary)

                    Text(updatedTimeText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let cwd = session.cwd, !cwd.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text(cwd)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName), \(statusText), \(updatedTimeText)")
    }

    private var statusColor: Color {
        if session.running {
            return .green
        }
        return Color(.systemGray4)
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}
