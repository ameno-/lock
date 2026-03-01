import SwiftUI

struct SurfaceDockView: View {
    let surfaces: [GenUIEvent]
    var onGenUIAction: ((GenUIEvent) -> Void)?
    var genUIActionState: ((String, String) -> GenUIActionDispatchState?)?

    @State private var isExpanded = true

    var body: some View {
        if !surfaces.isEmpty {
            VStack(spacing: 0) {
                dockHeader
                if isExpanded {
                    dockContent
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Divider().opacity(0.3)
            }
            .background(.ultraThinMaterial)
            .animation(.spring(duration: 0.3), value: isExpanded)
            .animation(.spring(duration: 0.3), value: surfaces.map(\.surfaceID))
        }
    }

    private var dockHeader: some View {
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("Surfaces")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(surfaces.count)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.blue.opacity(0.12), in: Capsule())
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var dockContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(surfaces, id: \.surfaceID) { surface in
                    SurfaceDockCard(
                        event: surface,
                        onAction: onGenUIAction,
                        actionState: genUIActionState
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }
}

private struct SurfaceDockCard: View {
    let event: GenUIEvent
    var onAction: ((GenUIEvent) -> Void)?
    var actionState: ((String, String) -> GenUIActionDispatchState?)?

    @State private var isDetailExpanded = false
    @Environment(\.genUIRenderingEngine) private var renderingEngine

    private var components: [GenUIRenderComponent] {
        renderingEngine.components(for: event)
    }

    private var isDecisionSurface: Bool {
        event.surfaceID.contains("decision") || event.surfaceID.contains("approval")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                surfaceIcon
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isDecisionSurface {
                    attentionBadge
                }
            }

            if isDetailExpanded {
                GenUIComponentRenderer(
                    event: event,
                    onAction: onAction,
                    actionState: actionState
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                compactPreview
            }
        }
        .padding(12)
        .frame(width: isDetailExpanded ? 300 : 220, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(duration: 0.25)) { isDetailExpanded.toggle() }
        }
    }

    @ViewBuilder
    private var compactPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(components.prefix(2)) { component in
                compactComponentRow(component)
            }
            if components.count > 2 {
                Text("+\(components.count - 2) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func compactComponentRow(_ component: GenUIRenderComponent) -> some View {
        switch component {
        case .progress(let p):
            HStack(spacing: 6) {
                ProgressView(value: p.value, total: 1.0)
                    .tint(.blue)
                    .frame(maxWidth: 80)
                Text("\(Int(p.value * 100))%")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .metric(let m):
            HStack(spacing: 4) {
                Text(m.label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(m.value)
                    .font(.caption2.weight(.semibold).monospacedDigit())
            }
        case .checklist(let c):
            let done = c.items.filter(\.done).count
            HStack(spacing: 4) {
                Text("\(done)/\(c.items.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(done == c.items.count ? .green : .secondary)
                Text(c.title ?? "Checklist")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        case .text(let t):
            Text(t.value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .timeline(let t):
            let active = t.steps.filter { $0.state == .active || $0.state == .completed }.count
            HStack(spacing: 4) {
                Text("\(active)/\(t.steps.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(active == t.steps.count ? .green : .blue)
                Text(t.title ?? "Steps")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        case .riskGate(let gate):
            HStack(spacing: 4) {
                Text(gate.level.rawValue.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(riskColor(gate.level), in: Capsule())
                Text(gate.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .decision(let d):
            Text(d.prompt)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .keyValue(let kv):
            if let first = kv.pairs.first {
                HStack(spacing: 4) {
                    Text(first.key)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(first.value)
                        .font(.caption2.weight(.semibold))
                }
            }
        case .actions(let actions):
            HStack(spacing: 4) {
                if actions.items.isEmpty {
                    Text("No actions")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Label("\(actions.items.count)", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text("actions")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .diffPreview(let diff):
            HStack(spacing: 4) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                if diff.additions > 0 {
                    Text("+\(diff.additions)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if diff.deletions > 0 {
                    Text("-\(diff.deletions)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if let path = diff.filePath {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

        case .codeBlock(let code):
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text(code.language ?? "code")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var surfaceIcon: some View {
        Group {
            if event.surfaceID.hasPrefix("session.plan") {
                Image(systemName: "list.bullet.clipboard")
            } else if event.surfaceID.hasPrefix("session.progress") {
                Image(systemName: "chart.bar.fill")
            } else if event.surfaceID.hasPrefix("session.decision") || event.surfaceID.hasPrefix("session.approval") {
                Image(systemName: "exclamationmark.triangle.fill")
            } else if event.surfaceID.hasPrefix("session.result") {
                Image(systemName: "checkmark.seal.fill")
            } else if event.surfaceID.hasPrefix("session.reorientation") {
                Image(systemName: "arrow.counterclockwise.circle.fill")
            } else {
                Image(systemName: "square.stack.3d.up.fill")
            }
        }
        .font(.caption2)
        .foregroundStyle(isDecisionSurface ? .orange : .blue)
    }

    private var attentionBadge: some View {
        Text("ACTION")
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.orange, in: Capsule())
    }

    private func riskColor(_ level: GenUIRiskGateComponent.RiskLevel) -> Color {
        switch level {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }

    private var cardBackground: some ShapeStyle {
        isDecisionSurface
            ? AnyShapeStyle(Color.orange.opacity(0.06))
            : AnyShapeStyle(Color(.secondarySystemBackground))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(
                isDecisionSurface ? Color.orange.opacity(0.3) : Color(.systemGray5),
                lineWidth: isDecisionSurface ? 1 : 0.5
            )
    }
}
