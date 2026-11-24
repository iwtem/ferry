import Foundation

// MARK: - Markdown AST

public enum MarkdownTableAlignment: String, Equatable, Sendable {
    case left
    case center
    case right
}

public struct MarkdownBulletItem: Equatable, Sendable {
    public let indentLevel: Int
    /// `nil` for regular bullet items; `false`/`true` for `- [ ]` / `- [x]` task items.
    public let checked: Bool?
    public let text: String

    public init(indentLevel: Int, checked: Bool? = nil, text: String) {
        self.indentLevel = indentLevel
        self.checked = checked
        self.text = text
    }
}

public struct MarkdownOrderedItem: Equatable, Sendable {
    public let indentLevel: Int
    public let number: Int
    public let text: String

    public init(indentLevel: Int, number: Int, text: String) {
        self.indentLevel = indentLevel
        self.number = number
        self.text = text
    }
}

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [MarkdownBulletItem])
    case orderedList(items: [MarkdownOrderedItem])
    case blockquote(lines: [String])
    case codeBlock(language: String?, code: String)
    case table(headers: [String], alignments: [MarkdownTableAlignment], rows: [[String]])
    case thematicBreak
}

public indirect enum MarkdownInline: Equatable, Sendable {
    case text(String)
    case bold([MarkdownInline])
    case italic([MarkdownInline])
    case boldItalic([MarkdownInline])
    case strikethrough([MarkdownInline])
    case code(String)
    case link(label: [MarkdownInline], url: String)
}

// MARK: - Markdown Document Parser, Detector & Serializers

public enum MarkdownDocument {
    // MARK: - Block Parsing

