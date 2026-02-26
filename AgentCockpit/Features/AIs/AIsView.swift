// AIsView.swift — Agent session list with polling
import SwiftUI

struct AIsView: View {
    @State private var viewModel: AIsViewModel
    @Environment(AppModel.self) private var appModel

    init(appModel: AppModel) {
        _viewModel = State(initialValue: AIsViewModel(appModel: appModel))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessions.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView {
                        Label("No Sessions", systemImage: "terminal")
                    } description: {
                        Text(emptyDescription)
                    }
                } else {
                    List(viewModel.sessions) { session in
                        let isPromoted = appModel.promotedSessionKey == session.key
                        let summary = viewModel.rowSummary(for: session, isPromoted: isPromoted)
                        HStack(spacing: 10) {
                            Button {
                                viewModel.promote(session: session)
                            } label: {
                                AgentRowView(summary: summary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .buttonStyle(.plain)

                            NavigationLink {
                                AgentDetailView(session: session)
                                    .environment(appModel)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await viewModel.refresh() }
                }
            }
            .navigationTitle("AIs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.createSession() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create Session")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    StatusPill(state: appModel.connection.state)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
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

    private var emptyDescription: String {
        switch appModel.settings.serverProtocol {
        case .gatewayLegacy:
            "No tmux sessions found.\nStart a Claude Code session on your VPS."
        case .acp:
            "No ACP sessions found.\nCreate one with + or start one on your ACP server."
        case .codex:
            "No Codex threads found.\nCreate one with + or resume an existing thread."
        }
    }
}
