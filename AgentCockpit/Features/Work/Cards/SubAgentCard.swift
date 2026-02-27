// SubAgentCard.swift
// ┌─ 🤖 Sub-Agent Spawned ─────────────────────── ┐
// │  claude-sonnet-4-6 · session: explore-abc       │
// │  ● Running · 0:23 elapsed   [View in AIs →]    │
// └────────────────────────────────────────────────┘
import SwiftUI

struct SubAgentCard: View {
    let event: SubAgentEvent
    var onViewInAIs: (() -> Void)? = nil

    var body: some View {
        CardBase {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(icon: "🤖", title: phaseTitle)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let model = event.modelName {
                            Text(model)
                                .font(.caption.weight(.medium))
                        }
                        Text("session: \(event.subSessionKey.prefix(20))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if event.phase == .spawned || event.phase == .running {
                        TimelineView(.periodic(from: event.startedAt, by: 1)) { context in
                            let elapsed = Int(context.date.timeIntervalSince(event.startedAt))
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.yellow)
                                    .frame(width: 6, height: 6)
                                Text(formatElapsed(elapsed))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if event.phase == .done || event.phase == .failed {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(event.phase == .done ? .green : .red)
                            .frame(width: 6, height: 6)
                        Text(event.phase == .done ? "Completed" : "Failed")
                            .font(.caption2)
                            .foregroundStyle(event.phase == .done ? .green : .red)
                    }
                }

                if let onViewInAIs {
                    Button("View in AIs →", action: onViewInAIs)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var phaseTitle: String {
        switch event.phase {
        case .spawned: return "Sub-Agent Spawned"
        case .running: return "Sub-Agent Running"
        case .done: return "Sub-Agent Done"
        case .failed: return "Sub-Agent Failed"
        }
    }
}

func formatElapsed(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}
