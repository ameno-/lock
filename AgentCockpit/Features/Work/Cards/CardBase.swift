import SwiftUI

/// Shared visual style for all event cards.
struct CardBase<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - Status badge

struct StatusBadge: View {
    enum Status { case running, done, error }
    let status: Status

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .running: .yellow
        case .done:    .green
        case .error:   .red
        }
    }

    private var label: String {
        switch status {
        case .running: "running"
        case .done:    "done"
        case .error:   "error"
        }
    }
}

// MARK: - Shared header row

struct CardHeader<Trailing: View>: View {
    let icon: String
    let title: String
    let trailing: Trailing

    init(icon: String, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer()
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(icon: String, title: String) {
        self.init(icon: icon, title: title) { EmptyView() }
    }
}

// MARK: - Tool emoji helper (loaded from JSON at runtime)

enum ToolDisplay {
    static func emoji(for toolName: String) -> String {
        switch toolName.lowercased() {
        case "bash":     "💻"
        case "read":     "📖"
        case "write":    "✍️"
        case "edit":     "✏️"
        case "glob":     "🔍"
        case "grep":     "🔎"
        case "task":     "🤖"
        case "webfetch": "🌐"
        case "websearch":"🔍"
        default:         "🛠️"
        }
    }
}
