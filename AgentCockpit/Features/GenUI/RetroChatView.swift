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

// MARK: - Colors
extension Color {
    static let cream = Color(hex: 0xF5F2E8)
    static let olive = Color(hex: 0x5B7B4A)
    static let oliveDark = Color(hex: 0x3D5A30)
    static let oliveLight = Color(hex: 0x7A9B6A)
    static let coral = Color(hex: 0xE07A5F)
    static let coralLight = Color(hex: 0xF2A594)
    static let sand = Color(hex: 0xF2CC8F)
    
    // Custom shadows
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

// MARK: - Main View
struct RetroChatView: View {
    @State private var messages: [ChatMessage] = [
        ChatMessage(text: "Hello! I'm your friendly AI assistant. How can I help you today?", isUser: false)
    ]
    @State private var inputText: String = ""
    @State private var agentState: AgentState = .idle
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        ZStack {
            // Organic Background
            RetroAnimatedBackgroundView()
            
            VStack(spacing: 0) {
                // Main Chat Window
                VStack(spacing: 0) {
                    RetroWindowHeader()
                    
                    // Avatar & Reactions Section
                    RetroAvatarSection(agentState: $agentState)
                        .padding(.vertical, 20)
                    
                    RetroStatusText(agentState: agentState)
                    
                    // Messages Area
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
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: messages.count) { _, _ in
                            withAnimation(.bouncy(duration: 0.5)) {
                                if let lastMessage = messages.last {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // Input Area
                    RetroInputSection(
                        inputText: $inputText,
                        agentState: $agentState,
                        isInputFocused: $isInputFocused,
                        onSend: sendMessage
                    )
                    
                    Text("v1.0 • Playful Chat")
                        .font(.custom("Courier New", size: 10))
                        .foregroundColor(.oliveLight)
                        .padding(.bottom, 16)
                }
                .retroCard()
                .padding()
            }
        }
    }
    
    // MARK: - Actions
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let newUserMsg = ChatMessage(text: inputText, isUser: true)
        withAnimation(.bouncy(duration: 0.4)) {
            messages.append(newUserMsg)
            inputText = ""
        }
        isInputFocused = false
        
        // Trigger AI thinking animation
        withAnimation(.spring(duration: 0.5)) { agentState = .thinking }
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(duration: 0.5)) { agentState = .typing }
            
            // Generate response
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

// MARK: - Subcomponents

struct RetroWindowHeader: View {
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.coral)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.olive, lineWidth: 1))
                Circle()
                    .fill(Color.sand)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.olive, lineWidth: 1))
                Circle()
                    .fill(Color.olive)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.oliveDark, lineWidth: 1))
            }
            Spacer()
            Text("Chat Assistant")
                .font(.custom("Courier New", size: 12).weight(.bold))
                .foregroundColor(.olive)
        }
        .padding(16)
    }
}

struct RetroStatusText: View {
    let agentState: AgentState
    
    var body: some View {
        Text(statusString)
            .font(.custom("Courier New", size: 12))
            .foregroundColor(.oliveLight)
            .padding(.bottom, 8)
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
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.olive, lineWidth: 2)
                )
                .shadow(color: .shadowSoft, radius: 0, x: 2, y: 2)
                .disabled(agentState != .idle)
                .onSubmit { onSend() }
            
            Button(action: onSend) {
                Text("Send")
                    .font(.custom("Courier New", size: 14).weight(.bold))
                    .foregroundColor(.cream)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.olive)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.oliveDark, lineWidth: 2)
                    )
                    .shadow(color: .shadowHard, radius: 0, x: 4, y: 4)
            }
            .buttonStyle(RetroButtonStyle())
            .disabled(agentState != .idle || inputText.isEmpty)
            .opacity(agentState != .idle ? 0.6 : 1.0)
        }
        .padding(16)
    }
}

// MARK: - Avatar & Animation Components
struct RetroAvatarSection: View {
    @Binding var agentState: AgentState
    
