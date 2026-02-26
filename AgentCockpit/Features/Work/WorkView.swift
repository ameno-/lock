// WorkView.swift — Main work canvas with event cards and agentic keyboard
import SwiftUI

struct WorkView: View {
    @State private var viewModel: WorkViewModel
    @Environment(AppModel.self) private var appModel

    init(appModel: AppModel) {
        _viewModel = State(initialValue: WorkViewModel(appModel: appModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            withAnimation {
                SubAgentTickerBar(agents: viewModel.runningSubAgents)
            }

            if viewModel.canvasEvents.isEmpty {
                emptyState
            } else {
                EventCanvasView(
                    events: viewModel.canvasEvents,
                    onViewSubAgentInAIs: { _ in
                        appModel.selectedTab = .ais
                    }
                )
            }
        }
        .navigationTitle("Work")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().opacity(0.3)
                InlineAgenticKeyboard(
                    text: $viewModel.inputText,
                    onSend: { text in viewModel.send(text: text) },
                    onAbort: { viewModel.abort() },
                    snippetCategories: viewModel.snippetCategories
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Work")
                        .font(.headline)
                    if let key = viewModel.activeSessionKey {
                        Text(key.prefix(20))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                StatusPill(state: viewModel.connectionState)
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            viewModel.subscribeToActive()
        }
        .onChange(of: appModel.promotedSessionKey) { _, _ in
            viewModel.activateSessionIfNeeded()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                viewModel.activeSessionKey == nil ? "No Active Session" : "No Events Yet",
                systemImage: "waveform.and.sparkles"
            )
        } description: {
            Text(
                viewModel.activeSessionKey == nil
                    ? "Open the AIs tab and tap a session to open chat."
                    : "Session context will appear here. Send a message to continue the thread."
            )
        }
    }
}
