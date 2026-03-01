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

// MARK: - Retro Style Modifiers
struct RetroCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 24
    var shadowOffset: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background(Color.cream)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.olive, lineWidth: 2)
            )
            .shadow(color: .shadowHard, radius: 0, x: shadowOffset, y: shadowOffset)
    }
}

extension View {
    func retroCard(cornerRadius: CGFloat = 24, shadowOffset: CGFloat = 6) -> some View {
        self.modifier(RetroCardStyle(cornerRadius: cornerRadius, shadowOffset: shadowOffset))
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

                RetroStatusText(agentState: agentState)
                    .padding(.bottom, 6)

                messagesScrollView
            }
            .padding(.horizontal, 10)
        }
        .ignoresSafeArea(.keyboard)
        .scrollDismissesKeyboard(.interactively)
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

        isInputFocused = false

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

// MARK: - Status text
struct RetroStatusText: View {
    let agentState: AgentState

    var body: some View {
        Text(statusString)
            .font(.custom("Courier New", size: 12))
            .foregroundColor(.oliveLight)
            .animation(.easeInOut(duration: 0.3), value: agentState)
    }

    var statusString: String {
        switch agentState {
        case .idle: return "Ready to chat"
        case .thinking: return "Thinking..."
        case .typing: return "Typing..."
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
        ZStack {
            RetroMorphingAvatar(state: agentState)
                .frame(width: 100, height: 100)
                .retroCard(cornerRadius: 20, shadowOffset: 3)
                .zIndex(1)

            HStack {
                RetroReactionButton(icon: "hand.thumbsdown", isPositive: false)
                    .offset(x: -20)
                Spacer()
                RetroReactionButton(icon: "hand.thumbsup", isPositive: true)
                    .offset(x: 20)
            }
            .frame(width: 160)
            .zIndex(0)
        }
    }
}

// MARK: - Morphing Avatar
struct RetroMorphingAvatar: View {
    let state: AgentState

    @State private var floatOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0

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
        Circle()
            .fill(LinearGradient(colors: [.cream, .sand], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().stroke(Color.olive, lineWidth: 2))
            .overlay(
                Text(":)")
                    .font(.custom("Courier New", size: 28).weight(.bold))
                    .foregroundColor(.olive)
            )
            .offset(y: floatOffset)
            .rotationEffect(.degrees(floatOffset * 0.5))
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    floatOffset = -6
                }
            }
    }

    private var thinkingAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32)
                .fill(LinearGradient(colors: [.coralLight, .sand], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 32).stroke(Color.olive, lineWidth: 2))
                .rotationEffect(.degrees(rotation))

            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [.sand, .coralLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(-rotation * 1.5))
        }
        .onAppear {
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    private var typingAvatar: some View {
        Circle()
            .fill(RadialGradient(colors: [.coralLight, .coral], center: .topLeading, startRadius: 10, endRadius: 60))
            .overlay(Circle().stroke(Color.olive, lineWidth: 2))
            .scaleEffect(pulseScale)
            .overlay {
                HStack(spacing: 3) {
                    RetroDot()
                    RetroDot(delay: 0.15)
                    RetroDot(delay: 0.3)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulseScale = 1.08
                }
            }
    }
}

struct RetroDot: View {
    var delay: Double = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        Circle()
            .fill(Color.olive)
            .frame(width: 5, height: 5)
            .offset(y: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay)) {
                    offset = -3
                }
            }
    }
}

// MARK: - Reaction Button
struct RetroReactionButton: View {
    let icon: String
    let isPositive: Bool

    @State private var isPressed = false

    var body: some View {
        Button(action: handleTap) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.olive)
                .frame(width: 48, height: 48)
                .background(isPressed ? (isPositive ? Color.sand : Color.coralLight) : Color.cream)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.olive, lineWidth: 2))
                .shadow(color: .shadowHard, radius: 0, x: isPressed ? 1 : 2, y: isPressed ? 1 : 2)
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
    }

    private func handleTap() {
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.5)) {
            isPressed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.2)) { isPressed = false }
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
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.olive, lineWidth: 1.5))
                    .overlay(Text("AI").font(.custom("Courier New", size: 8).weight(.bold)).foregroundColor(.olive))
            } else {
                Spacer(minLength: 38)
            }

            Text(message.text)
                .font(.custom("Courier New", size: 13))
                .foregroundColor(message.isUser ? .cream : .olive)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(message.isUser ? Color.olive : Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(message.isUser ? Color.oliveDark : Color.olive, lineWidth: 2)
                )
                .shadow(color: .shadowSoft, radius: 0, x: 2, y: 2)

            if message.isUser {
                Circle()
                    .fill(Color.olive)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.oliveDark, lineWidth: 1.5))
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
