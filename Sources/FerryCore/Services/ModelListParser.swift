import Foundation

/// Parses the OpenAI-compatible `GET /models` response (`{"data": [{"id": "..."}]}`)
/// used by DeepSeek, 阿里百炼 compatible mode, OpenAI, OpenRouter and Ollama.
public enum ModelListParser {
    /// Model ids that clearly cannot do chat translation (embeddings, speech, images…).
    /// Providers such as 百炼 return hundreds of models of every kind from the same endpoint.
    static let nonChatMarkers = [
        "embedding", "embed", "rerank", "moderation",
        "tts", "asr", "whisper", "transcribe", "paraformer", "sensevoice", "sambert", "cosyvoice",
        "dall-e", "image", "wanx", "wan2", "flux", "stable-diffusion", "video"
    ]

    public static func parse(_ data: Data) throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]?
            let models: [Model]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let ids = (decoded.data ?? decoded.models ?? []).map(\.id)
        return filterAndSort(ids)
    }

    public static func filterAndSort(_ ids: [String]) -> [String] {
        let chatModels = ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { id in
                guard !id.isEmpty else { return false }
                let lower = id.lowercased()
                return !nonChatMarkers.contains { lower.contains($0) }
            }
        return Array(Set(chatModels)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