    public static func parse(_ input: String) -> [MarkdownBlock] {
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            // 1. Fenced code block (``` or ~~~)
            if let fence = parseFenceOpener(trimmed) {
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if isFenceCloser(candidate, marker: fence.marker, minCount: fence.count) {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.codeBlock(language: fence.language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // 2. ATX Heading (# .. ######)
            if let heading = parseHeading(trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            // 3. Thematic break (---, ***, ___)
            if isThematicBreak(trimmed) {
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            // 4. GFM Pipe Table (header row + separator row)
            if index + 1 < lines.count,
               let alignments = parseTableSeparator(lines[index + 1]),
               let headerCells = parseTableRow(line),
               !headerCells.isEmpty {
                let colCount = max(headerCells.count, alignments.count)
                let paddedHeaders = padRow(headerCells, to: colCount)
                let paddedAlignments = padAlignments(alignments, to: colCount)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let rowLine = lines[index]
                    let rowTrimmed = rowLine.trimmingCharacters(in: .whitespaces)
                    if rowTrimmed.isEmpty || !rowTrimmed.contains("|") {
                        break
                    }
                    if let cells = parseTableRow(rowLine), !cells.isEmpty {
                        rows.append(padRow(cells, to: colCount))
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.table(headers: paddedHeaders, alignments: paddedAlignments, rows: rows))
                continue
            }

            // 5. Blockquote (>)
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let qTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard qTrimmed.hasPrefix(">") else { break }
                    var content = String(qTrimmed.dropFirst())
                    if content.hasPrefix(" ") {
                        content.removeFirst()
                    }
                    quoteLines.append(content)
                    index += 1
                }
                blocks.append(.blockquote(lines: quoteLines))
                continue
            }

            // 6. Bullet / Task List
            if let firstBullet = parseBulletItem(line) {
                var items = [firstBullet]
                index += 1
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                        break
                    }
                    if let nextItem = parseBulletItem(candidate) {
                        items.append(nextItem)
                        index += 1
                    } else if isIndentedContinuation(candidate), !items.isEmpty {
                        let last = items.removeLast()
                        let appended = last.text + "\n" + candidate.trimmingCharacters(in: .whitespaces)
                        items.append(MarkdownBulletItem(indentLevel: last.indentLevel, checked: last.checked, text: appended))
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // 7. Ordered List
            if let firstOrdered = parseOrderedItem(line) {
                var items = [firstOrdered]
                index += 1
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                        break
                    }
                    if let nextItem = parseOrderedItem(candidate) {
                        items.append(nextItem)
                        index += 1
                    } else if isIndentedContinuation(candidate), !items.isEmpty {
                        let last = items.removeLast()
                        let appended = last.text + "\n" + candidate.trimmingCharacters(in: .whitespaces)
                        items.append(MarkdownOrderedItem(indentLevel: last.indentLevel, number: last.number, text: appended))
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // 8. Paragraph (collect until blank line or next block opener)
            var paragraphLines: [String] = [line]
            index += 1
            while index < lines.count {
                let nextLine = lines[index]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty { break }
                if startsBlock(lines: lines, at: index) { break }
                paragraphLines.append(nextLine)
                index += 1
            }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: "\n")))
        }

        return blocks
    }

    // MARK: - Inline Parsing

    public static func parseInlines(_ input: String) -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        var plainBuffer = ""
        let chars = Array(input)
        let count = chars.count
        var i = 0

        func flushPlain() {
            if !plainBuffer.isEmpty {
                if case .text(let prev) = result.last {
                    result[result.count - 1] = .text(prev + plainBuffer)
                } else {
                    result.append(.text(plainBuffer))
                }
                plainBuffer = ""
            }
        }

        while i < count {
            let ch = chars[i]

            // Backslash escape for ASCII punctuation
            if ch == "\\", i + 1 < count, isEscapablePunctuation(chars[i + 1]) {
                plainBuffer.append(chars[i + 1])
                i += 2
                continue
            }

            // Inline code span (` or ``)
            if ch == "`" {
                var tickCount = 0
                while i + tickCount < count && chars[i + tickCount] == "`" {
                    tickCount += 1
                }
                let contentStart = i + tickCount
                if let closeIndex = findClosingBackticks(in: chars, from: contentStart, count: tickCount) {
                    var codeText = String(chars[contentStart..<closeIndex])
                    // CommonMark: strip one single leading and trailing space if both present and not all spaces
                    if codeText.count >= 2,
                       codeText.hasPrefix(" "),
                       codeText.hasSuffix(" "),
                       codeText.contains(where: { $0 != " " }) {
                        codeText = String(codeText.dropFirst().dropLast())
                    }
                    flushPlain()
                    result.append(.code(codeText))
                    i = closeIndex + tickCount
                    continue
                } else {
                    plainBuffer.append(contentsOf: repeatElement("`", count: tickCount))
                    i += tickCount
                    continue
                }
            }

            // Link: [label](url)
            if ch == "[", let linkMatch = parseLink(in: chars, from: i) {
                flushPlain()
                let labelNodes = parseInlines(linkMatch.label)
                result.append(.link(label: labelNodes, url: linkMatch.url))
                i = linkMatch.nextIndex
                continue
            }

            // Strikethrough: ~~text~~
            if ch == "~", i + 1 < count, chars[i + 1] == "~",
               let close = findClosingDelimiter(in: chars, from: i + 2, delimiter: ["~", "~"], requireWordBoundary: false) {
                let inner = String(chars[(i + 2)..<close])
                if !inner.trimmingCharacters(in: .whitespaces).isEmpty {
                    flushPlain()
                    result.append(.strikethrough(parseInlines(inner)))
                    i = close + 2
                    continue
                }
            }

            // Bold + Italic: ***text*** or ___text___
            if (ch == "*" || ch == "_"),
               i + 2 < count, chars[i + 1] == ch, chars[i + 2] == ch,
               canOpenEmphasis(chars: chars, at: i, marker: ch, length: 3),
               let close = findClosingDelimiter(in: chars, from: i + 3, delimiter: [ch, ch, ch], requireWordBoundary: ch == "_") {
                let inner = String(chars[(i + 3)..<close])
                if !inner.trimmingCharacters(in: .whitespaces).isEmpty {
                    flushPlain()
                    result.append(.boldItalic(parseInlines(inner)))
                    i = close + 3
                    continue
                }
            }

            // Bold: **text** or __text__
            if (ch == "*" || ch == "_"),
               i + 1 < count, chars[i + 1] == ch,
               canOpenEmphasis(chars: chars, at: i, marker: ch, length: 2),
               let close = findClosingDelimiter(in: chars, from: i + 2, delimiter: [ch, ch], requireWordBoundary: ch == "_") {
                let inner = String(chars[(i + 2)..<close])
                if !inner.trimmingCharacters(in: .whitespaces).isEmpty {
                    flushPlain()
                    result.append(.bold(parseInlines(inner)))
                    i = close + 2
                    continue
                }
            }

            // Italic: *text* or _text_
            if (ch == "*" || ch == "_"),
               canOpenEmphasis(chars: chars, at: i, marker: ch, length: 1),
               let close = findClosingDelimiter(in: chars, from: i + 1, delimiter: [ch], requireWordBoundary: ch == "_") {
                let inner = String(chars[(i + 1)..<close])
                if !inner.trimmingCharacters(in: .whitespaces).isEmpty {
                    flushPlain()
                    result.append(.italic(parseInlines(inner)))
                    i = close + 1
                    continue
                }
            }

            plainBuffer.append(ch)
            i += 1
        }

        flushPlain()
        return result
    }

