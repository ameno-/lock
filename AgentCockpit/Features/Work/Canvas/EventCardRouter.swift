// EventCardRouter.swift — Switch on CanvasEvent, emit the right card
import SwiftUI

struct EventCardRouter: View {
    let event: CanvasEvent
    var onViewInAIs: (() -> Void)? = nil

    var body: some View {
        switch event {
        case .toolUse(let e):
            ToolUseCard(event: e)

        case .reasoning(let e):
            ReasoningCard(event: e)

        case .gitDiff(let e):
            GitDiffCard(event: e)

        case .subAgent(let e):
            SubAgentCard(event: e, onViewInAIs: onViewInAIs)

        case .skillRun(let e):
            SkillRunCard(event: e)

        case .fileEdit(let e):
            FileEditCard(event: e)

        case .rawOutput(let e):
            RawOutputCard(event: e)
        }
    }
}
