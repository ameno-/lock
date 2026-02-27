// AssistantTextParser.swift — <think>/<thinking> block parser
import Foundation

public enum AssistantTextParser {

    /// Split content into thinking text and regular text.
    /// Returns (thinkingContent, remainingText).
    public static func split(_ content: String) -> (thinking: String?, text: String) {
        // Try <think> ... </think>
        if let result = extractBlock(content, open: "<think>", close: "</think>") {
            return result
        }
        // Try <thinking> ... </thinking>
        if let result = extractBlock(content, open: "<thinking>", close: "</thinking>") {
            return result
        }
        return (nil, content)
    }

    private static func extractBlock(
        _ content: String,
        open: String,
        close: String
    ) -> (thinking: String?, text: String)? {
        guard let openRange = content.range(of: open),
              let closeRange = content.range(of: close, range: openRange.upperBound..<content.endIndex)
        else { return nil }

        let thinking = String(content[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let before = String(content[..<openRange.lowerBound])
        let after = String(content[closeRange.upperBound...])
        let remaining = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)

        return (thinking.isEmpty ? nil : thinking, remaining)
    }
}
