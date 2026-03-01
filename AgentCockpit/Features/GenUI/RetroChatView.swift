import SwiftUI

// MARK: - Models
struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    var genUISurface: GenUIEvent? = nil

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.isUser == rhs.isUser
    }
}

enum AgentState {
    case idle
    case thinking
    case typing
}

// MARK: - Colors - Retro Palette
extension Color {
    static let cream = Color(hex: 0xF5F2E8)
    static let olive = Color(hex: 0x5B7B4A)
    static let oliveDark = Color(hex: 0x3D5A30)
    static let oliveLight = Color(hex: 0x7A9B6A)
    static let coral = Color(hex: 0xE07A5F)
    static let coralLight = Color(hex: 0xF2A594)
    static let sand = Color(hex: 0xF2CC8F)
    static let shadowSoft = Color(hex: 0x5B7B4A).opacity(0.15)
    static let shadowHard = Color(hex: 0x5B7B4A).opacity(0.25)

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Main View - Borderless Integrated Retro Chat
struct RetroChatView: View {
    @State private var messages: [ChatMessage] = [
        ChatMessage(text: "Hello! I'm your friendly AI assistant. How can I help you today?", isUser: false)
    ]
    @State private var inputText: String = ""
    @State private var agentState: AgentState = .idle

    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            RetroAnimatedBackgroundView()

            VStack(spacing: 0) {
                Spacer(minLength: 6)

                RetroAvatarSection(agentState: $agentState)
                    .padding(.vertical, 10)

                messagesScrollView
            }
            .padding(.horizontal, 10)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
                .foregroundColor(.olive)
                .font(.custom("Courier New", size: 14))
            }
        }
        .safeAreaInset(edge: .bottom) {
            messageInputSection
                .onTapGesture {
                    isInputFocused = true
                }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isInputFocused = true
            }
        }
    }

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        RetroMessageBubbleView(message: message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .scrollIndicators(.hidden)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.bouncy(duration: 0.4)) {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var messageInputSection: some View {
        RetroInputSection(
            inputText: $inputText,
            agentState: $agentState,
            isInputFocused: $isInputFocused,
            onSend: sendMessage
        )
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.olive.opacity(0.18))
                .frame(height: 1)
        }
        .padding(.bottom, 0)
    }

    private func sendMessage() {
        guard agentState == .idle else { return }
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let newUserMsg = ChatMessage(text: inputText, isUser: true)
        inputText = ""
        withAnimation(.bouncy(duration: 0.4)) {
            messages.append(newUserMsg)
        }

        isInputFocused = true

        withAnimation(.spring(duration: 0.5)) {
            agentState = .thinking
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(duration: 0.5)) {
                agentState = .typing
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let responses = [
                    "That's an interesting perspective! Let me expand on that...",
                    "I'd be happy to help with that. Here are some options.",
                    "Fascinating! Give me just a moment to pull up the details.",
                    "Here's a detailed generative UI component based on your request."
                ]

                let aiMsg = ChatMessage(text: responses.randomElement()!, isUser: false)
                withAnimation(.bouncy(duration: 0.4)) {
                    messages.append(aiMsg)
                    agentState = .idle
                }
            }
        }
    }
}

// MARK: - Input Section with Focus
struct RetroInputSection: View {
    @Binding var inputText: String
    @Binding var agentState: AgentState
    var isInputFocused: FocusState<Bool>.Binding
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Type your message...", text: $inputText)
                .font(.custom("Courier New", size: 14))
                .focused(isInputFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.olive, lineWidth: 2)
                )
                .shadow(color: .shadowSoft, radius: 0, x: 2, y: 2)
                .disabled(agentState != .idle)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .submitLabel(.send)
                .onSubmit { onSend() }

            Button(action: onSend) {
                Text("Send")
                    .font(.custom("Courier New", size: 14).weight(.bold))
                    .foregroundColor(.cream)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.olive)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.oliveDark, lineWidth: 2)
                    )
                    .shadow(color: .shadowHard, radius: 0, x: 3, y: 3)
            }
            .buttonStyle(RetroButtonStyle())
            .disabled(agentState != .idle || inputText.isEmpty)
            .opacity(agentState != .idle ? 0.6 : 1.0)
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.35))
    }
}

struct RetroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Avatar Section
struct RetroAvatarSection: View {
    @Binding var agentState: AgentState

