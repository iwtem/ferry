import Foundation

/// Converts clipboard HTML (Safari, Chrome, Notion, Feishu, Slack, Word, Google Docs, etc.)
/// into clean, structure-preserving Markdown without WebKit dependencies.
public enum HTMLToMarkdownConverter {
    public struct ConversionResult: Equatable, Sendable {
        public let markdown: String
        /// True when the HTML contained genuine semantic formatting (headings, emphasis,
        /// links, lists, blockquotes, code, tables, or horizontal rules).
        public let hasRichStructure: Bool

        public init(markdown: String, hasRichStructure: Bool) {
            self.markdown = markdown
            self.hasRichStructure = hasRichStructure
        }
    }

    /// Exposes Ferry's dictionary-term heuristic so AppKit RTF conversion applies the exact
    /// same single-word lookup safeguard as HTML conversion.
    public static func isSingleLookupTerm(_ text: String) -> Bool {
        TranslationPrompt.isLookupTerm(text)
    }

    /// Converts raw HTML clipboard data to Markdown. Returns `nil` when parsing fails or
    /// when the HTML represents syntax-highlighted source code / empty content that is
    /// better handled as plain text.
    public static func convert(
        htmlData: Data,
        plainTextFallback: String? = nil
    ) -> ConversionResult? {
        guard let htmlString = decodeHTMLString(from: htmlData) else { return nil }
        return convert(html: htmlString, plainTextFallback: plainTextFallback)
    }

    public static func convert(
        html: String,
        plainTextFallback: String? = nil
    ) -> ConversionResult? {
        let fragment = extractFragment(from: html)
        let trimmedFragment = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFragment.isEmpty else { return nil }

        let wrappedHTML = wrapForUTF8TidyParse(trimmedFragment)
        guard let document = try? XMLDocument(xmlString: wrappedHTML, options: [.documentTidyHTML, .nodePreserveWhitespace]),
              let root = findBodyElement(in: document) ?? document.rootElement()
        else {
            return nil
        }

        // Guard against syntax-highlighted code pasted from VS Code / Xcode / IDEs.
        if isSyntaxHighlightedCodeContainer(root) {
            return nil
        }

        var context = RenderContext()
        let rawMarkdown = renderChildren(of: root, context: &context)
        let cleaned = normalizeMarkdownOutput(rawMarkdown)
        guard !cleaned.isEmpty else { return nil }

        // Preserve dictionary lookup UX when user double-copies a single bold/italic word
        // from an article without any block structure, links, or code.
        let plainCheck = (plainTextFallback ?? MarkdownDocument.toPlainText(cleaned))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !context.hasBlockStructure,
           !context.hasLinkOrCode,
           TranslationPrompt.isLookupTerm(plainCheck) {
            return nil
        }

        return ConversionResult(
            markdown: cleaned,
            hasRichStructure: context.hasRichStructure
        )
    }

    // MARK: - Decoding & Fragment Preparation

