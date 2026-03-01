import SwiftUI

struct QuickReplyChip: Identifiable, Sendable {
    enum Kind: Sendable {
        case text(String)
        case genUIAction(GenUIEvent)
        case approvalDecision(requestID: String, decision: ACApprovalDecision)
    }

    let id: String
    let label: String
    let icon: String?
    let tint: Color
    let kind: Kind
}

struct QuickReplyStrip: View {
    let chips: [QuickReplyChip]
    var onTextReply: ((String) -> Void)?
    var onGenUIAction: ((GenUIEvent) -> Void)?
    var onApprovalDecision: ((String, ACApprovalDecision) -> Void)?

    var body: some View {
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        Button {
                            handleTap(chip)
                        } label: {
                            HStack(spacing: 4) {
                                if let icon = chip.icon {
                                    Image(systemName: icon)
                                        .font(.caption2)
                                }
                                Text(chip.label)
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(chip.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(chip.tint.opacity(0.1), in: Capsule())
                            .overlay(Capsule().stroke(chip.tint.opacity(0.2), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private func handleTap(_ chip: QuickReplyChip) {
        switch chip.kind {
        case .text(let text):
            onTextReply?(text)
        case .genUIAction(let event):
            onGenUIAction?(event)
        case .approvalDecision(let requestID, let decision):
            onApprovalDecision?(requestID, decision)
        }
    }
}
