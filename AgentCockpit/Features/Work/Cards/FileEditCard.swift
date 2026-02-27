// FileEditCard.swift — Compact single-line file operation summary
import SwiftUI

struct FileEditCard: View {
    let event: FileEditEvent

    private var fileName: String {
        event.filePath.split(separator: "/").last.map(String.init) ?? event.filePath
    }

    private var emoji: String {
        switch event.operation {
        case .read: return "📖"
        case .write: return "✍️"
        case .edit: return "✏️"
        case .delete: return "🗑️"
        }
    }

    private var label: String {
        switch event.operation {
        case .read: return "Read"
        case .write: return "Wrote"
        case .edit: return "Edited"
        case .delete: return "Deleted"
        }
    }

    var body: some View {
        CardBase {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.subheadline)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(fileName)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(event.filePath.split(separator: "/").dropLast().suffix(2).joined(separator: "/"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}
