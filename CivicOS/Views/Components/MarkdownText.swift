import SwiftUI

/// Lightweight block-level markdown renderer for chat bubbles. Handles
/// headings, paragraphs, ordered + unordered lists, blockquotes, code fences,
/// horizontal rules, and inline formatting (bold, italic, links, inline
/// code) via SwiftUI's AttributedString markdown parser. No third-party deps.
///
/// Renders a streaming-cursor (▍) glued to the last visible block so the
/// chat's typing affordance still works without breaking formatting.
struct MarkdownText: View {
    let raw: String
    /// Append a blinking cursor to the last block to indicate streaming.
    let isStreaming: Bool
    /// Color for body text — bold/italic inherit it. Links get the accent.
    var textColor: Color = CivicTheme.ink
    var accent: Color = CivicTheme.cyan

    var body: some View {
        let blocks = MarkdownText.parse(raw)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, isLast: index == blocks.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, isLast: Bool) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text) + cursorIfNeeded(isLast))
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(textColor)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        case let .paragraph(text):
            Text(inline(text) + cursorIfNeeded(isLast))
                .font(.system(size: 15))
                .foregroundStyle(textColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    let isLastBullet = isLast && idx == items.count - 1
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(textColor.opacity(0.6))
                        Text(inline(item) + cursorIfNeeded(isLastBullet))
                            .font(.system(size: 15))
                            .foregroundStyle(textColor)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case let .orderedList(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    let isLastItem = isLast && idx == items.count - 1
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(textColor.opacity(0.65))
                            .monospacedDigit()
                        Text(inline(item) + cursorIfNeeded(isLastItem))
                            .font(.system(size: 15))
                            .foregroundStyle(textColor)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case let .blockquote(text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(accent.opacity(0.45))
                    .frame(width: 3)
                Text(inline(text) + cursorIfNeeded(isLast))
                    .font(.system(size: 14, design: .serif))
                    .italic()
                    .foregroundStyle(textColor.opacity(0.88))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .codeBlock(_, code):
            Text((isLast && isStreaming) ? code + " ▍" : code)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(textColor)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(textColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(textColor.opacity(0.10), lineWidth: 1))
                .textSelection(.enabled)
        case .horizontalRule:
            Rectangle()
                .fill(textColor.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 19
        case 3: return 17
        default: return 16
        }
    }

    private func cursorIfNeeded(_ isLast: Bool) -> AttributedString {
        guard isLast && isStreaming else { return AttributedString("") }
        return AttributedString(" ▍")
    }

    /// Parse inline markdown (bold, italic, code, links) via AttributedString.
    /// Falls back to plain text if the parser chokes on something exotic.
    private func inline(_ text: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: false,
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            var styled = attr
            // Color any links with the accent.
            for run in styled.runs where run.link != nil {
                styled[run.range].foregroundColor = accent
                styled[run.range].underlineStyle = .single
            }
            return styled
        }
        return AttributedString(text)
    }
}

// MARK: - Parser

enum MarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case blockquote(String)
    case codeBlock(language: String?, code: String)
    case horizontalRule
}

extension MarkdownText {
    /// Splits the raw string into block-level pieces. Tolerant of partial
    /// input mid-stream (an unclosed code fence still renders its body).
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var i = 0
        var paragraphBuffer: [String] = []
        var unorderedBuffer: [String] = []
        var orderedBuffer: [String] = []
        var blockquoteBuffer: [String] = []

        func flushParagraph() {
            if !paragraphBuffer.isEmpty {
                let text = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { blocks.append(.paragraph(text)) }
                paragraphBuffer.removeAll()
            }
        }
        func flushUnordered() {
            if !unorderedBuffer.isEmpty {
                blocks.append(.unorderedList(unorderedBuffer))
                unorderedBuffer.removeAll()
            }
        }
        func flushOrdered() {
            if !orderedBuffer.isEmpty {
                blocks.append(.orderedList(orderedBuffer))
                orderedBuffer.removeAll()
            }
        }
        func flushBlockquote() {
            if !blockquoteBuffer.isEmpty {
                blocks.append(.blockquote(blockquoteBuffer.joined(separator: " ")))
                blockquoteBuffer.removeAll()
            }
        }
        func flushAll() {
            flushParagraph()
            flushUnordered()
            flushOrdered()
            flushBlockquote()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line → close any open paragraph/list/quote.
            if trimmed.isEmpty {
                flushAll()
                i += 1
                continue
            }

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                flushAll()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let codeLine = lines[i]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(codeLine)
                    i += 1
                }
                blocks.append(.codeBlock(language: language.isEmpty ? nil : language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Horizontal rule.
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushAll()
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Heading.
            if let headingMatch = parseHeading(trimmed) {
                flushAll()
                blocks.append(.heading(level: headingMatch.0, text: headingMatch.1))
                i += 1
                continue
            }

            // Unordered list item.
            if let item = parseUnorderedItem(trimmed) {
                flushParagraph()
                flushOrdered()
                flushBlockquote()
                unorderedBuffer.append(item)
                i += 1
                continue
            }

            // Ordered list item.
            if let item = parseOrderedItem(trimmed) {
                flushParagraph()
                flushUnordered()
                flushBlockquote()
                orderedBuffer.append(item)
                i += 1
                continue
            }

            // Blockquote.
            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushUnordered()
                flushOrdered()
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blockquoteBuffer.append(body)
                i += 1
                continue
            }

            // Plain paragraph line. Closing other block types so we don't
            // concatenate a list item into a following paragraph.
            flushUnordered()
            flushOrdered()
            flushBlockquote()
            paragraphBuffer.append(trimmed)
            i += 1
        }
        flushAll()
        return blocks
    }

    private static func parseHeading(_ s: String) -> (Int, String)? {
        guard s.hasPrefix("#") else { return nil }
        var level = 0
        var index = s.startIndex
        while index < s.endIndex && s[index] == "#" && level < 6 {
            level += 1
            index = s.index(after: index)
        }
        guard level >= 1, index < s.endIndex, s[index] == " " else { return nil }
        let body = String(s[s.index(after: index)...]).trimmingCharacters(in: .whitespaces)
        return (level, body)
    }

    private static func parseUnorderedItem(_ s: String) -> String? {
        let prefixes = ["- ", "* ", "+ "]
        for prefix in prefixes where s.hasPrefix(prefix) {
            return String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseOrderedItem(_ s: String) -> String? {
        // Match "1. ", "12) ", etc.
        let scanner = Scanner(string: s)
        scanner.charactersToBeSkipped = nil
        var number = 0
        guard scanner.scanInt(&number), number >= 0 else { return nil }
        guard let delim = scanner.scanCharacters(from: CharacterSet(charactersIn: ".)")), !delim.isEmpty else { return nil }
        guard scanner.scanCharacter() == " " else { return nil }
        let rest = String(s[s.index(s.startIndex, offsetBy: scanner.currentIndex.utf16Offset(in: s))...])
        return rest.trimmingCharacters(in: .whitespaces)
    }
}
