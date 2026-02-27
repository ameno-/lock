// EventCardRouter.swift — Switch on CanvasEvent, emit the right card
import SwiftUI

struct EventCardRouter: View {
    let event: CanvasEvent
    var onViewInAIs: (() -> Void)? = nil
    var onGenUIAction: ((GenUIEvent) -> Void)? = nil
    var genUIActionState: ((String, String) -> GenUIActionDispatchState?)? = nil

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
            GenUICard(event: e, onAction: onGenUIAction, actionState: genUIActionState)

        case .rawOutput(let e):
            RawOutputCard(event: e)
        }
    }
}

struct GenUICard: View {
    let event: GenUIEvent
    var onAction: ((GenUIEvent) -> Void)? = nil
    var actionState: ((String, String) -> GenUIActionDispatchState?)? = nil

    private var primaryActionID: String? {
        event.actionPayload["actionId"]?.stringValue
            ?? event.actionPayload["action_id"]?.stringValue
            ?? event.actionLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
    }

    var body: some View {
        CardBase {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(icon: "🧩", title: event.title)

                GenUIComponentRenderer(
                    event: event,
                    onAction: onAction,
                    actionState: actionState
                )

                Text("\(event.schemaVersion) • \(event.mode == .patch ? "patch" : "snapshot") • rev \(event.revision)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)

                if let actionLabel = event.actionLabel, !actionLabel.isEmpty {
                    let state = primaryActionID.flatMap { actionID in
                        actionState?(event.surfaceID, actionID)
                    }
                    let isSending = state?.status == .sending
                    Button {
                        onAction?(event)
                    } label: {
                        Label(actionLabel, systemImage: stateIcon(for: state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(stateColor(for: state))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(stateColor(for: state).opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                }
            }
        }
    }

    private func stateIcon(for state: GenUIActionDispatchState?) -> String {
        switch state?.status {
        case .sending:
            "hourglass.circle.fill"
        case .succeeded:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        default:
            "bolt.circle.fill"
        }
    }

    private func stateColor(for state: GenUIActionDispatchState?) -> Color {
        switch state?.status {
        case .sending:
            .orange
        case .succeeded:
            .green
        case .failed:
            .red
        default:
            .blue
        }
    }
}
