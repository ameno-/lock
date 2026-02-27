// AIsView.swift — Agmente-style session index with session-first workflow
import SwiftUI

struct AIsView: View {
    @State private var viewModel: AIsViewModel
    @State private var isShowingGenUIDemo = false
    @State private var isShowingSettings = false
    @Environment(AppModel.self) private var appModel

    init(appModel: AppModel) {
        _viewModel = State(initialValue: AIsViewModel(appModel: appModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            demoEntry

            if !viewModel.sessions.isEmpty {
                filterBar
            }

            Group {
                if viewModel.sessions.isEmpty && !viewModel.isLoading {
                    emptyState
                } else if viewModel.visibleSessions.isEmpty && !viewModel.isLoading {
                    filteredEmptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.visibleSessions) { session in
                                let isPromoted = appModel.promotedSessionKey == session.key
                                let summary = viewModel.rowSummary(for: session, isPromoted: isPromoted)
                                Button {
                                    viewModel.promote(session: session)
                                } label: {
                                    AgentRowView(summary: summary)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Open Session") {
                                        viewModel.promote(session: session)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .refreshable { await viewModel.refresh() }
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .searchable(text: $viewModel.searchQuery, prompt: "Search sessions")
        .navigationDestination(isPresented: $isShowingGenUIDemo) {
            GenUIDemoView()
                .environment(appModel)
        }
        .navigationDestination(isPresented: $isShowingSettings) {
            SettingsView()
                .environment(appModel)
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                StatusPill(state: appModel.connection.state)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    GenUIDemoView()
                        .environment(appModel)
                } label: {
                    Image(systemName: "puzzlepiece.extension")
                }
                .accessibilityLabel("Open GenUI Demo")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await viewModel.createSession() }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Session")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Open Settings")
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private var demoEntry: some View {
        Button {
            isShowingGenUIDemo = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GenUI Demo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Preview and inject response surfaces")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityLabel("Open GenUI Demo")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Sessions", systemImage: "ellipsis.message")
        } description: {
            Text(emptyDescription)
        } actions: {
            Button("Create Session") {
                Task { await viewModel.createSession() }
            }
            .buttonStyle(.borderedProminent)
            Button("Open Settings") {
                isShowingSettings = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptyDescription: String {
        switch appModel.settings.serverProtocol {
        case .acp:
            "No ACP sessions found. Create one with + or start one on your ACP server."
        case .codex:
            "No Codex threads found. Create one with + or resume an existing thread."
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label("No Matching Sessions", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Try changing the filter or search query.")
        } actions: {
            if viewModel.hasActiveFilters {
                Button("Clear Filters") {
                    viewModel.resetFilters()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            Picker("Session Filter", selection: $viewModel.selectedFilter) {
                ForEach(SessionListFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}
