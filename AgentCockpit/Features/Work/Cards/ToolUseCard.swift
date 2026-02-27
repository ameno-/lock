import SwiftUI

struct ToolUseCard: View {
    let event: ToolUseEvent
    @State private var showingDetail = false

    var body: some View {
        CardBase {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(ToolDisplay.emoji(for: event.toolName))  \(event.toolName)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    StatusBadge(status: badgeStatus)
                }

                if !event.input.isEmpty {
                    Text(event.input)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let result = event.result, !result.isEmpty {
                    Divider()
                    Text(result)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .onTapGesture { if event.result != nil { showingDetail = true } }
        .sheet(isPresented: $showingDetail) {
            ToolDetailSheet(event: event)
        }
    }

    private var badgeStatus: StatusBadge.Status {
        switch event.status {
        case .running: return .running
        case .done: return .done
        case .error: return .error
        }
    }
}

private struct ToolDetailSheet: View {
    let event: ToolUseEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Input")
                        .font(.caption.weight(.semibold))
                    Text(event.input.isEmpty ? "<none>" : event.input)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let result = event.result {
                        Text("Result")
                            .font(.caption.weight(.semibold))
                        Text(result)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("\(ToolDisplay.emoji(for: event.toolName)) \(event.toolName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
