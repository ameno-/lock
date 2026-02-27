// WorkView.swift — Agmente-style work surface with interactive approvals and user-input requests
import SwiftUI

struct WorkView: View {
    @State private var viewModel: WorkViewModel
    @Environment(AppModel.self) private var appModel
    @State private var activeUserInputRequestID: String?

    init(appModel: AppModel) {
        _viewModel = State(initialValue: WorkViewModel(appModel: appModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.pendingApprovalRequests.isEmpty {
                approvalQueueSection
                    .padding(.top, 8)
            }

            withAnimation {
                SubAgentTickerBar(agents: viewModel.runningSubAgents)
            }

            Group {
                if viewModel.canvasEvents.isEmpty {
                    emptyState
                } else {
                    EventCanvasView(
                        events: viewModel.canvasEvents,
                        onViewSubAgentInAIs: { _ in
                            appModel.selectedTab = .sessions
                        },
                        onGenUIAction: { event in
                            viewModel.performGenUIAction(event)
                        }
                    )
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Session")
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
            .background(.ultraThinMaterial)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Session")
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
        .sheet(isPresented: .init(
            get: { activeUserInputRequest != nil },
            set: { if !$0 { activeUserInputRequestID = nil } }
        )) {
            if let request = activeUserInputRequest {
                PendingUserInputSheet(
                    request: request,
                    onSubmit: { answers in
                        viewModel.submitUserInput(requestID: request.id, answers: answers)
                        advanceUserInputQueue()
                    },
                    onSkip: {
                        viewModel.dismissUserInput(requestID: request.id)
                        advanceUserInputQueue()
                    }
                )
            }
        }
        .onAppear {
            viewModel.subscribeToActive()
            if activeUserInputRequestID == nil {
                activeUserInputRequestID = viewModel.pendingUserInputRequests.first?.id
            }
        }
        .onChange(of: appModel.promotedSessionKey) { _, _ in
            viewModel.activateSessionIfNeeded()
        }
        .onChange(of: viewModel.pendingUserInputRequests.map(\.id)) { _, _ in
            if activeUserInputRequestID == nil {
                activeUserInputRequestID = viewModel.pendingUserInputRequests.first?.id
            }
        }
    }

    private var activeUserInputRequest: ACPendingUserInputRequest? {
        guard let activeUserInputRequestID else { return nil }
        return viewModel.pendingUserInputRequests.first(where: { $0.id == activeUserInputRequestID })
    }

    private var approvalQueueSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.pendingApprovalRequests) { request in
                    PendingApprovalCard(
                        request: request,
                        onAccept: { viewModel.decideApproval(requestID: request.id, decision: .accept) },
                        onDecline: { viewModel.decideApproval(requestID: request.id, decision: .decline) },
                        onCancel: { viewModel.decideApproval(requestID: request.id, decision: .cancel) }
                    )
                }
            }
            .padding(.horizontal, 12)
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
                    ? "Select a session from the session list to start chatting."
                    : "Session context will appear here. Send a message to continue the thread."
            )
        }
    }

    private func advanceUserInputQueue() {
        activeUserInputRequestID = viewModel.pendingUserInputRequests.first?.id
    }
}

private struct PendingApprovalCard: View {
    let request: ACPendingApprovalRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Approval Required")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }

            if let command = request.command, !command.isEmpty {
                Text(command)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            } else if let reason = request.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Accept", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Decline", action: onDecline)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct PendingUserInputSheet: View {
    let request: ACPendingUserInputRequest
    let onSubmit: ([String: [String]]) -> Void
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedByQuestionID: [String: Set<String>] = [:]
    @State private var otherTextByQuestionID: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tool Requested Input")
                        .font(.headline)

                    ForEach(request.questions) { question in
                        VStack(alignment: .leading, spacing: 8) {
                            if !question.header.isEmpty {
                                Text(question.header)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(question.prompt)
                                .font(.subheadline)

                            ForEach(question.options) { option in
                                if option.isOther {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(option.label)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        if option.isSecret {
                                            SecureField("Enter value", text: Binding(
                                                get: { otherTextByQuestionID[question.id] ?? "" },
                                                set: { otherTextByQuestionID[question.id] = $0 }
                                            ))
                                            .textFieldStyle(.roundedBorder)
                                        } else {
                                            TextField("Enter value", text: Binding(
                                                get: { otherTextByQuestionID[question.id] ?? "" },
                                                set: { otherTextByQuestionID[question.id] = $0 }
                                            ))
                                            .textFieldStyle(.roundedBorder)
                                        }
                                    }
                                    .padding(.top, 4)
                                } else {
                                    Button {
                                        toggle(optionLabel: option.label, for: question)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: isSelected(optionLabel: option.label, for: question)
                                                ? (question.allowsMultipleSelections ? "checkmark.square.fill" : "largecircle.fill.circle")
                                                : (question.allowsMultipleSelections ? "square" : "circle"))
                                                .foregroundStyle(isSelected(optionLabel: option.label, for: question) ? .blue : .secondary)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(option.label)
                                                    .foregroundStyle(.primary)
                                                if let details = option.details, !details.isEmpty {
                                                    Text(details)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(16)
            }
            .navigationTitle("Action Required")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        onSubmit(answerPayload())
                        dismiss()
                    }
                    .disabled(!hasAnyAnswer)
                }
            }
        }
    }

    private var hasAnyAnswer: Bool {
        for question in request.questions {
            if let selected = selectedByQuestionID[question.id], !selected.isEmpty {
                return true
            }
            if let other = otherTextByQuestionID[question.id], !other.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }
        return false
    }

    private func isSelected(optionLabel: String, for question: ACUserInputQuestion) -> Bool {
        selectedByQuestionID[question.id]?.contains(optionLabel) == true
    }

    private func toggle(optionLabel: String, for question: ACUserInputQuestion) {
        var existing = selectedByQuestionID[question.id] ?? []
        if question.allowsMultipleSelections {
            if existing.contains(optionLabel) {
                existing.remove(optionLabel)
            } else {
                existing.insert(optionLabel)
            }
        } else {
            existing = [optionLabel]
        }
        selectedByQuestionID[question.id] = existing
    }

    private func answerPayload() -> [String: [String]] {
        var payload: [String: [String]] = [:]

        for question in request.questions {
            var values = Array(selectedByQuestionID[question.id] ?? []).sorted()
            if let other = otherTextByQuestionID[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !other.isEmpty {
                values.append(other)
            }
            if !values.isEmpty {
                payload[question.id] = values
            }
        }

        return payload
    }
}
