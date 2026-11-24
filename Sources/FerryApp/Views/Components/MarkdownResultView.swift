import FerryCore
import SwiftUI

/// Renders translated output with structured Markdown layout (headings, emphasis,
/// lists, blockquotes, fenced code blocks, tables, links) or switches cleanly to
/// raw Markdown / plain text when toggled or when no Markdown structure is present.
public struct StructuredResultView: View {
    public let text: String
    public var fontSize: CGFloat = 14
    public var lineSpacing: CGFloat = 4
    public var showRawMarkdown: Bool = false

    public init(
        text: String,
        fontSize: CGFloat = 14,
        lineSpacing: CGFloat = 4,
        showRawMarkdown: Bool = false
    ) {
        self.text = text
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.showRawMarkdown = showRawMarkdown
    }

    public var body: some View {
        if showRawMarkdown {
            Text(text)
                .font(.system(size: max(12, fontSize - 1), design: .monospaced))
                .lineSpacing(max(3, lineSpacing - 0.5))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !MarkdownDocument.hasStructure(text) {
            Text(text)
                .font(.system(size: fontSize))
                .lineSpacing(lineSpacing)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let blocks = MarkdownDocument.parse(text)
            VStack(alignment: .leading, spacing: blockSpacing) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    blockView(block, isFirst: index == 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blockSpacing: CGFloat {
        fontSize >= 14.5 ? 9 : 7
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, isFirst: Bool) -> some View {
        switch block {
        case .heading(let level, let content):
            let headingSize = headingFontSize(for: level)
            let weight: Font.Weight = level <= 2 ? .bold : .semibold
            Text(inlineAttributed(content, size: headingSize, baseWeight: weight))
                .lineSpacing(max(2, lineSpacing - 1))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.top, isFirst ? 0 : (level <= 2 ? 4 : 2))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let content):
            Text(inlineAttributed(content, size: fontSize))
                .lineSpacing(lineSpacing)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        bulletMarker(for: item)
                        Text(inlineAttributed(item.text, size: fontSize))
                            .lineSpacing(lineSpacing)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(item.indentLevel) * 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(item.number).")
                            .font(.system(size: fontSize, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Stage.textSecondary)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(inlineAttributed(item.text, size: fontSize))
                            .lineSpacing(lineSpacing)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(item.indentLevel) * 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .blockquote(let lines):
            let quoteContent = lines.joined(separator: "\n")
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(FerryTheme.accent.opacity(0.62))
                    .frame(width: 2.5)
                Text(inlineAttributed(quoteContent, size: fontSize))
                    .lineSpacing(lineSpacing)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Stage.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: max(11.5, fontSize - 1.5), design: .monospaced))
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.top, (language?.isEmpty == false) ? 2 : 8)
                        .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Stage.wellFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Stage.controlStroke, lineWidth: 0.75)
            )

        case .table(let headers, let alignments, let rows):
            tableView(headers: headers, alignments: alignments, rows: rows)

