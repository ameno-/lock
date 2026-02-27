import SwiftUI

struct WorkTranscriptView: View {
    let events: [CanvasEvent]
    let displayMode: ACTranscriptDisplayMode
    var onViewSubAgentInAIs: ((SubAgentEvent) -> Void)?
    var onGenUIAction: ((GenUIEvent) -> Void)?
    var genUIActionState: ((String, String) -> GenUIActionDispatchState?)?

    @State private var isAtBottom = true
    @State private var latestMarker = ""

    private var entries: [WorkTranscriptEntry] {
        WorkTranscriptMapper.entries(
            from: events,
            policy: WorkTranscriptDisplayPolicy(displayMode: displayMode)
        )
    }

    init(
        events: [CanvasEvent],
        displayMode: ACTranscriptDisplayMode = .standard,
        onViewSubAgentInAIs: ((SubAgentEvent) -> Void)? = nil,
        onGenUIAction: ((GenUIEvent) -> Void)? = nil,
        genUIActionState: ((String, String) -> GenUIActionDispatchState?)? = nil
    ) {
        self.events = events
        self.displayMode = displayMode
        self.onViewSubAgentInAIs = onViewSubAgentInAIs
        self.onGenUIAction = onGenUIAction
        self.genUIActionState = genUIActionState
    }

    var body: some View {
        if events.isEmpty {
            ContentUnavailableView {
                Label("No Events Yet", systemImage: "waveform.and.sparkles")
            } description: {
                Text("Session context will appear here once messages or updates arrive.")
            }
        } else if entries.isEmpty {
            EventCanvasView(
                events: events,
                onViewSubAgentInAIs: onViewSubAgentInAIs,
                onGenUIAction: onGenUIAction,
                genUIActionState: genUIActionState
            )
        } else {
            transcriptBody
        }
    }

    private var transcriptBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(entries, id: \.id) { entry in
                        row(for: entry)
                            .id(entry.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("__work_bottom__")
                }
                .padding(.top, 12)
            }
            .onAppear {
                latestMarker = marker
                isAtBottom = false
            }
            .onChange(of: marker) { _, newValue in
                guard !newValue.isEmpty else { return }
                guard newValue != latestMarker else { return }
                latestMarker = newValue
                guard isAtBottom else { return }
                scrollToBottomAfterLayout(proxy: proxy, animated: true)
            }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { _ in
                        isAtBottom = false
                    }
            )
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom && !entries.isEmpty {
                    Button {
                        isAtBottom = true
                        scrollToBottom(proxy: proxy, animated: true)
                    } label: {
                        if #available(iOS 26, *) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(12)
                                .glassEffect(.regular.interactive(), in: .circle)
                        } else {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var marker: String {
        guard let last = entries.last else { return "" }
        let seconds = Int(last.timestamp.timeIntervalSince1970 * 1000)
        return "\(last.id)-\(seconds)"
    }

    @ViewBuilder
    private func row(for entry: WorkTranscriptEntry) -> some View {
        switch entry {
        case .message(let message):
            TranscriptMessageRow(message: message)
                .padding(.horizontal, 12)
        case .event(let event):
            EventCardRouter(event: event) {
                if case .subAgent(let subAgent) = event {
                    onViewSubAgentInAIs?(subAgent)
                }
            } onGenUIAction: { genui in
                onGenUIAction?(genui)
            } genUIActionState: { surfaceID, actionID in
                genUIActionState?(surfaceID, actionID)
            }
            .padding(.horizontal, 12)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("__work_bottom__", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("__work_bottom__", anchor: .bottom)
        }
    }

    private func scrollToBottomAfterLayout(proxy: ScrollViewProxy, animated: Bool) {
        Task { @MainActor in
            await Task.yield()
            scrollToBottom(proxy: proxy, animated: animated)
        }
    }
}

private struct TranscriptMessageRow: View {
    let message: WorkTranscriptMessageEntry

    private var isUser: Bool {
        message.role == .user
    }

    private var titleText: String {
        switch message.role {
        case .user:
            return "You"
        case .assistant:
            return "Assistant"
        case .thinking:
            return "Thinking"
        case .system:
            return "System"
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 36)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(titleText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(titleColor)

                Text(message.text)
                    .font(message.role == .thinking ? .footnote.italic() : .subheadline)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(backgroundStyle)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var textColor: Color {
        switch message.role {
        case .user:
            return .primary
        case .assistant:
            return .primary
        case .thinking:
            return .secondary
        case .system:
            return .secondary
        }
    }

    private var titleColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return .primary
        case .thinking:
            return .purple
        case .system:
            return .secondary
        }
    }

    private var borderColor: Color {
        switch message.role {
        case .user:
            return .blue.opacity(0.25)
        case .assistant:
            return Color(.systemGray5)
        case .thinking:
            return .purple.opacity(0.2)
        case .system:
            return Color(.systemGray5)
        }
    }

    private var backgroundStyle: some ShapeStyle {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.08)
        case .assistant:
            return Color(.secondarySystemBackground)
        case .thinking:
            return Color.purple.opacity(0.08)
        case .system:
            return Color(.tertiarySystemBackground)
        }
    }
}
