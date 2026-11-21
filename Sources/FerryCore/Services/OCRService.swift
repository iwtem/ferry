import CoreGraphics
import Foundation
import ImageIO
import Vision

/// A recognized text line and its normalized Vision bounding box (origin at bottom-left, 0...1).
public struct OCRTextBlock: Equatable, Sendable {
    public let text: String
    public let boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Errors produced during screenshot capture or on-device Vision OCR.
public enum OCRError: LocalizedError, Equatable, Sendable {
    case cancelled
    case invalidImage
    case noTextFound
    case permissionDenied
    case captureFailed(String)
    case recognitionFailed(String)

    public var errorDescription: String? {
        let lang = FerryLocalization.resolved
        switch self {
        case .cancelled:
            return FerryLocalization.text(zh: "已取消截图", en: "Screenshot cancelled.", in: lang)
        case .invalidImage:
            return FerryLocalization.text(zh: "无法读取截图图像", en: "Unable to read the captured image.", in: lang)
        case .noTextFound:
            return FerryLocalization.text(
                zh: "未在截图中识别到文字，请框选更清晰的区域重试。",
                en: "No text detected in the screenshot. Try selecting a clearer region.",
                in: lang
            )
        case .permissionDenied:
            return FerryLocalization.text(
                zh: "未能读取屏幕内容，请先授予「屏幕录制」权限后重试。",
                en: "Unable to capture screen content. Grant Screen Recording permission and try again.",
                in: lang
            )
        case .captureFailed(let detail):
            return FerryLocalization.text(
                zh: "截图失败：\(detail)",
                en: "Screenshot failed: \(detail)",
                in: lang
            )
        case .recognitionFailed(let detail):
            return FerryLocalization.text(
                zh: "文字识别失败：\(detail)",
                en: "Text recognition failed: \(detail)",
                in: lang
            )
        }
    }
}

/// Reconstructs clean reading order and paragraph breaks from Vision text observations.
public enum OCRTextFormatter {
    private struct VisualLine {
        var blocks: [OCRTextBlock]
        var minY: CGFloat
        var maxY: CGFloat
        var minX: CGFloat
        var maxX: CGFloat

        var midY: CGFloat { (minY + maxY) * 0.5 }
        var height: CGFloat { max(maxY - minY, 0.001) }
        var width: CGFloat { max(maxX - minX, 0) }

        var joinedText: String {
            let sorted = blocks.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            var output = ""
            for block in sorted {
                let piece = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !piece.isEmpty else { continue }
                output = OCRTextFormatter.appendInline(output, piece)
            }
            return output
        }
    }

    public static func format(_ rawBlocks: [OCRTextBlock]) -> String {
        let blocks = rawBlocks.compactMap { block -> OCRTextBlock? in
            let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return OCRTextBlock(text: trimmed, boundingBox: block.boundingBox)
        }
        guard !blocks.isEmpty else { return "" }

        // Sort top-to-bottom (Vision Y increases upward), then left-to-right.
        let sorted = blocks.sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.001 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        // Group horizontally aligned fragments into visual lines.
        var lines: [VisualLine] = []
        for block in sorted {
            let box = block.boundingBox
            if let idx = lines.firstIndex(where: { line in
                let overlap = min(line.maxY, box.maxY) - max(line.minY, box.minY)
                let minHeight = min(line.height, max(box.height, 0.001))
                return overlap >= minHeight * 0.45
                    || abs(line.midY - box.midY) <= minHeight * 0.45
            }) {
                lines[idx].blocks.append(block)
                lines[idx].minY = min(lines[idx].minY, box.minY)
                lines[idx].maxY = max(lines[idx].maxY, box.maxY)
                lines[idx].minX = min(lines[idx].minX, box.minX)
                lines[idx].maxX = max(lines[idx].maxX, box.maxX)
            } else {
                lines.append(VisualLine(
                    blocks: [block],
                    minY: box.minY,
                    maxY: box.maxY,
                    minX: box.minX,
                    maxX: box.maxX
                ))
            }
        }

        lines.sort { $0.midY > $1.midY }
        guard !lines.isEmpty else { return "" }

        let heights = lines.map(\.height).sorted()
        let medianHeight = heights[heights.count / 2]
        let maxWidth = lines.map(\.width).max() ?? 0

        var paragraphs: [String] = []
        var current = lines[0].joinedText

        for i in 1..<lines.count {
            let prev = lines[i - 1]
            let next = lines[i]
            let nextText = next.joinedText
            guard !nextText.isEmpty else { continue }

            if shouldStartNewParagraph(
                previous: prev,
                previousText: current,
                next: next,
                nextText: nextText,
                medianHeight: medianHeight,
                maxWidth: maxWidth
            ) {
                if !current.isEmpty {
                    paragraphs.append(current)
                }
                current = nextText
            } else {
                current = joinWrappedLine(current, nextText)
            }
        }

        if !current.isEmpty {
            paragraphs.append(current)
        }

        return paragraphs.joined(separator: "\n")
    }