    // MARK: - Structure Detection

    /// Returns true if the text contains genuine Markdown block or inline structure
    /// (headings, lists, tables, blockquotes, code blocks, links, bold/italic/strikethrough/inline code).
    public static func hasStructure(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let blocks = parse(trimmed)
        for block in blocks {
            switch block {
            case .heading, .bulletList, .orderedList, .blockquote, .codeBlock, .table, .thematicBreak:
                return true
            case .paragraph(let text):
                if hasInlineStructure(parseInlines(text)) {
                    return true
                }
            }
        }
        return false
    }

    private static func hasInlineStructure(_ nodes: [MarkdownInline]) -> Bool {
        for node in nodes {
            switch node {
            case .text:
                continue
            case .bold, .italic, .boldItalic, .strikethrough, .code, .link:
                return true
            }
        }
        return false
    }

    // MARK: - Outer Markdown Fence Unwrapper

    /// Strips a stray outer ```` ```markdown ... ``` ```` wrapper that some LLMs emit
    /// when translating Markdown, while leaving legitimate code blocks intact.
    public static func unwrapOuterMarkdownFenceIfNeeded(_ output: String, source: String) -> String {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else { return output }

        // If the source itself started with a fenced code block, never unwrap.
        if trimmedSource.hasPrefix("```") || trimmedSource.hasPrefix("~~~") {
            return trimmedOutput
        }

        let lines = trimmedOutput
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        guard lines.count >= 3 else { return trimmedOutput }

        let first = lines[0].trimmingCharacters(in: .whitespaces).lowercased()
        let last = lines[lines.count - 1].trimmingCharacters(in: .whitespaces)
        guard (first == "```markdown" || first == "```md"), last == "```" else {
            return trimmedOutput
        }

        // Ensure there isn't a balanced closing fence in the middle that would indicate multiple blocks.
        var fenceDepth = 1
        for idx in 1..<(lines.count - 1) {
            let line = lines[idx].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if fenceDepth == 1 && line == "```" {
                    // Closes the outer fence prematurely; do not strip.
                    return trimmedOutput
                }
                if line == "```" {
                    fenceDepth -= 1
                } else {
                    fenceDepth += 1
                }
            }
        }

        return lines[1..<(lines.count - 1)].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML Serialization (for Rich Clipboard Paste)

