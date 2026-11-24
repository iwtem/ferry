import AppKit
import FerryCore
import Foundation

/// Handles reading rich clipboard content (HTML / RTF / Markdown / Plain Text)
/// and writing translated structured output back to `NSPasteboard` with matching formats.
@MainActor
public enum RichClipboardService {
    // MARK: - Reading from Pasteboard

    /// Reads the current clipboard content, preserving semantic structure from HTML/RTF
    /// when `preserveFormatting` is enabled.
    public static func readContent(
        from pasteboard: NSPasteboard = .general,
        preserveFormatting: Bool
    ) -> CapturedContent? {
        let rawPlain = pasteboard.string(forType: .string)
        let trimmedPlain = rawPlain?.trimmingCharacters(in: .whitespacesAndNewlines)

        if preserveFormatting {
            // 1. HTML (Safari, Chrome, Notion, Feishu, Slack, Word, Google Docs, Electron apps)
            if let htmlData = pasteboard.data(forType: .html) ?? pasteboard.string(forType: .html)?.data(using: .utf8),
               let converted = HTMLToMarkdownConverter.convert(htmlData: htmlData, plainTextFallback: trimmedPlain),
               converted.hasRichStructure {
                return CapturedContent(text: converted.markdown, format: .richText)
            }

            // 2. RTF (Apple Notes, Pages, TextEdit, Mail)
            if let rtfData = pasteboard.data(forType: .rtf),
               let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil),
               let converted = convertRTFToMarkdown(attributed, plainTextFallback: trimmedPlain),
               converted.hasRichStructure {
                return CapturedContent(text: converted.markdown, format: .richText)
            }
        }

        // 3. Plain text / raw Markdown fallback
        guard let rawPlain, let trimmedPlain, !trimmedPlain.isEmpty else {
            return nil
        }

        if preserveFormatting && MarkdownDocument.hasStructure(rawPlain) {
            let cleanMarkdown = trimOuterBlankLines(rawPlain)
            return CapturedContent(text: cleanMarkdown, format: .markdown)
        }