    private static func shouldStartNewParagraph(
        previous: VisualLine,
        previousText: String,
        next: VisualLine,
        nextText: String,
        medianHeight: CGFloat,
        maxWidth: CGFloat
    ) -> Bool {
        // Large vertical gap between lines implies a paragraph or block break.
        let verticalGap = previous.minY - next.maxY
        if verticalGap > medianHeight * 0.85 {
            return true
        }

        // Bullet or numbered list items stay on their own line.
        if startsWithListMarker(nextText) {
            return true
        }

        // Notable horizontal indentation change (e.g. indented new paragraph or shifted column).
        if maxWidth > 0 && abs(next.minX - previous.minX) > medianHeight * 1.8 {
            return true
        }

        // Previous line was noticeably shorter than the block width and ended a sentence (or looked like a heading).
        if maxWidth > 0, previous.width < maxWidth * 0.72, endsWithSentenceBoundary(previousText) {
            return true
        }

        return false
    }

    private static func joinWrappedLine(_ previous: String, _ next: String) -> String {
        guard !previous.isEmpty else { return next }
        guard !next.isEmpty else { return previous }

        // De-hyphenate wrapped English words like "algo-" + "rithm" -> "algorithm".
        if previous.hasSuffix("-"),
           let beforeHyphen = previous.dropLast().last,
           beforeHyphen.isASCII && beforeHyphen.isLetter,
           let nextFirst = next.first,
           nextFirst.isASCII && nextFirst.isLowercase {
            return String(previous.dropLast()) + next
        }

        return appendInline(previous, next)
    }

    private static func appendInline(_ left: String, _ right: String) -> String {
        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }

        if let last = left.unicodeScalars.last,
           let first = right.unicodeScalars.first,
           isCJK(last) && isCJK(first) {
            return left + right
        }
        return left + " " + right
    }

    private static func startsWithListMarker(_ text: String) -> Bool {
        let bulletPrefixes = ["•", "·", "▪", "◦", "–", "—", "-", "*", "✓", "✔", "☐", "☑"]
        for prefix in bulletPrefixes where text.hasPrefix(prefix + " ") || text == prefix {
            return true
        }
        // Numbered list like "1. ", "2) ", "(1) "
        if text.range(of: #"^(\(\d+\)|\d+[\.\)])\s+"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func endsWithSentenceBoundary(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".?!。？！:：;；".contains(last)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F, // CJK Symbols & Punctuation
             0x3040...0x309F, // Hiragana
             0x30A0...0x30FF, // Katakana
             0x3400...0x4DBF, // CJK Extension A
             0x4E00...0x9FFF, // CJK Unified Ideographs
             0xAC00...0xD7AF, // Hangul Syllables
             0xF900...0xFAFF, // CJK Compatibility Ideographs
             0xFF00...0xFFEF: // Fullwidth Forms
            return true
        default:
            return false
        }
    }
}

/// On-device Apple Vision OCR service supporting multilingual screenshot text extraction.
public final class OCRService: Sendable {
    private static let preferredLanguages = [
        "zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES"
    ]

    public init() {}

    public func recognizeText(fromImageData data: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw OCRError.invalidImage
        }
        return try await recognizeText(from: cgImage)
    }

    public func recognizeText(from cgImage: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Self.performVisionRecognition(on: cgImage)
        }.value
    }

    private static func performVisionRecognition(on cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        if let supported = try? request.supportedRecognitionLanguages() {
            let filtered = preferredLanguages.filter { supported.contains($0) }
            if !filtered.isEmpty {
                request.recognitionLanguages = filtered
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        let blocks: [OCRTextBlock] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return OCRTextBlock(text: trimmed, boundingBox: observation.boundingBox)
        }

        let formatted = OCRTextFormatter.format(blocks)
        guard !formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OCRError.noTextFound
        }
        return formatted
    }
}