        case .thematicBreak:
            Rectangle()
                .fill(Stage.hairline)
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func bulletMarker(for item: MarkdownBulletItem) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: max(11, fontSize - 2), weight: .medium))
                .foregroundStyle(checked ? FerryTheme.accentText : Stage.textSecondary)
                .frame(width: 14, alignment: .center)
        } else {
            Text(item.indentLevel % 2 == 0 ? "•" : "◦")
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Stage.textSecondary)
                .frame(width: 14, alignment: .center)
        }
    }

    private func tableView(
        headers: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    ) -> some View {
        let cellFontSize = max(12, fontSize - 1.5)
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { col, header in
                        let align = col < alignments.count ? alignments[col] : .left
                        Text(inlineAttributed(header, size: cellFontSize, baseWeight: .semibold))
                            .multilineTextAlignment(textAlignment(align))
                            .textSelection(.enabled)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: frameAlignment(align))
                            .overlay(alignment: .trailing) {
                                if col < headers.count - 1 {
                                    Rectangle().fill(Stage.hairline).frame(width: 1)
                                }
                            }
                    }
                }
                .background(Color.primary.opacity(0.055))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    GridRow {
                        ForEach(0..<headers.count, id: \.self) { col in
                            let cell = col < row.count ? row[col] : ""
                            let align = col < alignments.count ? alignments[col] : .left
                            Text(inlineAttributed(cell, size: cellFontSize))
                                .multilineTextAlignment(textAlignment(align))
                                .textSelection(.enabled)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5.5)
                                .frame(maxWidth: .infinity, alignment: frameAlignment(align))
                                .overlay(alignment: .top) {
                                    Rectangle().fill(Stage.hairline).frame(height: 1)
                                }
                                .overlay(alignment: .trailing) {
                                    if col < headers.count - 1 {
                                        Rectangle().fill(Stage.hairline).frame(width: 1)
                                    }
                                }
                        }
                    }
                    .background(rowIdx % 2 == 1 ? Color.primary.opacity(0.02) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Stage.controlStroke, lineWidth: 0.75)
            )
        }
    }

    private func headingFontSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize + 3.5
        case 2: return fontSize + 2.0
        case 3: return fontSize + 1.0
        default: return fontSize + 0.5
        }
    }

    private func frameAlignment(_ align: MarkdownTableAlignment) -> Alignment {
        switch align {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private func textAlignment(_ align: MarkdownTableAlignment) -> TextAlignment {
        switch align {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    // MARK: - Inline AttributedString Builder

    private func inlineAttributed(
        _ raw: String,
        size: CGFloat,
        baseWeight: Font.Weight = .regular
    ) -> AttributedString {
        let lines = raw.components(separatedBy: "\n")
        var combined = AttributedString()

        for (idx, line) in lines.enumerated() {
            if idx > 0 {
                combined.append(AttributedString("\n"))
            }
            let nodes = MarkdownDocument.parseInlines(line)
            combined.append(buildAttributed(
                nodes,
                size: size,
                baseWeight: baseWeight,
                bold: false,
                italic: false,
                strike: false,
                linkURL: nil
            ))
        }
        return combined
    }

    private func buildAttributed(
        _ nodes: [MarkdownInline],
        size: CGFloat,
        baseWeight: Font.Weight,
        bold: Bool,
        italic: Bool,
        strike: Bool,
        linkURL: URL?
    ) -> AttributedString {
        var output = AttributedString()

        for node in nodes {
            switch node {
            case .text(let s):
                var part = AttributedString(s)
                let effectiveWeight: Font.Weight = bold ? (baseWeight == .bold ? .bold : .semibold) : baseWeight
                var font = Font.system(size: size, weight: effectiveWeight)
                if italic {
                    font = font.italic()
                }
                part.font = font
                if strike {
                    part.strikethroughStyle = .single
                }
                if let linkURL {
                    part.link = linkURL
                    part.foregroundColor = FerryTheme.accentText
                    part.underlineStyle = .single
                }
                output.append(part)

            case .bold(let children):
                output.append(buildAttributed(
                    children, size: size, baseWeight: baseWeight,
                    bold: true, italic: italic, strike: strike, linkURL: linkURL
                ))

            case .italic(let children):
                output.append(buildAttributed(
                    children, size: size, baseWeight: baseWeight,
                    bold: bold, italic: true, strike: strike, linkURL: linkURL
                ))

            case .boldItalic(let children):
                output.append(buildAttributed(
                    children, size: size, baseWeight: baseWeight,
                    bold: true, italic: true, strike: strike, linkURL: linkURL
                ))

            case .strikethrough(let children):
                output.append(buildAttributed(
                    children, size: size, baseWeight: baseWeight,
                    bold: bold, italic: italic, strike: true, linkURL: linkURL
                ))

            case .code(let code):
                var part = AttributedString(" \(code) ")
                part.font = .system(size: max(11.5, size - 1), design: .monospaced)
                part.backgroundColor = Color.primary.opacity(0.075)
                if let linkURL {
                    part.link = linkURL
                    part.foregroundColor = FerryTheme.accentText
                }
                output.append(part)

            case .link(let label, let urlString):
                let url = MarkdownDocument.isSafeLinkURL(urlString) ? URL(string: urlString) : nil
                output.append(buildAttributed(
                    label, size: size, baseWeight: baseWeight,
                    bold: bold, italic: italic, strike: strike, linkURL: url
                ))
            }
        }

        return output
    }
}
