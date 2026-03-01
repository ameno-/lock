// AgenticKeyboard.swift — UIInputView accessory (no extension entitlements)
import SwiftUI
import UIKit

// MARK: - SwiftUI wrapper

struct AgenticKeyboard: UIViewRepresentable {
    @Binding var text: String
    var onSend: (String) -> Void
    var onAbort: () -> Void
    var snippetCategories: [SnippetCategory]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        // Transparent passthrough view — keyboard is attached as accessory
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject {}
}

// MARK: - Inline keyboard view (used directly in WorkView as overlay)

struct InlineAgenticKeyboard: View {
    @Binding var text: String
    var onSend: (String) -> Void
    var onAbort: () -> Void
    var onSnippetInsert: (String) -> Void
    var onExecuteStack: () -> Void
    var onClearStack: () -> Void
    var snippetStackCount: Int
    var snippetCategories: [SnippetCategory]
    var quickReplyChips: [QuickReplyChip] = []
    var onQuickTextReply: ((String) -> Void)?
    var onQuickGenUIAction: ((GenUIEvent) -> Void)?
    var onQuickApprovalDecision: ((String, ACApprovalDecision) -> Void)?

    @State private var isSnippetMode = false
    @State private var selectedCategory: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if isSnippetMode {
                KeyboardSnippetMode(
                    selectedCategory: $selectedCategory,
                    onInsert: { snippet in
                        onSnippetInsert(snippet)
                    },
                    onDismiss: {
                        withAnimation(.spring(duration: 0.25)) { isSnippetMode = false }
                    },
                    categories: snippetCategories
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                KeyboardInputMode(
                    text: $text,
                    onSend: onSend,
                    onAbort: onAbort,
                    onSnippetToggle: {
                        withAnimation(.spring(duration: 0.25)) { isSnippetMode = true }
                    },
                    snippetStackCount: snippetStackCount,
                    onExecuteStack: onExecuteStack,
                    onClearStack: onClearStack,
                    quickReplyChips: quickReplyChips,
                    onQuickTextReply: onQuickTextReply,
                    onQuickGenUIAction: onQuickGenUIAction,
                    onQuickApprovalDecision: onQuickApprovalDecision
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: isSnippetMode)
    }
}
