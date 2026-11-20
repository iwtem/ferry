import Foundation

public enum SSEEvent: Equatable, Sendable {
    case delta(String)
    case done
    case ignore
}

public enum SSEParser {
    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta?
        }
        let choices: [Choice]?
    }

    /// Parses a single line from an OpenAI-compatible Server-Sent Events stream.
    public static func parseLine(_ rawLine: String) -> SSEEvent {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return .ignore }
        guard !line.hasPrefix(":") else { return .ignore }

        let payload: String
        if line.hasPrefix("data:") {
            payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else {
            return .ignore
        }

        if payload == "[DONE]" {
            return .done
        }

        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
              let content = chunk.choices?.first?.delta?.content,
              !content.isEmpty
        else {
            return .ignore
        }

        return .delta(content)
    }
}
