import SwiftUI

private struct ChatDemoMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
    var isAnimating: Bool = false
}

private struct ChatDemoTheme {
    let backgroundTop = Color(red: 0.04, green: 0.08, blue: 0.13)
    let backgroundBottom = Color(red: 0.02, green: 0.03, blue: 0.05)
    let accentA = Color(red: 0.12, green: 0.72, blue: 0.88)
    let accentB = Color(red: 0.00, green: 0.45, blue: 0.92)
    let assistantBubbleTop = Color.white.opacity(0.12)
    let assistantBubbleBottom = Color.white.opacity(0.05)
}

struct ChatUIDemoView: View {
    @State private var messages: [ChatDemoMessage] = [
        ChatDemoMessage(content: "Hello. I can summarize activity, run through plans, or draft commands.", isUser: false)
    ]
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var responseTask: Task<Void, Never>?

    private let theme = ChatDemoTheme()

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                ChatDemoHeader(theme: theme)
                messageList
            }

            VStack {
                Spacer()
                ChatDemoInputBar(
                    text: $inputText,
                    theme: theme,
                    onSend: sendMessage
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .navigationTitle("Chat UI Demo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onDisappear {
            responseTask?.cancel()
            responseTask = nil
        }
    }

    @ViewBuilder
    private var background: some View {
        LinearGradient(
            colors: [theme.backgroundTop, theme.backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                ZStack {
                    Circle()
                        .fill(theme.accentA.opacity(0.16))
                        .frame(width: width * 0.8, height: width * 0.8)
                        .blur(radius: 50)
                        .offset(x: -width * 0.28, y: -height * 0.30)
                    Circle()
                        .fill(theme.accentB.opacity(0.14))
                        .frame(width: width * 0.9, height: width * 0.9)
                        .blur(radius: 62)
                        .offset(x: width * 0.30, y: height * 0.34)
                }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(messages) { message in
                        ChatDemoMessageRow(message: message, theme: theme)
                            .id(message.id)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .onChange(of: messages.count) { _, _ in
                guard let lastID = messages.last?.id else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .simultaneousGesture(DragGesture().onChanged { _ in inputFocused = false })
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatDemoMessage(content: trimmed, isUser: true))
        inputText = ""

        responseTask?.cancel()
        responseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            messages.append(
                ChatDemoMessage(
                    content: generatedReply(for: trimmed),
                    isUser: false,
                    isAnimating: true
                )
            )
        }
    }

    private func generatedReply(for prompt: String) -> String {
        let normalized = prompt.lowercased()
        if normalized.contains("timer") {
            return "Timer concept acknowledged. I would render this as a progress surface and patch it per second (5 → 0)."
        }
        if normalized.contains("plan") {
            return "Plan drafted:\n1. Capture active events\n2. Map to structured components\n3. Render transcript + cards\n4. Dispatch actions"
        }
        if normalized.contains("error") || normalized.contains("fail") {
            return "I found a likely failure path. Next: inspect logs, verify tool result payload, then patch transport fallback ordering."
        }
        return "Received. I can convert that into a structured response surface with metrics, checklist state, and action controls."
    }
}

private struct ChatDemoHeader: View {
    let theme: ChatDemoTheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Relay")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green.opacity(0.85))
                        .frame(width: 7, height: 7)
                    Text("Connected")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            Spacer(minLength: 12)

            ChatDemoOrb(theme: theme)
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.26), Color.black.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
    }
}

private struct ChatDemoMessageRow: View {
    let message: ChatDemoMessage
    let theme: ChatDemoTheme

    var body: some View {
        HStack(spacing: 0) {
            if message.isUser {
                Spacer(minLength: 44)
            }

            Group {
                if !message.isUser, message.isAnimating {
                    ChatDemoTypewriterText(text: message.content)
                } else {
                    Text(message.content)
                }
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(bubbleBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(message.isUser ? 0.16 : 0.11), lineWidth: 0.6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 6)
            .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser {
                Spacer(minLength: 44)
            }
        }
        .padding(.horizontal, 14)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isUser {
            LinearGradient(
                colors: [theme.accentA.opacity(0.92), theme.accentB.opacity(0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [theme.assistantBubbleTop, theme.assistantBubbleBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct ChatDemoInputBar: View {
    @Binding var text: String
    let theme: ChatDemoTheme
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                // reserved for attachments in the demo
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08), in: Circle())
            }

            TextField("Type a message...", text: $text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [theme.accentA, theme.accentB],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .shadow(color: theme.accentA.opacity(0.5), radius: 8, x: 0, y: 4)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
        }
    }
}

private struct ChatDemoTypewriterText: View {
    let text: String

    @State private var visibleCharacters = 0
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        Text(String(text.prefix(visibleCharacters)))
            .onAppear {
                startReveal()
            }
            .onChange(of: text) { _, _ in
                startReveal()
            }
            .onDisappear {
                revealTask?.cancel()
                revealTask = nil
            }
    }

    private func startReveal() {
        revealTask?.cancel()
        visibleCharacters = 0
        let characters = text.count
        revealTask = Task { @MainActor in
            guard characters > 0 else { return }
            while visibleCharacters < characters {
                try? await Task.sleep(nanoseconds: 22_000_000)
                guard !Task.isCancelled else { return }
                visibleCharacters += 1
            }
        }
    }
}

private struct ChatDemoOrb: View {
    let theme: ChatDemoTheme
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.accentA.opacity(0.26))
                .scaleEffect(animate ? 1.20 : 0.78)
                .blur(radius: animate ? 10 : 4)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [theme.accentA, theme.accentB],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(animate ? 0.88 : 1.0)

            Circle()
                .fill(.white.opacity(0.30))
                .frame(width: 12, height: 12)

            Circle()
                .stroke(.white.opacity(0.42), lineWidth: 1)
                .padding(1)
                .rotationEffect(.degrees(animate ? 320 : 0))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}
