import SwiftUI

struct GenUIComponentRenderer: View {
    let event: GenUIEvent
    var onAction: ((GenUIEvent) -> Void)? = nil
    var actionState: ((String, String) -> GenUIActionDispatchState?)? = nil

    @Environment(\.genUIRenderingEngine) private var renderingEngine

    private var components: [GenUIRenderComponent] {
        renderingEngine.components(for: event)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if components.isEmpty {
                if !event.body.isEmpty {
                    Text(event.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(components) { component in
                    componentView(component)
                }
            }
        }
    }

    @ViewBuilder
    private func componentView(_ component: GenUIRenderComponent) -> some View {
        switch component {
        case .text(let text):
            Text(text.value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .metric(let metric):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(metric.value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Spacer(minLength: 0)
                if let trend = metric.trend, !trend.isEmpty {
                    Text(trend)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Color(.tertiarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

        case .progress(let progress):
            VStack(alignment: .leading, spacing: 6) {
                if let label = progress.label, !label.isEmpty {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress.value, total: 1.0)
                    .tint(.blue)
                Text("\(Int(progress.value * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

        case .checklist(let checklist):
            VStack(alignment: .leading, spacing: 6) {
                if let title = checklist.title, !title.isEmpty {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(checklist.items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? .green : .secondary)
                        Text(item.label)
                            .font(.caption)
                            .foregroundStyle(item.done ? .secondary : .primary)
                            .strikethrough(item.done)
                    }
                }
            }

        case .actions(let actions):
            if !actions.items.isEmpty {
                FlowActionRow(
                    items: actions.items,
                    onTap: { action in
                        var payload = event.actionPayload
                        for (key, value) in action.payload {
                            payload[key] = value
                        }
                        payload["actionId"] = AnyCodable(action.id)
                        if payload["label"] == nil {
                            payload["label"] = AnyCodable(action.label)
                        }

                        onAction?(
                            GenUIEvent(
                                id: event.id,
                                schemaVersion: event.schemaVersion,
                                mode: event.mode,
                                surfaceID: event.surfaceID,
                                revision: event.revision,
                                correlationID: event.correlationID,
                                title: event.title,
                                body: event.body,
                                surfacePayload: event.surfacePayload,
                                contextPayload: event.contextPayload,
                                actionLabel: action.label,
                                actionPayload: payload,
                                timestamp: .now
                            )
                        )
                    },
                    stateForActionID: { actionID in
                        actionState?(event.surfaceID, actionID)
                    }
                )
            }
        }
    }
}

private struct FlowActionRow: View {
    let items: [GenUIActionDescriptor]
    let onTap: (GenUIActionDescriptor) -> Void
    var stateForActionID: ((String) -> GenUIActionDispatchState?)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { action in
                    let state = stateForActionID?(action.id)
                    let isSending = state?.status == .sending
                    Button {
                        onTap(action)
                    } label: {
                        Label(action.label, systemImage: icon(for: state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color(for: state))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(color(for: state).opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                }
            }
        }
    }

    private func icon(for state: GenUIActionDispatchState?) -> String {
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

    private func color(for state: GenUIActionDispatchState?) -> Color {
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