        return CapturedContent(text: trimmedPlain, format: .plainText)
    }

    // MARK: - Writing to Pasteboard

    /// Resolves the concrete clipboard format for an `.auto` copy/replace operation.
    public static func resolvedFormat(
        requested: OutputCopyFormat,
        sourceFormat: SourceContentFormat,
        text: String
    ) -> OutputCopyFormat {
        switch requested {
        case .richText, .markdown, .plainText:
            return requested
        case .auto:
            let hasStructure = MarkdownDocument.hasStructure(text)
            switch sourceFormat {
            case .richText:
                return hasStructure ? .richText : .plainText
            case .markdown:
                return .markdown
            case .plainText:
                return .plainText
            }
        }
    }

    /// Writes translated output to `pasteboard` in the requested or auto-matched format.
    public static func writeTranslation(
        _ text: String,
        format: OutputCopyFormat = .auto,
        sourceFormat: SourceContentFormat = .plainText,
        to pasteboard: NSPasteboard = .general
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let effective = resolvedFormat(requested: format, sourceFormat: sourceFormat, text: trimmed)

        switch effective {
        case .richText:
            let item = NSPasteboardItem()
            let html = MarkdownDocument.toHTML(trimmed)
            if let htmlData = html.data(using: .utf8) {
                item.setData(htmlData, forType: .html)
            }
            let attributed = buildAttributedString(fromMarkdown: trimmed)
            let range = NSRange(location: 0, length: attributed.length)
            if let rtfData = try? attributed.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) {
                item.setData(rtfData, forType: .rtf)
            }
            let plainFallback = MarkdownDocument.toPlainText(trimmed)
            item.setString(plainFallback, forType: .string)

            pasteboard.clearContents()
            pasteboard.writeObjects([item])

        case .markdown:
            pasteboard.clearContents()
            pasteboard.setString(trimmed, forType: .string)

        case .plainText:
            let output: String
            if format == .plainText && MarkdownDocument.hasStructure(trimmed) {
                output = MarkdownDocument.toPlainText(trimmed)
            } else {
                output = trimmed
            }
            pasteboard.clearContents()
            pasteboard.setString(output, forType: .string)

        case .auto:
            pasteboard.clearContents()
            pasteboard.setString(trimmed, forType: .string)
        }
    }

    // MARK: - RTF -> Markdown Conversion

    static func convertRTFToMarkdown(
        _ attributed: NSAttributedString,
        plainTextFallback: String? = nil
    ) -> HTMLToMarkdownConverter.ConversionResult? {
        let fullString = attributed.string
        guard !fullString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // Compute dominant body font size and detect pure-monospace code pastes.
        var sizeFrequency: [Int: Int] = [:]
        var totalNonWhitespaceChars = 0
        var monospaceChars = 0
        var hasLinks = false
        var hasTextLists = false

        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
            let sub = (fullString as NSString).substring(with: range)
            let nonWSCount = sub.filter { !$0.isWhitespace }.count
            guard nonWSCount > 0 else { return }
            totalNonWhitespaceChars += nonWSCount

            if let font = attrs[.font] as? NSFont {
                let roundedSize = Int(font.pointSize.rounded())
                sizeFrequency[roundedSize, default: 0] += nonWSCount
                if isMonospaceFont(font) {
                    monospaceChars += nonWSCount
                }
            }
            if attrs[.link] != nil {
                hasLinks = true
            }
            if let ps = attrs[.paragraphStyle] as? NSParagraphStyle, !ps.textLists.isEmpty {
                hasTextLists = true
            }
        }

        // If >90% of characters are monospace with no links/lists, treat as raw code paste.
        if totalNonWhitespaceChars > 0,
           Double(monospaceChars) / Double(totalNonWhitespaceChars) > 0.9,
           !hasLinks && !hasTextLists {
            return nil
        }

        let bodyFontSize: CGFloat = CGFloat(
            sizeFrequency.max(by: { $0.value < $1.value })?.key ?? 13
        )

        var hasRichStructure = false
        var hasBlockStructure = false
        var hasLinkOrCode = false
        var outputLines: [String] = []
        var listCounters: [Int: Int] = [:]

        let nsString = fullString as NSString
        var cursor = 0
        while cursor < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
            cursor = NSMaxRange(lineRange)

            let rawLine = nsString.substring(with: lineRange)
            let strippedNewlines = rawLine.trimmingCharacters(in: CharacterSet.newlines)
            if strippedNewlines.trimmingCharacters(in: .whitespaces).isEmpty {
                if outputLines.last != "" && !outputLines.isEmpty {
                    outputLines.append("")
                }
                continue
            }

            let contentLength = (strippedNewlines as NSString).length
            let contentRange = NSRange(location: lineRange.location, length: min(contentLength, lineRange.length))
            guard contentRange.length > 0 else { continue }

            let firstAttrs = attributed.attributes(at: contentRange.location, effectiveRange: nil)
            let paragraphStyle = firstAttrs[.paragraphStyle] as? NSParagraphStyle
            let textLists = paragraphStyle?.textLists ?? []

            var listPrefix = ""
            var effectiveRange = contentRange

            if let deepestList = textLists.last {
                hasRichStructure = true
                hasBlockStructure = true
                let depth = max(0, textLists.count - 1)
                let indent = String(repeating: "  ", count: depth)
                let isOrdered = isOrderedTextList(deepestList)

                if isOrdered {
                    let nextNum = (listCounters[depth] ?? max(1, deepestList.startingItemNumber))
                    listCounters[depth] = nextNum + 1
                    listPrefix = "\(indent)\(nextNum). "
                } else {
                    listPrefix = "\(indent)- "
                }

                // Strip AppKit's embedded list marker (`\t•\t` or `\t1.\t`) at start of paragraph.
                effectiveRange = stripRTFListPrefix(in: nsString, range: contentRange)
            } else {
                listCounters.removeAll()
            }

            guard effectiveRange.length > 0 else { continue }

            // Check if the paragraph is a heading (uniformly larger font, single short line, not a list)
            let headingLevel: Int? = textLists.isEmpty
                ? detectRTFHeadingLevel(in: attributed, range: effectiveRange, bodySize: bodyFontSize)
                : nil

            let isHeading = headingLevel != nil
            let renderedLine = renderRTFLineRuns(
                attributed: attributed,
                range: effectiveRange,
                suppressBold: isHeading,
                hasRichStructure: &hasRichStructure,
                hasLinkOrCode: &hasLinkOrCode
            ).trimmingCharacters(in: .whitespaces)

            guard !renderedLine.isEmpty else { continue }

            if let level = headingLevel {
                hasRichStructure = true
                hasBlockStructure = true
                if !outputLines.isEmpty && outputLines.last != "" {
                    outputLines.append("")
                }
                outputLines.append("\(String(repeating: "#", count: level)) \(renderedLine)")
                outputLines.append("")
            } else if !listPrefix.isEmpty {
                outputLines.append(listPrefix + renderedLine)
            } else {
                outputLines.append(renderedLine)
            }
        }

        while outputLines.last == "" {
            outputLines.removeLast()
        }

        let markdown = outputLines.joined(separator: "\n")
        guard !markdown.isEmpty else { return nil }

        let plainCheck = (plainTextFallback ?? MarkdownDocument.toPlainText(markdown))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !hasBlockStructure && !hasLinkOrCode && HTMLToMarkdownConverter.isSingleLookupTerm(plainCheck) {
            return nil
        }

        return HTMLToMarkdownConverter.ConversionResult(
            markdown: markdown,
            hasRichStructure: hasRichStructure
        )
    }

    private static func isMonospaceFont(_ font: NSFont) -> Bool {
        if font.fontDescriptor.symbolicTraits.contains(.monoSpace) {
            return true
        }
        let name = font.fontName.lowercased()
        let hints = ["mono", "menlo", "monaco", "courier", "consolas", "fira", "jetbrains"]
        return hints.contains { name.contains($0) }
    }

    private static func isOrderedTextList(_ list: NSTextList) -> Bool {
        switch list.markerFormat {
        case .decimal, .lowercaseAlpha, .uppercaseAlpha, .lowercaseRoman, .uppercaseRoman,
             .lowercaseLatin, .uppercaseLatin, .octal:
            return true
        default:
            let raw = list.markerFormat.rawValue.lowercased()
            return raw.contains("decimal") || raw.contains("roman") || raw.contains("alpha")
                || raw.contains("latin") || raw.contains("hex")
        }
    }

    private static func stripRTFListPrefix(in nsString: NSString, range: NSRange) -> NSRange {
        let text = nsString.substring(with: range)
        // AppKit RTF list paragraphs typically start with `\t•\t` or `\t1.\t` or `•\t`
        if let regex = try? NSRegularExpression(pattern: #"^\t?(?:[•◦▪▫–—\-\*]|\d+[\.\)]|[a-zA-Z][\.\)])\t+"#),
           let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            let cut = match.range.length
            return NSRange(location: range.location + cut, length: max(0, range.length - cut))
        }
        return range
    }

    private static func detectRTFHeadingLevel(
        in attributed: NSAttributedString,
        range: NSRange,
        bodySize: CGFloat
    ) -> Int? {
        let lineText = (attributed.string as NSString).substring(with: range).trimmingCharacters(in: .whitespaces)
        guard !lineText.isEmpty, lineText.count <= 140 else { return nil }

        var minSize: CGFloat = .greatestFiniteMagnitude
        var maxSize: CGFloat = 0
        var hasBold = false

        attributed.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
            let sub = (attributed.string as NSString).substring(with: subRange)
            guard !sub.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if let font = attrs[.font] as? NSFont {
                minSize = min(minSize, font.pointSize)
                maxSize = max(maxSize, font.pointSize)
                if font.fontDescriptor.symbolicTraits.contains(.bold) {
                    hasBold = true
                }
            }
        }

        guard minSize < .greatestFiniteMagnitude else { return nil }
        let ratio = minSize / max(bodySize, 10)
        if ratio >= 1.65 { return 1 }
        if ratio >= 1.35 { return 2 }
        if ratio >= 1.18 && hasBold { return 3 }
        return nil
    }

    private static func renderRTFLineRuns(
        attributed: NSAttributedString,
        range: NSRange,
        suppressBold: Bool,
        hasRichStructure: inout Bool,
        hasLinkOrCode: inout Bool
    ) -> String {
        var result = ""
        let nsString = attributed.string as NSString

        attributed.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
            let rawText = nsString.substring(with: subRange).replacingOccurrences(of: "\u{00A0}", with: " ")
            guard !rawText.isEmpty else { return }

            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isBold = !suppressBold && traits.contains(.bold)
            let isItalic = traits.contains(.italic)
            let isMono = font.map(isMonospaceFont) ?? false
            let isStrike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0

            let linkURL: String? = {
                if let url = attrs[.link] as? URL, MarkdownDocument.isSafeLinkURL(url.absoluteString) {
                    return url.absoluteString
                }
                if let str = attrs[.link] as? String, MarkdownDocument.isSafeLinkURL(str) {
                    return str
                }
                return nil
            }()

            let leadingWS = String(rawText.prefix(while: { $0.isWhitespace }))
            let trailingWS = String(rawText.reversed().prefix(while: { $0.isWhitespace }).reversed())
            let core = rawText.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else {
                result += rawText
                return
            }

            var formatted = core
            if isMono && linkURL == nil {
                hasRichStructure = true
                hasLinkOrCode = true
                formatted = core.contains("`") ? "`` \(core) ``" : "`\(core)`"
            } else {
                if isStrike {
                    hasRichStructure = true
                    formatted = "~~\(formatted)~~"
                }
                if isBold && isItalic {
                    hasRichStructure = true
                    formatted = "***\(formatted)***"
                } else if isBold {
                    hasRichStructure = true
                    formatted = "**\(formatted)**"
                } else if isItalic {
                    hasRichStructure = true
                    formatted = "*\(formatted)*"
                }
                if let linkURL, core != linkURL {
                    hasRichStructure = true
                    hasLinkOrCode = true
                    formatted = "[\(formatted)](\(linkURL))"
                }
            }

            result += leadingWS + formatted + trailingWS
        }

        return result
    }

    // MARK: - Markdown -> NSAttributedString (Native RTF Builder, Zero WebKit)

    static func buildAttributedString(fromMarkdown markdown: String) -> NSAttributedString {
        let blocks = MarkdownDocument.parse(markdown)
        let output = NSMutableAttributedString()
        let baseFont = NSFont.systemFont(ofSize: 13)
        let textColor = NSColor.textColor

        for (blockIdx, block) in blocks.enumerated() {
            if blockIdx > 0 && !output.string.hasSuffix("\n") {
                output.append(NSAttributedString(string: "\n"))
            }

            switch block {
            case .heading(let level, let text):
                let size: CGFloat = switch level {
                case 1: 20
                case 2: 17
                case 3: 15
                default: 13.5
                }
                let headingFont = NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
                let ps = NSMutableParagraphStyle()
                ps.paragraphSpacingBefore = blockIdx == 0 ? 0 : 8
                ps.paragraphSpacing = 6
                let attr = renderInlinesToAttributed(
                    MarkdownDocument.parseInlines(text),
                    baseFont: headingFont,
                    textColor: textColor,
                    paragraphStyle: ps
                )
                output.append(attr)
                if blockIdx < blocks.count - 1 {
                    output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: ps]))
                }

            case .paragraph(let text):
                let ps = NSMutableParagraphStyle()
                ps.paragraphSpacing = 8
                ps.lineHeightMultiple = 1.25
                let attr = renderInlinesToAttributed(
                    MarkdownDocument.parseInlines(text),
                    baseFont: baseFont,
                    textColor: textColor,
                    paragraphStyle: ps
                )
                output.append(attr)
                if blockIdx < blocks.count - 1 {
                    output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: ps]))
                }

            case .bulletList(let items):
                for (idx, item) in items.enumerated() {
                    let ps = NSMutableParagraphStyle()
                    let indent = CGFloat(item.indentLevel) * 18
                    ps.firstLineHeadIndent = indent
                    ps.headIndent = indent + 16
                    ps.paragraphSpacing = idx == items.count - 1 ? 8 : 3
                    ps.lineHeightMultiple = 1.2

                    let marker: String
                    if let checked = item.checked {
                        marker = checked ? "☑ " : "☐ "
                    } else {
                        marker = item.indentLevel % 2 == 0 ? "• " : "◦ "
                    }
                    output.append(NSAttributedString(string: marker, attributes: [
                        .font: baseFont,
                        .foregroundColor: textColor,
                        .paragraphStyle: ps
                    ]))
                    output.append(renderInlinesToAttributed(
                        MarkdownDocument.parseInlines(item.text),
                        baseFont: baseFont,
                        textColor: textColor,
                        paragraphStyle: ps
                    ))
                    if idx < items.count - 1 || blockIdx < blocks.count - 1 {
                        output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: ps]))
                    }
                }

            case .orderedList(let items):
                for (idx, item) in items.enumerated() {
                    let ps = NSMutableParagraphStyle()
                    let indent = CGFloat(item.indentLevel) * 18
                    ps.firstLineHeadIndent = indent
                    ps.headIndent = indent + 20
                    ps.paragraphSpacing = idx == items.count - 1 ? 8 : 3
                    ps.lineHeightMultiple = 1.2

                    output.append(NSAttributedString(string: "\(item.number). ", attributes: [
                        .font: baseFont,
                        .foregroundColor: textColor,
                        .paragraphStyle: ps
                    ]))
                    output.append(renderInlinesToAttributed(
                        MarkdownDocument.parseInlines(item.text),
                        baseFont: baseFont,
                        textColor: textColor,
                        paragraphStyle: ps
                    ))
                    if idx < items.count - 1 || blockIdx < blocks.count - 1 {
                        output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: ps]))
                    }
                }

            case .blockquote(let lines):
                let ps = NSMutableParagraphStyle()
                ps.firstLineHeadIndent = 14
                ps.headIndent = 14
                ps.paragraphSpacing = 8
                ps.lineHeightMultiple = 1.25
                let quoteText = lines.joined(separator: "\n")
                let attr = renderInlinesToAttributed(
                    MarkdownDocument.parseInlines(quoteText),
                    baseFont: baseFont,
                    textColor: NSColor.secondaryLabelColor,
                    paragraphStyle: ps
                )
                output.append(attr)
                if blockIdx < blocks.count - 1 {
                    output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: ps]))
                }

            case .codeBlock(_, let code):
                let ps = NSMutableParagraphStyle()
                ps.firstLineHeadIndent = 10
                ps.headIndent = 10
                ps.paragraphSpacing = 8
                let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                let codeBG = NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1.0)
                output.append(NSAttributedString(string: code, attributes: [
                    .font: codeFont,
                    .foregroundColor: textColor,
                    .backgroundColor: codeBG,
                    .paragraphStyle: ps
                ]))
                if blockIdx < blocks.count - 1 {
                    output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: ps]))
                }

            case .table(let headers, let alignments, let rows):
                output.append(buildRTFTable(headers: headers, alignments: alignments, rows: rows, baseFont: baseFont))

            case .thematicBreak:
                let ps = NSMutableParagraphStyle()
                ps.paragraphSpacing = 8
                output.append(NSAttributedString(string: "──────────", attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: ps
                ]))
                if blockIdx < blocks.count - 1 {
                    output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: ps]))
                }
            }
        }

        return output
    }

    private static func renderInlinesToAttributed(
        _ nodes: [MarkdownInline],
        baseFont: NSFont,
        textColor: NSColor,
        paragraphStyle: NSParagraphStyle,
        bold: Bool = false,
        italic: Bool = false,
        strike: Bool = false,
        linkURL: URL? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for node in nodes {
            switch node {
            case .text(let s):
                let font = styledFont(baseFont, bold: bold, italic: italic)
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: linkURL != nil ? NSColor.linkColor : textColor,
                    .paragraphStyle: paragraphStyle
                ]
                if strike {
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                if let linkURL {
                    attrs[.link] = linkURL
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                result.append(NSAttributedString(string: s, attributes: attrs))

            case .bold(let children):
                result.append(renderInlinesToAttributed(
                    children, baseFont: baseFont, textColor: textColor, paragraphStyle: paragraphStyle,
                    bold: true, italic: italic, strike: strike, linkURL: linkURL
                ))

            case .italic(let children):
                result.append(renderInlinesToAttributed(
                    children, baseFont: baseFont, textColor: textColor, paragraphStyle: paragraphStyle,
                    bold: bold, italic: true, strike: strike, linkURL: linkURL
                ))

            case .boldItalic(let children):
                result.append(renderInlinesToAttributed(
                    children, baseFont: baseFont, textColor: textColor, paragraphStyle: paragraphStyle,
                    bold: true, italic: true, strike: strike, linkURL: linkURL
                ))

            case .strikethrough(let children):
                result.append(renderInlinesToAttributed(
                    children, baseFont: baseFont, textColor: textColor, paragraphStyle: paragraphStyle,
                    bold: bold, italic: italic, strike: true, linkURL: linkURL
                ))

            case .code(let code):
                let mono = NSFont.monospacedSystemFont(ofSize: max(11, baseFont.pointSize - 1), weight: .regular)
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: mono,
                    .foregroundColor: textColor,
                    .backgroundColor: NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1.0),
                    .paragraphStyle: paragraphStyle
                ]
                if let linkURL {
                    attrs[.link] = linkURL
                }
                result.append(NSAttributedString(string: code, attributes: attrs))

            case .link(let label, let urlString):
                let url = MarkdownDocument.isSafeLinkURL(urlString) ? URL(string: urlString) : nil
                result.append(renderInlinesToAttributed(
                    label, baseFont: baseFont, textColor: textColor, paragraphStyle: paragraphStyle,
                    bold: bold, italic: italic, strike: strike, linkURL: url
                ))
            }
        }

        return result
    }

    private static func styledFont(_ base: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    private static func buildRTFTable(
        headers: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]],
        baseFont: NSFont
    ) -> NSAttributedString {
        let table = NSTextTable()
        table.numberOfColumns = max(1, headers.count)
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        let result = NSMutableAttributedString()
        let borderColor = NSColor(srgbRed: 0.82, green: 0.84, blue: 0.87, alpha: 1.0)
        let headerBG = NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
        let allRows: [([String], Bool)] = [(headers, true)] + rows.map { ($0, false) }

        for (rowIdx, (cells, isHeader)) in allRows.enumerated() {
            for colIdx in 0..<table.numberOfColumns {
                let cellText = colIdx < cells.count ? cells[colIdx] : ""
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: rowIdx,
                    rowSpan: 1,
                    startingColumn: colIdx,
                    columnSpan: 1
                )
                block.setWidth(0.75, type: .absoluteValueType, for: .border)
                block.setBorderColor(borderColor)
                block.setWidth(5, type: .absoluteValueType, for: .padding, edge: .minX)
                block.setWidth(5, type: .absoluteValueType, for: .padding, edge: .maxX)
                block.setWidth(4, type: .absoluteValueType, for: .padding, edge: .minY)
                block.setWidth(4, type: .absoluteValueType, for: .padding, edge: .maxY)
                if isHeader {
                    block.backgroundColor = headerBG
                }

                let ps = NSMutableParagraphStyle()
                ps.textBlocks = [block]
                let align = colIdx < alignments.count ? alignments[colIdx] : .left
                switch align {
                case .left: ps.alignment = .left
                case .center: ps.alignment = .center
                case .right: ps.alignment = .right
                }

                let cellAttr = renderInlinesToAttributed(
                    MarkdownDocument.parseInlines(cellText),
                    baseFont: baseFont,
                    textColor: NSColor.textColor,
                    paragraphStyle: ps,
                    bold: isHeader
                )
                result.append(cellAttr)
                result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: ps]))
            }
        }
        return result
    }

    private static func trimOuterBlankLines(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
