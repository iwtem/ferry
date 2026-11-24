import Foundation

/// Cleans common PDF / academic paper copy-paste artifacts: hard line wraps and hyphenated word splits.
public enum TextPreprocessor {
    /// Joins wrapped lines and de-hyphenates split words (e.g. `algo-\nrithm` → `algorithm`)
    /// while preserving real paragraph breaks (blank lines), bullet/numbered lists, and fenced code blocks.
    public static func cleanPDFLineBreaks(_ input: String) -> String {
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard normalized.contains("\n") else { return normalized }

        let rawLines = normalized.components(separatedBy: "\n")
        var outputLines: [String] = []
        var paragraphBuffer: [String] = []
        var inCodeFence = false

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            outputLines.append(joinParagraphLines(paragraphBuffer))
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                inCodeFence.toggle()
                outputLines.append(line)
                continue
            }

            if inCodeFence {
                outputLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                // Collapse consecutive blank lines to at most one blank line between paragraphs
                if outputLines.last != "" {
                    outputLines.append("")
                }
                continue
            }

            paragraphBuffer.append(line)
        }

        flushParagraph()
        return outputLines.joined(separator: "\n")
    }

    private static func joinParagraphLines(_ lines: [String]) -> String {
        guard lines.count > 1 else { return lines[0] }

        var resultLines: [String] = []
        var current = preservedLeadingLine(lines[0])

        for index in 1..<lines.count {
            let rawNext = lines[index]
            let next = rawNext.trimmingCharacters(in: .whitespaces)
            guard !next.isEmpty else { continue }

            if shouldKeepLineBreak(previous: current, rawNext: rawNext, next: next) {
                resultLines.append(current)
                current = preservedLeadingLine(rawNext)
            } else {
                current = joinWrapped(current, next)
            }
        }

        resultLines.append(current)
        return resultLines.joined(separator: "\n")
    }

    /// Preserves leading indentation for indented code blocks and nested list items,
    /// while stripping stray leading spaces on ordinary prose lines.
    private static func preservedLeadingLine(_ rawLine: String) -> String {
        let strippedTrailing = rawLine.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
        let trimmed = strippedTrailing.trimmingCharacters(in: .whitespaces)
        if strippedTrailing.hasPrefix("    ") || strippedTrailing.hasPrefix("\t") {
            return strippedTrailing
        }
        if (strippedTrailing.hasPrefix("  ") || strippedTrailing.hasPrefix("\t")),
           startsWithListMarker(trimmed) || trimmed.hasPrefix(">") {
            return strippedTrailing
        }
        return trimmed
    }

    private static func shouldKeepLineBreak(previous: String, rawNext: String, next: String) -> Bool {
        let prevTrimmed = previous.trimmingCharacters(in: .whitespaces)
        // Indented code or block quotes
        if rawNext.hasPrefix("    ") || rawNext.hasPrefix("\t") {
            return true
        }
        // Keep line breaks after Markdown headings, blockquotes, tables, or horizontal rules
        if prevTrimmed.hasPrefix("#") || prevTrimmed.hasPrefix(">") || prevTrimmed.hasPrefix("|") || isThematicBreak(prevTrimmed) {
            return true
        }
        // Markdown headings, blockquotes, tables, horizontal rules
        if next.hasPrefix("#") || next.hasPrefix(">") || next.hasPrefix("|") || isThematicBreak(next) {
            return true
        }
        // Bullet or numbered list items
        if startsWithListMarker(next) {
            return true
        }
        // Code-like line endings
        if let last = prevTrimmed.last, "{};\\".contains(last) {
            return true
        }
        // Short header / label ending with colon
        if prevTrimmed.count <= 48, (prevTrimmed.hasSuffix(":") || prevTrimmed.hasSuffix("：")) {
            return true
        }
        return false
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let stripped = trimmed.filter { $0 != " " && $0 != "\t" }
        guard stripped.count >= 3, let first = stripped.first else { return false }
        guard first == "-" || first == "*" || first == "_" else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func joinWrapped(_ previous: String, _ next: String) -> String {
        guard !previous.isEmpty else { return next }
        guard !next.isEmpty else { return previous }

        if let lastScalar = previous.unicodeScalars.last,
           (lastScalar == "-" || lastScalar == "\u{00AD}" || lastScalar == "\u{2010}"),
           let beforeHyphen = previous.dropLast().last,
           beforeHyphen.isASCII && beforeHyphen.isLetter,
           let nextFirst = next.first,
           nextFirst.isASCII {
            // De-hyphenate wrapped lowercase splits: "algo-" + "rithm" -> "algorithm"
            if nextFirst.isLowercase {
                return String(previous.dropLast()) + next
            }
            // Keep hyphen without stray space for codes/proper compounds: "GPT-" + "4" -> "GPT-4"
            if nextFirst.isUppercase || nextFirst.isNumber {
                return previous + next
            }
        }

        // Join CJK-to-CJK without adding a stray space
        if let last = previous.unicodeScalars.last,
           let first = next.unicodeScalars.first,
           isCJK(last) && isCJK(first) {
            return previous + next
        }

        return previous + " " + next
    }

    private static func startsWithListMarker(_ text: String) -> Bool {
        let bulletPrefixes = ["•", "·", "▪", "◦", "–", "—", "-", "*", "+", "✓", "✔", "☐", "☑"]
        for prefix in bulletPrefixes where text.hasPrefix(prefix + " ") {
            return true
        }
        // Numbered or bracketed list items: "1. ", "2) ", "(1) ", "[1] "
        if text.range(of: #"^(\(\d+\)|\[\d+\]|\d+[\.\)])\s+"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F,
             0x3040...0x309F,
             0x30A0...0x30FF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xAC00...0xD7AF,
             0xF900...0xFAFF,
             0xFF00...0xFFEF:
            return true
        default:
            return false
        }
    }
}
