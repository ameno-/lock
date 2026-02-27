import SwiftUI

struct ReasoningCard: View {
    let event: ReasoningEvent
    @State private var isExpanded = false

    var body: some View {
        CardBase {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
                } label: {
                    HStack {
                        Text(event.isThinking ? "💭  Thinking" : "💬  Assistant")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(event.isThinking ? .purple : .primary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text(event.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text(event.text)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill((event.isThinking ? Color.purple : Color.blue).opacity(0.5))
                .frame(width: 3)
                .padding(.vertical, 8)
                .padding(.leading, 2)
        }
    }
}