    private static func decodeHTMLString(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func extractFragment(from html: String) -> String {
        let startMarker = "<!--StartFragment-->"
        let endMarker = "<!--EndFragment-->"
        if let startRange = html.range(of: startMarker),
           let endRange = html.range(of: endMarker, range: startRange.upperBound..<html.endIndex) {
            return String(html[startRange.upperBound..<endRange.lowerBound])
        }
        return html
    }

    private static func wrapForUTF8TidyParse(_ html: String) -> String {
        let metaTag = "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">"
        let lower = html.lowercased()
        if lower.contains("<html") || lower.contains("<body") {
            if !lower.contains("http-equiv=\"content-type\"") && !lower.contains("http-equiv='content-type'") {
                if let headRange = html.range(of: "<head>", options: .caseInsensitive) {
                    var mutable = html
                    mutable.insert(contentsOf: metaTag, at: headRange.upperBound)
                    return mutable
                }
                return "<!DOCTYPE html><html><head>\(metaTag)</head>" + html
            }
            return html
        }
        return "<!DOCTYPE html><html><head>\(metaTag)</head><body>\(html)</body></html>"
    }

    private static func findBodyElement(in document: XMLDocument) -> XMLElement? {
        guard let root = document.rootElement() else { return nil }
        return findFirstElement(named: "body", in: root)
    }

    private static func findFirstElement(named tagName: String, in element: XMLElement) -> XMLElement? {
        if element.name?.lowercased() == tagName {
            return element
        }
        for child in element.children ?? [] {
            if let childEl = child as? XMLElement,
               let found = findFirstElement(named: tagName, in: childEl) {
                return found
            }
        }
        return nil
    }

    // MARK: - IDE / Syntax-Highlighted Code Detection

    private static func isSyntaxHighlightedCodeContainer(_ body: XMLElement) -> Bool {
        let significantChildren = (body.children ?? []).compactMap { node -> XMLElement? in
            if let el = node as? XMLElement {
                let tag = el.name?.lowercased() ?? ""
                if ignoredTags.contains(tag) { return nil }
                return el
            }
            return nil
        }

        // VS Code / Xcode / Terminal copy a single top-level <div> or <pre> with monospace + white-space:pre
        // containing only styled <div>/<span>/<br> tokens and no prose structure tags.
        guard significantChildren.count == 1, let single = significantChildren.first else {
            return false
        }
        let tag = single.name?.lowercased() ?? ""
        guard tag == "div" || tag == "pre" else { return false }

        let style = parseInlineStyle(single.attribute(forName: "style")?.stringValue)
        let isMonospace = styleFontIsMonospace(style["font-family"])
        let isPreWhitespace = (style["white-space"] ?? "").contains("pre")
        guard (isMonospace && isPreWhitespace) || (tag == "div" && isMonospace && containsNoProseTags(single)) else {
            return false
        }
        return containsNoProseTags(single)
    }

    private static func containsNoProseTags(_ element: XMLElement) -> Bool {
        let proseTags: Set<String> = [
            "h1", "h2", "h3", "h4", "h5", "h6",
            "ul", "ol", "li", "table", "blockquote", "a", "p", "hr"
        ]
        for child in element.children ?? [] {
            guard let el = child as? XMLElement else { continue }
            let tag = el.name?.lowercased() ?? ""
            if proseTags.contains(tag) { return false }
            if !containsNoProseTags(el) { return false }
        }
        return true
    }

    // MARK: - DOM Traversal & Markdown Emission

    private struct ActiveStyles {
        var bold: Bool = false
        var italic: Bool = false
        var strike: Bool = false
        var code: Bool = false
        var preserveWhitespace: Bool = false
    }

    private struct RenderContext {
        var styles = ActiveStyles()
        var listDepth: Int = 0
        var hasRichStructure: Bool = false
        var hasBlockStructure: Bool = false
        var hasLinkOrCode: Bool = false
    }

    private static let ignoredTags: Set<String> = [
        "script", "style", "head", "title", "meta", "link", "noscript", "template", "svg", "iframe", "button"
    ]

    private static func renderChildren(of element: XMLElement, context: inout RenderContext) -> String {
        var output = ""
        for child in element.children ?? [] {
            output += renderNode(child, context: &context)
        }
        return output
    }

    private static func renderNode(_ node: XMLNode, context: inout RenderContext) -> String {
        switch node.kind {
        case .text:
            let raw = node.stringValue ?? ""
            if context.styles.preserveWhitespace {
                return raw
            }
            return collapseHTMLWhitespace(raw)

        case .element:
            guard let element = node as? XMLElement else { return "" }
            return renderElement(element, context: &context)

        default:
            return ""
        }
    }

    private static func renderElement(_ element: XMLElement, context: inout RenderContext) -> String {
        let tag = element.name?.lowercased() ?? ""
        if ignoredTags.contains(tag) {
            return ""
        }

        let style = parseInlineStyle(element.attribute(forName: "style")?.stringValue)
        if style["display"] == "none" || style["visibility"] == "hidden" {
            return ""
        }

        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tag.dropFirst())) ?? 1
            var innerCtx = context
            innerCtx.styles.bold = true // Avoid redundant `## **Heading**`
            let inner = renderChildren(of: element, context: &innerCtx)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !inner.isEmpty else { return "" }
            context.hasRichStructure = true
            context.hasBlockStructure = true
            let prefix = String(repeating: "#", count: level)
            return "\n\n\(prefix) \(inner)\n\n"