    var body: some View {
        RetroMorphingAvatar(state: agentState)
            .frame(width: 92, height: 92)
            .accessibilityIdentifier("retro-agent-avatar")
    }
}

// MARK: - Morphing Avatar
struct RetroMorphingAvatar: View {
    let state: AgentState

    @State private var floatOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var morphOffset: CGFloat = 0

    var body: some View {
        ZStack {
            switch state {
            case .idle:
                idleAvatar

            case .thinking:
                thinkingAvatar

            case .typing:
                typingAvatar
            }
        }
    }

    private var idleAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: morphCornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [.cream, .sand], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 92, height: 92)
                .offset(y: floatOffset)

            Circle()
                .fill(Color.coralLight.opacity(0.45))
                .frame(width: 28, height: 28)
                .offset(x: -14 + morphOffset * 8, y: -12 - morphOffset * 4)

            Circle()
                .fill(Color.olive.opacity(0.2))
                .frame(width: 16, height: 16)
                .offset(x: 12 - morphOffset * 12, y: 14 + morphOffset * 4)
        }
        .rotationEffect(.degrees(Double(floatOffset)))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                floatOffset = -6
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                morphOffset = 1
            }
        }
    }

    private var thinkingAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [.coralLight, .sand], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 96, height: 84)
                .rotationEffect(.degrees(rotation))

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [.sand, .coralLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 52, height: 68)
                .rotationEffect(.degrees(-rotation * 1.4))
        }
        .onAppear {
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                morphOffset = 0.7
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                floatOffset = -8
            }
        }
        .frame(width: 96, height: 92)
    }

    private var typingAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: morphCornerRadius, style: .continuous)
                .fill(RadialGradient(colors: [.coralLight, .coral], center: .topLeading, startRadius: 8, endRadius: 62))
                .frame(width: 88, height: 88)
                .scaleEffect(1.0 + morphOffset * 0.06)

            HStack(spacing: 3) {
                RetroDot()
                RetroDot(delay: 0.15)
                RetroDot(delay: 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                morphOffset = 1
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                floatOffset = -4
            }
        }
    }

    private var morphCornerRadius: CGFloat {
        let progress = (sin(rotation + Double(morphOffset) * 2) + 1) / 2
        return 18 + CGFloat(progress * 26)
    }

}

struct RetroDot: View {
    var delay: Double = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        Circle()
            .fill(Color.olive)
            .frame(width: 6, height: 6)
            .offset(y: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay)) {
                    offset = -4
                }
            }
    }
}

// MARK: - Message Bubble
struct RetroMessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if !message.isUser {
                Circle()
                    .fill(LinearGradient(colors: [.coralLight, .sand], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .fill(Color.olive.opacity(0.18))
                            .frame(width: 8, height: 8)
                    )
            } else {
                Spacer(minLength: 38)
            }

            if message.isUser {
                Text(message.text)
                    .font(.custom("Courier New", size: 13))
                    .foregroundColor(.cream)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.olive)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.oliveDark, lineWidth: 2)
                    )
                    .shadow(color: .shadowSoft, radius: 0, x: 2, y: 2)
            } else {
                Text(message.text)
                    .font(.custom("Courier New", size: 13))
                    .foregroundColor(.oliveDark)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color(hex: 0xFDF9ED), Color(hex: 0xF4EFD7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.olive.opacity(0.05))
                                .padding(2)
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .shadowSoft, radius: 4, x: 1, y: 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.2))
                            .blendMode(.screen)
                    }
            }

            if message.isUser {
                Circle()
                    .fill(Color.olive)
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 12)).foregroundColor(.cream))
            } else {
                Spacer(minLength: 38)
            }
        }
    }
}

// MARK: - Animated Background
struct RetroAnimatedBackgroundView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()

            Circle()
                .fill(Color(hex: 0xE8D5F2).opacity(0.5))
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .offset(x: isAnimating ? -80 : 80, y: isAnimating ? -150 : 0)

            Circle()
                .fill(Color(hex: 0xD5E8F2).opacity(0.4))
                .frame(width: 350, height: 350)
                .blur(radius: 70)
                .offset(x: isAnimating ? 120 : -40, y: isAnimating ? 150 : -80)

            Circle()
                .fill(Color(hex: 0xF2D5E8).opacity(0.35))
                .frame(width: 220, height: 220)
                .blur(radius: 45)
                .offset(x: isAnimating ? 0 : 80, y: isAnimating ? 80 : 250)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Preview
#Preview {
    RetroChatView()
}
