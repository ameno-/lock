// GitDiffCard.swift — Pure Swift unified diff renderer with +/- colored lines
import SwiftUI

struct GitDiffCard: View {
    let event: GitDiffEvent
    @State private var showFullDiff = false

    private let maxInlineLines = 5

    var body: some View {
        CardBase {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(
                    icon: "🔀",
                    title: "Git Diff" + (event.filePath.map { " · \($0.split(separator: "/").last.map(String.init) ?? $0)" } ?? "")
                ) {
                    HStack(spacing: 6) {
                        if event.additions > 0 {
                            Text("+\(event.additions)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.green)
                        }
                        if event.deletions > 0 {
                            Text("-\(event.deletions)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.red)
                        }
                    }
                }

                if !event.rawDiff.isEmpty {
                    DiffPreview(diff: event.rawDiff, maxLines: maxInlineLines)

                    if event.rawDiff.split(separator: "\n").count > maxInlineLines {
                        Button {
                            showFullDiff = true
                        } label: {
                            Text("Show full diff →")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                } else {
                    Text("No diff content")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showFullDiff) {
            FullDiffSheet(event: event)
        }
    }
}

// MARK: - Diff preview (inline, up to N lines)

struct DiffPreview: View {
    let diff: String
    let maxLines: Int

    private var lines: [DiffLine] { parseDiff(diff, limit: maxLines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                Text(line.display)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(line.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(line.bgColor.opacity(0.15))
            }
        }
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Full diff sheet

private struct FullDiffSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: GitDiffEvent

    var body: some View {
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(parseDiff(event.rawDiff, limit: .max)) { line in
                        Text(line.display)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .background(line.bgColor.opacity(0.12))
                    }
                }
                .padding()
            }
            .navigationTitle(event.filePath ?? "Git Diff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Diff line model + parser (~100 lines)

struct DiffLine: Identifiable {
    let id = UUID()
    let display: String
    let kind: DiffLineKind

    var textColor: Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .header: return .blue
        case .hunk: return .cyan
        case .context: return .primary.opacity(0.7)
        }
    }

    var bgColor: Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .header, .hunk: return .blue
        case .context: return .clear
        }
    }
}

enum DiffLineKind {
    case addition, deletion, header, hunk, context
}

private func parseDiff(_ diff: String, limit: Int) -> [DiffLine] {
    var result: [DiffLine] = []
    for rawLine in diff.split(separator: "\n", omittingEmptySubsequences: false) {
        if result.count >= limit { break }
        let line = String(rawLine)
        let kind: DiffLineKind
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
            kind = .header
        } else if line.hasPrefix("@@") {
            kind = .hunk
        } else if line.hasPrefix("+") {
            kind = .addition
        } else if line.hasPrefix("-") {
            kind = .deletion
        } else {
            kind = .context
        }
        result.append(DiffLine(display: line, kind: kind))
    }
    return result
}
