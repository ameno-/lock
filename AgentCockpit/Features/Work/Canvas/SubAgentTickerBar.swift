// SubAgentTickerBar.swift — Sliding top overlay with live sub-agent timers
import SwiftUI

struct SubAgentTickerBar: View {
    let agents: [SubAgentEvent]

    var body: some View {
        if !agents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(agents, id: \.subSessionKey) { agent in
                        AgentTickerChip(agent: agent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Divider().opacity(0.3)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

private struct AgentTickerChip: View {
    let agent: SubAgentEvent

    var body: some View {
        TimelineView(.periodic(from: agent.startedAt, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(agent.startedAt))
            HStack(spacing: 6) {
                Text("🤖")
                    .font(.caption)
                Text(agent.subSessionKey.prefix(12))
                    .font(.caption.weight(.medium))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(formatElapsed(elapsed))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.yellow.opacity(0.3), lineWidth: 0.5))
        }
    }
}