    var body: some View {
        ZStack {
            // Main Avatar Box
            RetroMorphingAvatar(state: agentState)
                .frame(width: 120, height: 120)
                .padding(16)
                .retroCard(cornerRadius: 24, shadowOffset: 4)
                .zIndex(1)
            
            // Thumbs Down/Up reactions
            HStack {
                RetroReactionButton(icon: "hand.thumbsdown", isPositive: false)
                    .offset(x: -24)
                Spacer()
                RetroReactionButton(icon: "hand.thumbsup", isPositive: true)
                    .offset(x: 24)
            }
            .frame(width: 200)
            .zIndex(0)
        }
    }
}

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
            .overlay(Circle().stroke(Color.olive, lineWidth: 3))
            .overlay(
                Text(":)")
                    .font(.custom("Courier New", size: 36).weight(.bold))
                    .foregroundColor(.olive)
            )
            .offset(y: floatOffset)
            .rotationEffect(.degrees(floatOffset * 0.5))
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    floatOffset = -8
                }
            }
    }
    
    private var thinkingAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40)
                .fill(LinearGradient(colors: [.coralLight, .sand], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 40).stroke(Color.olive, lineWidth: 3))
                .rotationEffect(.degrees(rotation))
            
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [.sand, .coralLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 90, height: 90)
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
            .fill(RadialGradient(colors: [.coralLight, .coral], center: .topLeading, startRadius: 10, endRadius: 80))
            .overlay(Circle().stroke(Color.olive, lineWidth: 3))
            .scaleEffect(pulseScale)
            .overlay {
                HStack(spacing: 4) {
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
            .frame(width: 6, height: 6)
            .offset(y: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay)) {
                    offset = -4
                }
            }
    }
}

// MARK: - Custom Buttons & Effects
struct RetroReactionButton: View {
    let icon: String
    let isPositive: Bool
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: handleTap) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.olive)
                .frame(width: 56, height: 56)
                .background(isPressed ? (isPositive ? Color.sand : Color.coralLight) : Color.cream)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.olive, lineWidth: 2))
                .shadow(color: .shadowHard, radius: 0, x: isPressed ? 1 : 3, y: isPressed ? 1 : 3)
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

struct RetroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Message Bubble
struct RetroMessageBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if !message.isUser {
                // AI Avatar tiny
                Circle()
                    .fill(LinearGradient(colors: [.coralLight, .sand], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Color.olive, lineWidth: 2))
                    .overlay(Text("AI").font(.custom("Courier New", size: 10).weight(.bold)).foregroundColor(.olive))
            } else {
                Spacer(minLength: 44)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                Text(message.text)
                    .font(.custom("Courier New", size: 14))
                    .foregroundColor(message.isUser ? .cream : .olive)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(message.isUser ? Color.olive : Color.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(message.isUser ? Color.oliveDark : Color.olive, lineWidth: 2)
                    )
                    .shadow(color: .shadowSoft, radius: 0, x: 3, y: 3)
                
                // GenUI Surface placeholder - could integrate GenUI here
                if let surface = message.genUISurface {
                    RetroGenUISurfaceContainer(surface: surface)
                }
            }
            
            if message.isUser {
                // User Avatar tiny
                Circle()
                    .fill(Color.olive)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Color.oliveDark, lineWidth: 2))
                    .overlay(Image(systemName: "person.fill").font(.system(size: 14)).foregroundColor(.cream))
            } else {
                Spacer(minLength: 44)
            }
        }
    }
}

// MARK: - GenUI Integration Container
struct RetroGenUISurfaceContainer: View {
    let surface: GenUIEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !surface.title.isEmpty {
                Text(surface.title)
                    .font(.custom("Courier New", size: 12).weight(.bold))
                    .foregroundColor(.olive)
            }
            
            // Simplified GenUI rendering for retro chat
            if let body = surface.body.isEmpty ? nil : surface.body {
                Text(body)
                    .font(.custom("Courier New", size: 11))
                    .foregroundColor(.oliveLight)
            }
            
            // Action buttons if present
            if surface.actionLabel != nil || surface.actionPayload["actionId"] != nil {
                HStack(spacing: 8) {
                    Button(action: {}) {
                        Text(surface.actionLabel ?? "Continue")
                            .font(.custom("Courier New", size: 11).weight(.bold))
                            .foregroundColor(.cream)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sand, lineWidth: 2)
        )
    }
}

// MARK: - Animated Background
struct RetroAnimatedBackgroundView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()
            
            // Soft shifting blurred gradients
            Circle()
                .fill(Color(hex: 0xE8D5F2).opacity(0.6))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: isAnimating ? -100 : 100, y: isAnimating ? -200 : 0)
            
            Circle()
                .fill(Color(hex: 0xD5E8F2).opacity(0.5))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: isAnimating ? 150 : -50, y: isAnimating ? 200 : -100)
            
            Circle()
                .fill(Color(hex: 0xF2D5E8).opacity(0.4))
                .frame(width: 250, height: 250)
                .blur(radius: 50)
                .offset(x: isAnimating ? 0 : 100, y: isAnimating ? 100 : 300)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Previews
#Preview {
    RetroChatView()
}