    /// Renders Markdown to clean semantic HTML suitable for pasting into Notion, Feishu,
    /// Word, Google Docs, Pages, Mail, Slack, and Apple Notes.
    public static func toHTML(_ markdown: String) -> String {
        let blocks = parse(markdown)
        var htmlParts: [String] = []
        htmlParts.reserveCapacity(blocks.count)

        for block in blocks {
            switch block {
            case .heading(let level, let text):
                let clamped = min(max(level, 1), 6)
                let content = inlinesToHTML(parseInlines(text))
                htmlParts.append("<h\(clamped)>\(content)</h\(clamped)>")

            case .paragraph(let text):
                let lines = text.components(separatedBy: "\n")
                let rendered = lines.map { inlinesToHTML(parseInlines($0)) }.joined(separator: "<br>")
                htmlParts.append("<p>\(rendered)</p>")

            case .bulletList(let items):
                htmlParts.append(bulletListToHTML(items))

            case .orderedList(let items):
                htmlParts.append(orderedListToHTML(items))

            case .blockquote(let lines):
                let innerHTML = toHTML(lines.joined(separator: "\n"))
                htmlParts.append(
                    "<blockquote style=\"border-left: 3px solid #cbd5e1; margin: 8px 0; padding: 2px 12px; color: #475569;\">\(innerHTML)</blockquote>"
                )

            case .codeBlock(let language, let code):
                let langAttr: String
                if let language, !language.isEmpty {
                    langAttr = " class=\"language-\(escapeHTMLAttribute(language))\""
                } else {
                    langAttr = ""
                }
                let escaped = escapeHTML(code)
                htmlParts.append(
                    "<pre style=\"background: #f1f5f9; padding: 10px 12px; border-radius: 6px; font-family: Menlo, Monaco, Consolas, monospace; font-size: 13px; white-space: pre-wrap;\"><code\(langAttr)>\(escaped)</code></pre>"
                )

            case .table(let headers, let alignments, let rows):
                htmlParts.append(tableToHTML(headers: headers, alignments: alignments, rows: rows))

            case .thematicBreak:
                htmlParts.append("<hr>")
            }
        }

        let body = htmlParts.joined(separator: "\n")
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>"
    }

    // MARK: - Plain Text Serialization (for Copy Plain Text & TTS Speech)

