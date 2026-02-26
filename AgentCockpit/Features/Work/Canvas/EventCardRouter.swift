// EventCardRouter.swift — Switch on CanvasEvent, emit the right card
import SwiftUI

struct EventCardRouter: View {
    let event: CanvasEvent
    var onViewInAIs: (() -> Void)? = nil

    var body: some View {
        switch event {
        case .toolUse(let e):
            ToolUseCard(event: e)

        case .reasoning(let e):
            ReasoningCard(event: e)

        case .gitDiff(let e):
            GitDiffCard(event: e)

        case .subAgent(let e):
            SubAgentCard(event: e, onViewInAIs: onViewInAIs)

        case .skillRun(let e):
            SkillRunCard(event: e)

        case .fileEdit(let e):
            FileEditCard(event: e)

        case .genUI(let e):
            GenUICard(event: e)

        case .rawOutput(let e):
            RawOutputCard(event: e)
        }
    }
}

private struct GenUICard: View {
    let event: GenUIEvent

    var body: some View {
        CardBase {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(icon: "🧩", title: event.title)

                if !event.body.isEmpty {
                    Text(event.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let actionLabel = event.actionLabel, !actionLabel.isEmpty {
                    Label(actionLabel, systemImage: "bolt.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}