        case "br":
            return "\n"

        case "hr":
            context.hasRichStructure = true
            context.hasBlockStructure = true
            return "\n\n---\n\n"

        case "pre":
            let (codeText, language) = extractCodeBlock(from: element)
            guard !codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            context.hasRichStructure = true
            context.hasBlockStructure = true
            context.hasLinkOrCode = true
            let fence = codeText.contains("```") ? "~~~~" : "```"
            let lang = language ?? ""
            let cleanedCode = codeText.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            return "\n\n\(fence)\(lang)\n\(cleanedCode)\n\(fence)\n\n"

        case "code", "kbd", "samp", "tt":
            if context.styles.preserveWhitespace {
                return element.stringValue ?? ""
            }
            let rawCode = (element.stringValue ?? "")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            guard !rawCode.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
            context.hasRichStructure = true
            context.hasLinkOrCode = true
            return wrapInlineCode(rawCode)

        case "blockquote":
            var innerCtx = context
            let inner = normalizeMarkdownOutput(renderChildren(of: element, context: &innerCtx))
            guard !inner.isEmpty else { return "" }
            context.hasRichStructure = true
            context.hasBlockStructure = true
            let quoted = inner
                .components(separatedBy: "\n")
                .map { $0.isEmpty ? ">" : "> \($0)" }
                .joined(separator: "\n")
            return "\n\n\(quoted)\n\n"

        case "ul":
            return renderList(element, ordered: false, context: &context)

        case "ol":
            return renderList(element, ordered: true, context: &context)

        case "table":
            return renderTable(element, context: &context)

