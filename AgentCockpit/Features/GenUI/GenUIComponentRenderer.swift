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

        case .timeline(let timeline):
            TimelineComponentView(timeline: timeline)

        case .decision(let decision):
            DecisionComponentView(decision: decision, event: event, onAction: onAction, actionState: actionState)

        case .diffPreview(let diff):
            DiffPreviewComponentView(diff: diff)

        case .riskGate(let gate):
            RiskGateComponentView(gate: gate)

        case .keyValue(let kv):
            KeyValueComponentView(kv: kv)

        case .codeBlock(let block):
            CodeBlockComponentView(block: block)
        }
    }
}

// MARK: - Timeline

private struct TimelineComponentView: View {
    let timeline: GenUITimelineComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = timeline.title, !title.isEmpty {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(timeline.steps) { step in
                HStack(alignment: .top, spacing: 8) {
                    stepIcon(step.state)
                        .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.label)
                            .font(.caption)
                            .foregroundStyle(step.state == .completed ? .secondary : .primary)
                            .strikethrough(step.state == .completed)
                        if let detail = step.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(_ state: GenUITimelineComponent.StepState) -> some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .active:
            Image(systemName: "circle.dotted.circle.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .pending:
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Decision

private struct DecisionComponentView: View {
    let decision: GenUIDecisionComponent
    let event: GenUIEvent
    var onAction: ((GenUIEvent) -> Void)?
    var actionState: ((String, String) -> GenUIActionDispatchState?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(decision.prompt)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)

            ForEach(decision.options) { option in
                let state = actionState?(event.surfaceID, option.id)
                let isSending = state?.status == .sending
                Button {
                    var payload = event.actionPayload
                    for (key, value) in option.payload {
                        payload[key] = value
                    }
                    payload["actionId"] = AnyCodable(option.id)
                    payload["label"] = AnyCodable(option.label)
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
                            actionLabel: option.label,
                            actionPayload: payload,
                            timestamp: .now
                        )
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: stateIcon(state))
                                .foregroundStyle(stateColor(state))
                            Text(option.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        if let desc = option.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(stateColor(state).opacity(0.3), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSending)
            }
        }
    }

    private func stateIcon(_ state: GenUIActionDispatchState?) -> String {
        switch state?.status {
        case .sending: "hourglass.circle.fill"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "circle"
        }
    }

    private func stateColor(_ state: GenUIActionDispatchState?) -> Color {
        switch state?.status {
        case .sending: .orange
        case .succeeded: .green
        case .failed: .red
        default: .blue
        }
    }
}

// MARK: - Diff Preview

private struct DiffPreviewComponentView: View {
    let diff: GenUIDiffPreviewComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let path = diff.filePath {
                    Text(path.split(separator: "/").last.map(String.init) ?? path)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if diff.additions > 0 {
                    Text("+\(diff.additions)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
                if diff.deletions > 0 {
                    Text("-\(diff.deletions)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
            DiffPreview(diff: diff.diff, maxLines: 8)
        }
    }
}

// MARK: - Risk Gate

private struct RiskGateComponentView: View {
    let gate: GenUIRiskGateComponent

    var body: some View {
        HStack(spacing: 10) {
            riskBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(gate.summary)
                    .font(.caption.weight(.medium))
                if let detail = gate.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(riskColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(riskColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var riskBadge: some View {
        Text(gate.level.rawValue.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(riskColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var riskColor: Color {
        switch gate.level {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}

// MARK: - Key Value

private struct KeyValueComponentView: View {
    let kv: GenUIKeyValueComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = kv.title, !title.isEmpty {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(kv.pairs) { pair in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(pair.key)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 60, alignment: .trailing)
                    Text(pair.value)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(8)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Code Block

private struct CodeBlockComponentView: View {
    let block: GenUICodeBlockComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let lang = block.language, !lang.isEmpty {
                Text(lang)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.code)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
