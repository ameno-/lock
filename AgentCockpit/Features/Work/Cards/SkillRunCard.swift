// SkillRunCard.swift — Compact skill execution summary
import SwiftUI

struct SkillRunCard: View {
    let event: SkillRunEvent

    private var statusColor: Color {
        switch event.status {
        case .running: return .yellow
        case .done: return .green
        case .failed: return .red
        }
    }

    private var statusLabel: String {
        switch event.status {
        case .running: return "running"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    var body: some View {
        CardBase {
            HStack(spacing: 8) {
                Text("⚡")
                    .font(.subheadline)
                Text(event.skillName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let ms = event.durationMs {
                    Text("\(ms)ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }
            }
        }
    }
}
