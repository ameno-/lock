// StatusPill.swift — Connection status indicator badge
import SwiftUI

public struct StatusPill: View {
    public let state: ACConnectionState

    public init(state: ACConnectionState) {
        self.state = state
    }

    private var label: String {
        switch state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .authenticating: return "Authenticating…"
        case .connected: return "Connected"
        case .failed(let msg): return "Error: \(msg.prefix(30))"
        }
    }

    private var color: Color {
        switch state {
        case .connected: return .green
        case .connecting, .authenticating: return .yellow
        case .disconnected: return .secondary
        case .failed: return .red
        }
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 3)
                        .scaleEffect(state == .connected ? 1.5 : 1)
                        .opacity(state == .connected ? 0 : 1)
                        .animation(
                            state == .connected
                                ? .easeOut(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: state == .connected
                        )
                )

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
    }
}