        case "a":
            let href = element.attribute(forName: "href")?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = renderChildren(of: element, context: &context)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return "" }
            if MarkdownDocument.isSafeLinkURL(href), label != href {
                context.hasRichStructure = true
                context.hasLinkOrCode = true
                return "[\(label)](\(href))"
            }
            return label

        case "strong", "b":
            // Google Docs wraps entire copied fragments in `<b style="font-weight:normal;">`!
            if isExplicitNormalWeight(style["font-weight"]) {
                return renderChildren(of: element, context: &context)
            }
            return renderInlineStyled(element, addBold: true, addItalic: false, addStrike: false, context: &context)

        case "em", "i":
            if style["font-style"] == "normal" {
                return renderChildren(of: element, context: &context)
            }
            return renderInlineStyled(element, addBold: false, addItalic: true, addStrike: false, context: &context)

        case "del", "s", "strike":
            return renderInlineStyled(element, addBold: false, addItalic: false, addStrike: true, context: &context)

        case "span", "font", "mark", "u", "ins", "small", "sub", "sup", "abbr":
            let addBold = isBoldWeight(style["font-weight"])
            let addItalic = isItalicStyle(style["font-style"])
            let addStrike = isStrikethroughStyle(style)
            let isInlineMono = styleFontIsMonospace(style["font-family"]) && !context.styles.code

            if isInlineMono && !addBold && !addItalic && !addStrike {
                let raw = (element.stringValue ?? "").replacingOccurrences(of: "\u{00A0}", with: " ")
                if !raw.contains("\n"), !raw.trimmingCharacters(in: .whitespaces).isEmpty {
                    context.hasRichStructure = true
                    context.hasLinkOrCode = true
                    return wrapInlineCode(raw)
                }
            }
            return renderInlineStyled(
                element,
                addBold: addBold,
                addItalic: addItalic,
                addStrike: addStrike,
                context: &context
            )

        case "p", "section", "article", "header", "footer", "main", "aside", "figure", "figcaption", "dt", "dd":
            let addBold = isBoldWeight(style["font-weight"])
            let addItalic = isItalicStyle(style["font-style"])
            let addStrike = isStrikethroughStyle(style)
            let inner = renderInlineStyled(
                element,
                addBold: addBold,
                addItalic: addItalic,
                addStrike: addStrike,
                context: &context
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !inner.isEmpty else { return "" }
            return "\n\n\(inner)\n\n"

        case "div":
            let inner = renderChildren(of: element, context: &context)
            let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            // Preserve block separation between sibling divs without over-splitting nested wrappers
            if containsBlockChildren(element) {
                return "\n\n\(trimmed)\n\n"
            }
            return "\n\(trimmed)\n"

        case "li":
            // Standalone <li> outside a list
            let inner = renderChildren(of: element, context: &context).trimmingCharacters(in: .whitespacesAndNewlines)
            return inner.isEmpty ? "" : "\n- \(inner)\n"

        case "img":
            let alt = element.attribute(forName: "alt")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return alt

        default:
            return renderChildren(of: element, context: &context)
        }
    }

    private static func renderInlineStyled(
        _ element: XMLElement,
        addBold: Bool,
        addItalic: Bool,
        addStrike: Bool,
        context: inout RenderContext
    ) -> String {
        let applyBold = addBold && !context.styles.bold
        let applyItalic = addItalic && !context.styles.italic
        let applyStrike = addStrike && !context.styles.strike

        var innerCtx = context
        if applyBold { innerCtx.styles.bold = true }
        if applyItalic { innerCtx.styles.italic = true }
        if applyStrike { innerCtx.styles.strike = true }

        let inner = renderChildren(of: element, context: &innerCtx)
        context.hasRichStructure = context.hasRichStructure || innerCtx.hasRichStructure
        context.hasBlockStructure = context.hasBlockStructure || innerCtx.hasBlockStructure
        context.hasLinkOrCode = context.hasLinkOrCode || innerCtx.hasLinkOrCode

        guard applyBold || applyItalic || applyStrike else {
            return inner
        }
        guard !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return inner
        }

        // Preserve leading and trailing spaces outside Markdown markers so `** text **` never occurs.
        let leadingWS = String(inner.prefix(while: { $0.isWhitespace }))
        let trailingWS = String(inner.reversed().prefix(while: { $0.isWhitespace }).reversed())
        let core = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return inner }

        // If the styled container spans multiple blocks (e.g. a bold wrapper around paragraphs), don't wrap across `\n\n`.
        if core.contains("\n\n") {
            return inner
        }

        context.hasRichStructure = true
        var wrapped = core
        if applyStrike { wrapped = "~~\(wrapped)~~" }
        if applyBold && applyItalic {
            wrapped = "***\(wrapped)***"
        } else if applyBold {
            wrapped = "**\(wrapped)**"
        } else if applyItalic {
            wrapped = "*\(wrapped)*"
        }
        return leadingWS + wrapped + trailingWS
    }

    // MARK: - Lists

    private static func renderList(_ listElement: XMLElement, ordered: Bool, context: inout RenderContext) -> String {
        let depth = context.listDepth
        let startNumber = Int(listElement.attribute(forName: "start")?.stringValue ?? "") ?? 1
        var lines: [String] = []
        var itemIndex = startNumber

        for child in listElement.children ?? [] {
            guard let childEl = child as? XMLElement else { continue }
            let childTag = childEl.name?.lowercased() ?? ""

            if childTag == "li" {
                let indent = String(repeating: "  ", count: depth)
                let taskState = detectTaskListState(in: childEl)

                var textParts: [String] = []
                var nestedListParts: [String] = []

                for liChild in childEl.children ?? [] {
                    if let subEl = liChild as? XMLElement {
                        let subTag = subEl.name?.lowercased() ?? ""
                        if subTag == "ul" || subTag == "ol" {
                            var subCtx = context
                            subCtx.listDepth = depth + 1
                            let nested = renderList(subEl, ordered: subTag == "ol", context: &subCtx)
                                .trimmingCharacters(in: .newlines)
                            context.hasRichStructure = context.hasRichStructure || subCtx.hasRichStructure
                            context.hasBlockStructure = context.hasBlockStructure || subCtx.hasBlockStructure
                            context.hasLinkOrCode = context.hasLinkOrCode || subCtx.hasLinkOrCode
                            if !nested.isEmpty {
                                nestedListParts.append(nested)
                            }
                            continue
                        }
                        if subTag == "input" && subEl.attribute(forName: "type")?.stringValue?.lowercased() == "checkbox" {
                            continue
                        }
                    }
                    var itemCtx = context
                    textParts.append(renderNode(liChild, context: &itemCtx))
                    context.hasRichStructure = context.hasRichStructure || itemCtx.hasRichStructure
                    context.hasBlockStructure = context.hasBlockStructure || itemCtx.hasBlockStructure
                    context.hasLinkOrCode = context.hasLinkOrCode || itemCtx.hasLinkOrCode
                }

                let itemText = textParts.joined()
                    .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !itemText.isEmpty || !nestedListParts.isEmpty {
                    let marker: String
                    if let checked = taskState {
                        marker = checked ? "- [x] " : "- [ ] "
                    } else if ordered {
                        marker = "\(itemIndex). "
                    } else {
                        marker = "- "
                    }

                    if !itemText.isEmpty {
                        let formattedBody = itemText
                            .components(separatedBy: "\n")
                            .enumerated()
                            .map { idx, line in
                                idx == 0 ? line : indent + "  " + line.trimmingCharacters(in: .whitespaces)
                            }
                            .joined(separator: "\n")
                        lines.append(indent + marker + formattedBody)
                    }
                    for nested in nestedListParts {
                        lines.append(nested)
                    }
                    itemIndex += 1
                }
            } else if childTag == "ul" || childTag == "ol" {
                var subCtx = context
                subCtx.listDepth = depth + 1
                let nested = renderList(childEl, ordered: childTag == "ol", context: &subCtx)
                    .trimmingCharacters(in: .newlines)
                if !nested.isEmpty {
                    lines.append(nested)
                }
            }
        }

        guard !lines.isEmpty else { return "" }
        context.hasRichStructure = true
        context.hasBlockStructure = true
        let body = lines.joined(separator: "\n")
        return depth == 0 ? "\n\n\(body)\n\n" : "\n\(body)"
    }

    private static func detectTaskListState(in liElement: XMLElement) -> Bool? {
        if let dataChecked = liElement.attribute(forName: "data-checked")?.stringValue?.lowercased() {
            if dataChecked == "true" { return true }
            if dataChecked == "false" { return false }
        }
        if let ariaChecked = liElement.attribute(forName: "aria-checked")?.stringValue?.lowercased() {
            if ariaChecked == "true" { return true }
            if ariaChecked == "false" { return false }
        }
        if let checkbox = findCheckboxInput(in: liElement) {
            return checkbox.attribute(forName: "checked") != nil
        }
        return nil
    }

    private static func findCheckboxInput(in element: XMLElement) -> XMLElement? {
        for child in element.children ?? [] {
            guard let el = child as? XMLElement else { continue }
            let tag = el.name?.lowercased() ?? ""
            if tag == "ul" || tag == "ol" { continue }
            if tag == "input", el.attribute(forName: "type")?.stringValue?.lowercased() == "checkbox" {
                return el
            }
            if let nested = findCheckboxInput(in: el) {
                return nested
            }
        }
        return nil
    }

    // MARK: - Tables

    private struct TableRowData {
        let cells: [String]
        let alignments: [MarkdownTableAlignment]
        let isHeader: Bool
    }

    private static func renderTable(_ tableElement: XMLElement, context: inout RenderContext) -> String {
        var rows: [TableRowData] = []
        collectTableRows(from: tableElement, inHeaderSection: false, rows: &rows, context: &context)

        guard !rows.isEmpty else { return "" }

        // Unwrap single-cell layout tables (common in emails and web layouts)
        let maxCols = rows.map { $0.cells.count }.max() ?? 0
        if rows.count == 1 && maxCols <= 1 && !rows[0].isHeader {
            let cell = rows[0].cells.first ?? ""
            return cell.isEmpty ? "" : "\n\n\(cell)\n\n"
        }
        guard maxCols >= 1 else { return "" }

        context.hasRichStructure = true
        context.hasBlockStructure = true

        let headerRow = rows[0]
        let bodyRows = Array(rows.dropFirst())

        func formatPipeRow(_ cells: [String]) -> String {
            let padded = cells.count < maxCols ? cells + Array(repeating: "", count: maxCols - cells.count) : cells
            let escaped = padded.map { cell in
                cell
                    .replacingOccurrences(of: "|", with: "\\|")
                    .replacingOccurrences(of: #"\s*\n+\s*"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            return "| " + escaped.joined(separator: " | ") + " |"
        }

        let sepCells: [String] = (0..<maxCols).map { col in
            let align = col < headerRow.alignments.count ? headerRow.alignments[col] : .left
            switch align {
            case .left: return "---"
            case .center: return ":---:"
            case .right: return "---:"
            }
        }

        var mdLines: [String] = [
            formatPipeRow(headerRow.cells),
            "| " + sepCells.joined(separator: " | ") + " |"
        ]
        for row in bodyRows {
            mdLines.append(formatPipeRow(row.cells))
        }
        return "\n\n" + mdLines.joined(separator: "\n") + "\n\n"
    }

    private static func collectTableRows(
        from element: XMLElement,
        inHeaderSection: Bool,
        rows: inout [TableRowData],
        context: inout RenderContext
    ) {
        for child in element.children ?? [] {
            guard let el = child as? XMLElement else { continue }
            let tag = el.name?.lowercased() ?? ""
            switch tag {
            case "thead":
                collectTableRows(from: el, inHeaderSection: true, rows: &rows, context: &context)
            case "tbody", "tfoot":
                collectTableRows(from: el, inHeaderSection: false, rows: &rows, context: &context)
            case "tr":
                var cells: [String] = []
                var alignments: [MarkdownTableAlignment] = []
                var allTH = true
                for cellNode in el.children ?? [] {
                    guard let cellEl = cellNode as? XMLElement else { continue }
                    let cellTag = cellEl.name?.lowercased() ?? ""
                    guard cellTag == "td" || cellTag == "th" else { continue }
                    if cellTag != "th" { allTH = false }
                    var cellCtx = context
                    let cellText = renderChildren(of: cellEl, context: &cellCtx)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    cells.append(cellText)
                    alignments.append(extractAlignment(from: cellEl))
                }
                if !cells.isEmpty {
                    rows.append(TableRowData(cells: cells, alignments: alignments, isHeader: inHeaderSection || allTH))
                }
            default:
                continue
            }
        }
    }

    private static func extractAlignment(from cell: XMLElement) -> MarkdownTableAlignment {
        let style = parseInlineStyle(cell.attribute(forName: "style")?.stringValue)
        let rawAlign = (style["text-align"] ?? cell.attribute(forName: "align")?.stringValue ?? "").lowercased()
        switch rawAlign {
        case "center": return .center
        case "right": return .right
        default: return .left
        }
    }

    // MARK: - Code Block & Inline Code Helpers

    private static func extractCodeBlock(from preElement: XMLElement) -> (code: String, language: String?) {
        var language = extractCodeLanguage(from: preElement)
        if language == nil, let codeChild = findFirstElement(named: "code", in: preElement) {
            language = extractCodeLanguage(from: codeChild)
        }
        var raw = ""
        collectPreformattedText(from: preElement, into: &raw)
        return (raw, language)
    }

    private static func collectPreformattedText(from node: XMLNode, into buffer: inout String) {
        switch node.kind {
        case .text:
            buffer += node.stringValue ?? ""
        case .element:
            guard let el = node as? XMLElement else { return }
            let tag = el.name?.lowercased() ?? ""
            if ignoredTags.contains(tag) { return }
            if tag == "br" {
                buffer += "\n"
                return
            }
            for child in el.children ?? [] {
                collectPreformattedText(from: child, into: &buffer)
            }
            if tag == "div" || tag == "p" {
                if !buffer.hasSuffix("\n") {
                    buffer += "\n"
                }
            }
        default:
            break
        }
    }

    private static func extractCodeLanguage(from element: XMLElement) -> String? {
        if let langAttr = element.attribute(forName: "data-language")?.stringValue?.trimmingCharacters(in: .whitespaces),
           !langAttr.isEmpty {
            return langAttr
        }
        guard let classAttr = element.attribute(forName: "class")?.stringValue else { return nil }
        for token in classAttr.split(whereSeparator: { $0.isWhitespace }) {
            let lower = token.lowercased()
            if lower.hasPrefix("language-") {
                let lang = String(token.dropFirst("language-".count))
                if !lang.isEmpty { return lang }
            } else if lower.hasPrefix("lang-") {
                let lang = String(token.dropFirst("lang-".count))
                if !lang.isEmpty { return lang }
            }
        }
        return nil
    }

    private static func wrapInlineCode(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .newlines)
        if trimmed.contains("`") {
            let padded = (trimmed.hasPrefix("`") || trimmed.hasSuffix("`")) ? " \(trimmed) " : trimmed
            return "``\(padded)``"
        }
        return "`\(trimmed)`"
    }

    // MARK: - CSS Style Helpers

    private static func parseInlineStyle(_ styleString: String?) -> [String: String] {
        guard let styleString, !styleString.isEmpty else { return [:] }
        var map: [String: String] = [:]
        for decl in styleString.split(separator: ";") {
            let parts = decl.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let val = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty && !val.isEmpty {
                map[key] = val
            }
        }
        return map
    }

    private static func isExplicitNormalWeight(_ value: String?) -> Bool {
        guard let value else { return false }
        if value == "normal" || value == "lighter" { return true }
        if let numeric = Int(value), numeric <= 400 { return true }
        return false
    }

    private static func isBoldWeight(_ value: String?) -> Bool {
        guard let value else { return false }
        if value == "bold" || value == "bolder" { return true }
        if let numeric = Int(value), numeric >= 600 { return true }
        return false
    }

    private static func isItalicStyle(_ value: String?) -> Bool {
        guard let value else { return false }
        return value == "italic" || value == "oblique"
    }

    private static func isStrikethroughStyle(_ style: [String: String]) -> Bool {
        let dec = style["text-decoration"] ?? style["text-decoration-line"] ?? ""
        return dec.contains("line-through")
    }

    private static func styleFontIsMonospace(_ fontFamily: String?) -> Bool {
        guard let fontFamily, !fontFamily.isEmpty else { return false }
        let monoHints = ["monospace", "menlo", "monaco", "consolas", "sf mono", "courier", "fira code", "jetbrains mono", "source code"]
        return monoHints.contains { fontFamily.contains($0) }
    }

    private static func containsBlockChildren(_ element: XMLElement) -> Bool {
        let blockTags: Set<String> = [
            "p", "div", "h1", "h2", "h3", "h4", "h5", "h6",
            "ul", "ol", "table", "blockquote", "pre", "hr", "section", "article"
        ]
        for child in element.children ?? [] {
            if let el = child as? XMLElement,
               let tag = el.name?.lowercased(),
               blockTags.contains(tag) {
                return true
            }
        }
        return false
    }

    private static func collapseHTMLWhitespace(_ raw: String) -> String {
        let replacedNBSP = raw.replacingOccurrences(of: "\u{00A0}", with: " ")
        return replacedNBSP.replacingOccurrences(of: #"[ \t\r\n]+"#, with: " ", options: .regularExpression)
    }

    private static func normalizeMarkdownOutput(_ raw: String) -> String {
        let normalizedNewlines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalizedNewlines.components(separatedBy: "\n")
        var cleaned: [String] = []
        var inCodeFence = false
        var consecutiveBlanks = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~~") {
                inCodeFence.toggle()
                consecutiveBlanks = 0
                cleaned.append(line)
                continue
            }
            if inCodeFence {
                cleaned.append(line)
                continue
            }
            if trimmed.isEmpty {
                consecutiveBlanks += 1
                if consecutiveBlanks <= 1 && !cleaned.isEmpty {
                    cleaned.append("")
                }
                continue
            }
            consecutiveBlanks = 0
            // Keep leading indentation for lists/blockquotes/code; strip trailing spaces only.
            let strippedTrailing = line.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
            if strippedTrailing.hasPrefix("  ") || strippedTrailing.hasPrefix("\t") {
                cleaned.append(strippedTrailing)
            } else {
                cleaned.append(strippedTrailing.trimmingCharacters(in: .whitespaces))
            }
        }

        while cleaned.last?.isEmpty == true {
            cleaned.removeLast()
        }
        return cleaned.joined(separator: "\n")
    }
}