    /// Strips Markdown markup while keeping readable spacing, lists, tables, and paragraphs.
    public static func toPlainText(_ markdown: String) -> String {
        let blocks = parse(markdown)
        var parts: [String] = []
        parts.reserveCapacity(blocks.count)

        for block in blocks {
            switch block {
            case .heading(_, let text):
                parts.append(inlinesToPlainText(parseInlines(text)))

            case .paragraph(let text):
                let rendered = text
                    .components(separatedBy: "\n")
                    .map { inlinesToPlainText(parseInlines($0)) }
                    .joined(separator: "\n")
                parts.append(rendered)

            case .bulletList(let items):
                let lines = items.map { item -> String in
                    let indent = String(repeating: "  ", count: item.indentLevel)
                    let prefix: String
                    if let checked = item.checked {
                        prefix = checked ? "[x] " : "[ ] "
                    } else {
                        prefix = "• "
                    }
                    let text = item.text
                        .components(separatedBy: "\n")
                        .map { inlinesToPlainText(parseInlines($0)) }
                        .joined(separator: "\n" + indent + "  ")
                    return indent + prefix + text
                }
                parts.append(lines.joined(separator: "\n"))

            case .orderedList(let items):
                let lines = items.map { item -> String in
                    let indent = String(repeating: "  ", count: item.indentLevel)
                    let text = item.text
                        .components(separatedBy: "\n")
                        .map { inlinesToPlainText(parseInlines($0)) }
                        .joined(separator: "\n" + indent + "   ")
                    return "\(indent)\(item.number). \(text)"
                }
                parts.append(lines.joined(separator: "\n"))

            case .blockquote(let lines):
                parts.append(toPlainText(lines.joined(separator: "\n")))

            case .codeBlock(_, let code):
                parts.append(code)

            case .table(let headers, _, let rows):
                var tableLines: [String] = []
                tableLines.append(headers.map { inlinesToPlainText(parseInlines($0)) }.joined(separator: "\t"))
                for row in rows {
                    tableLines.append(row.map { inlinesToPlainText(parseInlines($0)) }.joined(separator: "\t"))
                }
                parts.append(tableLines.joined(separator: "\n"))

            case .thematicBreak:
                parts.append("---")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Block Parsing Helpers

    private static func startsBlock(lines: [String], at index: Int) -> Bool {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if parseFenceOpener(trimmed) != nil { return true }
        if parseHeading(trimmed) != nil { return true }
        if isThematicBreak(trimmed) { return true }
        if trimmed.hasPrefix(">") { return true }
        if parseBulletItem(line) != nil { return true }
        if parseOrderedItem(line) != nil { return true }
        if index + 1 < lines.count,
           parseTableSeparator(lines[index + 1]) != nil,
           parseTableRow(line) != nil {
            return true
        }
        return false
    }

    private static func parseFenceOpener(_ trimmed: String) -> (marker: Character, count: Int, language: String?)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        let info = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        // Backtick info string cannot contain backticks per CommonMark
        if first == "`", info.contains("`") { return nil }
        let language = info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        return (first, count, language?.isEmpty == true ? nil : language)
    }

    private static func isFenceCloser(_ trimmed: String, marker: Character, minCount: Int) -> Bool {
        guard trimmed.first == marker else { return false }
        let count = trimmed.prefix(while: { $0 == marker }).count
        guard count >= minCount else { return false }
        return trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard hashes >= 1 && hashes <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        var text = String(rest).trimmingCharacters(in: .whitespaces)
        // Strip optional closing ATX hashes (`## Title ##`)
        if text.hasSuffix("#") {
            let withoutTrailingHashes = text.reversed().drop(while: { $0 == "#" })
            if withoutTrailingHashes.first == " " || withoutTrailingHashes.first == "\t" {
                text = String(withoutTrailingHashes.reversed()).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !text.isEmpty else { return nil }
        return (hashes, text)
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let stripped = trimmed.filter { $0 != " " && $0 != "\t" }
        guard stripped.count >= 3, let first = stripped.first else { return false }
        guard first == "-" || first == "*" || first == "_" else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func leadingIndentLevel(_ line: String) -> (level: Int, remainder: Substring) {
        var spaces = 0
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if ch == " " {
                spaces += 1
            } else if ch == "\t" {
                spaces += 2
            } else {
                break
            }
            idx = line.index(after: idx)
        }
        return (min(spaces / 2, 6), line[idx...])
    }

    private static func isIndentedContinuation(_ line: String) -> Bool {
        line.hasPrefix("  ") || line.hasPrefix("\t")
    }

    private static func parseBulletItem(_ line: String) -> MarkdownBulletItem? {
        let (level, remainder) = leadingIndentLevel(line)
        guard let first = remainder.first, first == "-" || first == "*" || first == "+" || first == "•" else {
            return nil
        }
        let afterMarker = remainder.dropFirst()
        guard afterMarker.first == " " || afterMarker.first == "\t" else { return nil }
        let trimmedBody = String(afterMarker).trimmingCharacters(in: .whitespaces)
        guard !trimmedBody.isEmpty else { return nil }

        // Task list checkbox: `[ ] ` or `[x] ` / `[X] `
        if trimmedBody.hasPrefix("[ ] ") {
            return MarkdownBulletItem(indentLevel: level, checked: false, text: String(trimmedBody.dropFirst(4)))
        }
        if trimmedBody.hasPrefix("[x] ") || trimmedBody.hasPrefix("[X] ") {
            return MarkdownBulletItem(indentLevel: level, checked: true, text: String(trimmedBody.dropFirst(4)))
        }
        return MarkdownBulletItem(indentLevel: level, checked: nil, text: trimmedBody)
    }

    private static func parseOrderedItem(_ line: String) -> MarkdownOrderedItem? {
        let (level, remainder) = leadingIndentLevel(line)
        let digits = remainder.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 6, let number = Int(digits) else { return nil }
        let afterDigits = remainder.dropFirst(digits.count)
        guard let delim = afterDigits.first, delim == "." || delim == ")" else { return nil }
        let afterDelim = afterDigits.dropFirst()
        guard afterDelim.first == " " || afterDelim.first == "\t" else { return nil }
        let body = String(afterDelim).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        return MarkdownOrderedItem(indentLevel: level, number: number, text: body)
    }

    private static func parseTableRow(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }

        var raw = trimmed
        if raw.hasPrefix("|") { raw.removeFirst() }
        if raw.hasSuffix("|") && !raw.hasSuffix("\\|") { raw.removeLast() }

        var cells: [String] = []
        var current = ""
        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "|" {
                current.append("|")
                i += 2
                continue
            }
            if chars[i] == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(chars[i])
            }
            i += 1
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func parseTableSeparator(_ line: String) -> [MarkdownTableAlignment]? {
        guard let cells = parseTableRow(line), !cells.isEmpty else { return nil }
        var alignments: [MarkdownTableAlignment] = []
        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let leftColon = trimmed.hasPrefix(":")
            let rightColon = trimmed.hasSuffix(":")
            var core = trimmed
            if leftColon { core.removeFirst() }
            if rightColon && !core.isEmpty { core.removeLast() }
            guard !core.isEmpty, core.allSatisfy({ $0 == "-" }) else { return nil }

            if leftColon && rightColon {
                alignments.append(.center)
            } else if rightColon {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }
        return alignments
    }

    private static func padRow(_ row: [String], to count: Int) -> [String] {
        if row.count >= count { return Array(row.prefix(count)) }
        return row + Array(repeating: "", count: count - row.count)
    }

    private static func padAlignments(_ alignments: [MarkdownTableAlignment], to count: Int) -> [MarkdownTableAlignment] {
        if alignments.count >= count { return Array(alignments.prefix(count)) }
        return alignments + Array(repeating: .left, count: count - alignments.count)
    }

    // MARK: - Inline Parsing Helpers

    private static func isEscapablePunctuation(_ ch: Character) -> Bool {
        #"\"`*_{}[]()#+-.!~|>"#.contains(ch)
    }

    private static func findClosingBackticks(in chars: [Character], from start: Int, count: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == "`" {
                var run = 0
                while i + run < chars.count && chars[i + run] == "`" {
                    run += 1
                }
                if run == count {
                    return i
                }
                i += run
            } else {
                i += 1
            }
        }
        return nil
    }

    private static func canOpenEmphasis(chars: [Character], at index: Int, marker: Character, length: Int) -> Bool {
        let afterIndex = index + length
        guard afterIndex < chars.count else { return false }
        let next = chars[afterIndex]
        if next.isWhitespace { return false }

        // Avoid intraword underscores like `my_var_name`
        if marker == "_", index > 0 {
            let prev = chars[index - 1]
            if isWordChar(prev) { return false }
        }
        return true
    }

    private static func findClosingDelimiter(
        in chars: [Character],
        from start: Int,
        delimiter: [Character],
        requireWordBoundary: Bool
    ) -> Int? {
        let dLen = delimiter.count
        var i = start
        while i + dLen <= chars.count {
            // Skip escaped chars
            if chars[i] == "\\", i + 1 < chars.count {
                i += 2
                continue
            }
            // Skip inline code spans so delimiters inside code don't close emphasis
            if chars[i] == "`" {
                var ticks = 0
                while i + ticks < chars.count && chars[i + ticks] == "`" { ticks += 1 }
                if let closeTicks = findClosingBackticks(in: chars, from: i + ticks, count: ticks) {
                    i = closeTicks + ticks
                    continue
                }
                i += ticks
                continue
            }

            if matches(chars, at: i, pattern: delimiter) {
                // Closing delimiter must not be preceded by whitespace
                if i > start && !chars[i - 1].isWhitespace {
                    if requireWordBoundary {
                        let after = i + dLen
                        if after < chars.count && isWordChar(chars[after]) {
                            i += 1
                            continue
                        }
                    }
                    return i
                }
            }
            i += 1
        }
        return nil
    }

    private static func matches(_ chars: [Character], at index: Int, pattern: [Character]) -> Bool {
        guard index + pattern.count <= chars.count else { return false }
        for offset in 0..<pattern.count where chars[index + offset] != pattern[offset] {
            return false
        }
        return true
    }

    private static func isWordChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber
    }

    private static func parseLink(in chars: [Character], from start: Int) -> (label: String, url: String, nextIndex: Int)? {
        guard start < chars.count, chars[start] == "[" else { return nil }
        var i = start + 1
        var bracketDepth = 1

        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count {
                i += 2
                continue
            }
            if chars[i] == "[" {
                bracketDepth += 1
            } else if chars[i] == "]" {
                bracketDepth -= 1
                if bracketDepth == 0 { break }
            }
            i += 1
        }
        guard bracketDepth == 0, i + 1 < chars.count, chars[i + 1] == "(" else { return nil }

        let label = String(chars[(start + 1)..<i])
        var urlStart = i + 2
        while urlStart < chars.count && chars[urlStart].isWhitespace {
            urlStart += 1
        }

        var j = urlStart
        var parenDepth = 1
        while j < chars.count {
            if chars[j] == "\\", j + 1 < chars.count {
                j += 2
                continue
            }
            if chars[j] == "(" {
                parenDepth += 1
            } else if chars[j] == ")" {
                parenDepth -= 1
                if parenDepth == 0 { break }
            }
            j += 1
        }
        guard parenDepth == 0 else { return nil }

        var rawDest = String(chars[urlStart..<j]).trimmingCharacters(in: .whitespaces)
        // Strip optional title (`https://example.com "Title"`)
        if let quoteSpace = rawDest.range(of: " \""), rawDest.hasSuffix("\"") {
            rawDest = String(rawDest[..<quoteSpace.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if rawDest.hasPrefix("<") && rawDest.hasSuffix(">") && rawDest.count >= 2 {
            rawDest = String(rawDest.dropFirst().dropLast())
        }
        guard !rawDest.isEmpty, isSafeLinkURL(rawDest) else { return nil }

        return (label, rawDest, j + 1)
    }

    public static func isSafeLinkURL(_ urlString: String) -> Bool {
        let lower = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("https://")
            || lower.hasPrefix("http://")
            || lower.hasPrefix("mailto:")
    }

    // MARK: - HTML Serialization Helpers

    private static func inlinesToHTML(_ nodes: [MarkdownInline]) -> String {
        nodes.map { node in
            switch node {
            case .text(let s):
                return escapeHTML(s)
            case .bold(let children):
                return "<strong>\(inlinesToHTML(children))</strong>"
            case .italic(let children):
                return "<em>\(inlinesToHTML(children))</em>"
            case .boldItalic(let children):
                return "<strong><em>\(inlinesToHTML(children))</em></strong>"
            case .strikethrough(let children):
                return "<del>\(inlinesToHTML(children))</del>"
            case .code(let code):
                return "<code style=\"background: #f1f5f9; padding: 1px 4px; border-radius: 3px; font-family: Menlo, Monaco, Consolas, monospace; font-size: 0.92em;\">\(escapeHTML(code))</code>"
            case .link(let label, let url):
                let inner = inlinesToHTML(label)
                if isSafeLinkURL(url) {
                    return "<a href=\"\(escapeHTMLAttribute(url))\">\(inner)</a>"
                }
                return inner
            }
        }.joined()
    }

    private static func bulletListToHTML(_ items: [MarkdownBulletItem]) -> String {
        var html = ""
        var currentLevel = -1

        for item in items {
            let level = item.indentLevel
            if currentLevel == -1 {
                html += "<ul>"
                currentLevel = level
            } else if level > currentLevel {
                while currentLevel < level {
                    html += "<ul>"
                    currentLevel += 1
                }
            } else if level < currentLevel {
                html += "</li>"
                while currentLevel > level {
                    html += "</ul></li>"
                    currentLevel -= 1
                }
            } else {
                html += "</li>"
            }

            let checkbox: String
            if let checked = item.checked {
                checkbox = checked ? "☑ " : "☐ "
            } else {
                checkbox = ""
            }
            let body = item.text
                .components(separatedBy: "\n")
                .map { inlinesToHTML(parseInlines($0)) }
                .joined(separator: "<br>")
            html += "<li>\(checkbox)\(body)"
        }

        if currentLevel >= 0 {
            html += "</li>"
            while currentLevel > 0 {
                html += "</ul></li>"
                currentLevel -= 1
            }
            html += "</ul>"
        }
        return html
    }

    private static func orderedListToHTML(_ items: [MarkdownOrderedItem]) -> String {
        var html = ""
        var currentLevel = -1

        for item in items {
            let level = item.indentLevel
            if currentLevel == -1 {
                let startAttr = item.number != 1 ? " start=\"\(item.number)\"" : ""
                html += "<ol\(startAttr)>"
                currentLevel = level
            } else if level > currentLevel {
                while currentLevel < level {
                    html += "<ol>"
                    currentLevel += 1
                }
            } else if level < currentLevel {
                html += "</li>"
                while currentLevel > level {
                    html += "</ol></li>"
                    currentLevel -= 1
                }
            } else {
                html += "</li>"
            }

            let body = item.text
                .components(separatedBy: "\n")
                .map { inlinesToHTML(parseInlines($0)) }
                .joined(separator: "<br>")
            html += "<li>\(body)"
        }

        if currentLevel >= 0 {
            html += "</li>"
            while currentLevel > 0 {
                html += "</ol></li>"
                currentLevel -= 1
            }
            html += "</ol>"
        }
        return html
    }

    private static func tableToHTML(
        headers: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    ) -> String {
        let cellStyle = "border: 1px solid #d1d5db; padding: 6px 10px;"
        var html = "<table style=\"border-collapse: collapse; margin: 8px 0;\"><thead><tr>"
        for (idx, header) in headers.enumerated() {
            let align = idx < alignments.count ? alignments[idx].rawValue : "left"
            html += "<th style=\"\(cellStyle) background: #f8fafc; text-align: \(align); font-weight: 600;\">\(inlinesToHTML(parseInlines(header)))</th>"
        }
        html += "</tr></thead><tbody>"
        for row in rows {
            html += "<tr>"
            for (idx, cell) in row.enumerated() {
                let align = idx < alignments.count ? alignments[idx].rawValue : "left"
                html += "<td style=\"\(cellStyle) text-align: \(align);\">\(inlinesToHTML(parseInlines(cell)))</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        return html
    }

    private static func inlinesToPlainText(_ nodes: [MarkdownInline]) -> String {
        nodes.map { node in
            switch node {
            case .text(let s): return s
            case .bold(let children): return inlinesToPlainText(children)
            case .italic(let children): return inlinesToPlainText(children)
            case .boldItalic(let children): return inlinesToPlainText(children)
            case .strikethrough(let children): return inlinesToPlainText(children)
            case .code(let code): return code
            case .link(let label, let url):
                let text = inlinesToPlainText(label)
                return text.isEmpty ? url : text
            }
        }.joined()
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeHTMLAttribute(_ string: String) -> String {
        escapeHTML(string).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
