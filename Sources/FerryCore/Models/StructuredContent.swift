import Foundation

/// Tracks the origin format of a translation input so output rendering,
/// preprocessing, and clipboard write-back can match the user's source cleanly.
public enum SourceContentFormat: String, Codable, Equatable, Sendable {
    /// Unstructured plain text.
    case plainText
    /// Plain text that already contains Markdown structure (e.g. Obsidian, VS Code, GitHub).
    case markdown
    /// Captured from rich clipboard content (HTML / RTF) and normalized to Markdown for translation.
    case richText
}

/// Output format written to the clipboard on copy or in-place replacement.
public enum OutputCopyFormat: String, CaseIterable, Equatable, Sendable {
    /// Automatically matches the source format:
    /// rich-text sources write HTML + RTF + plain text; Markdown sources write raw Markdown;
    /// plain-text sources write plain text.
    case auto
    /// Writes HTML + RTF + clean plain-text fallback to the pasteboard.
    case richText
    /// Writes raw Markdown text (`.string`) to the pasteboard.
    case markdown
    /// Strips Markdown syntax and writes clean plain text (`.string`) to the pasteboard.
    case plainText
}

/// Text captured from the clipboard or selection along with its detected structural format.
public struct CapturedContent: Equatable, Sendable {
    public let text: String
    public let format: SourceContentFormat

    public init(text: String, format: SourceContentFormat = .plainText) {
        self.text = text
        self.format = format
    }
}
