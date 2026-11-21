import Foundation

public enum CloudTTSError: LocalizedError, Sendable {
    case missingAPIKey(String)
    case invalidEndpoint(String)
    case httpError(Int, String)
    case invalidResponse(String)

    public var errorDescription: String? {
        let lang = FerryLocalization.resolved
        switch self {
        case .missingAPIKey(let provider):
            return FerryLocalization.text(
                zh: "请先在「模型」中配置 \(provider) 的 API Key。",
                en: "Please configure an API Key for \(provider) in Settings → Models first.",
                in: lang
            )
        case .invalidEndpoint(let message):
            return FerryLocalization.text(
                zh: "TTS 接口地址无效：\(message)",
                en: "Invalid TTS endpoint URL: \(message)",
                in: lang
            )
        case .httpError(let code, let detail):
            return FerryLocalization.text(
                zh: "云端语音合成失败（HTTP \(code)）：\(detail)",
                en: "Cloud TTS failed (HTTP \(code)): \(detail)",
                in: lang
            )
        case .invalidResponse(let detail):
            return FerryLocalization.text(
                zh: "无法解析云端语音响应：\(detail)",
                en: "Could not parse cloud TTS response: \(detail)",
                in: lang
            )
        }
    }
}

public struct CloudTTSRequest: Sendable, Hashable {
    public let engine: SpeechEngine
    public let text: String
    public let model: String
    public let voice: String
    public let speed: Double
    public let baseURL: String
    public let apiKey: String
    public let languageType: String?

    public init(
        engine: SpeechEngine,
        text: String,
        model: String,
        voice: String,
        speed: Double,
        baseURL: String,
        apiKey: String,
        languageType: String? = nil
    ) {
        self.engine = engine
        self.text = text
        self.model = model
        self.voice = voice
        self.speed = speed
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.languageType = languageType
    }
}

public actor CloudTTSService {
    private let session: URLSession
    private var cache: [String: Data] = [:]
    private var cacheOrder: [String] = []
    private let maxCacheEntries = 30

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func synthesize(_ request: CloudTTSRequest) async throws -> Data {
        let cleanedText = Self.sanitizeForSpeech(request.text)
        guard !cleanedText.isEmpty else {
            throw CloudTTSError.invalidResponse(
                FerryLocalization.text(zh: "朗读文本为空", en: "No text to speak")
            )
        }

        let cacheKey = [
            request.engine.rawValue,
            request.model,
            request.voice,
            String(format: "%.2f", request.speed),
            request.languageType ?? "",
            cleanedText
        ].joined(separator: "|")

        if let cached = cache[cacheKey] {
            return cached
        }

        let audioData: Data
        switch request.engine {
        case .bailian:
            audioData = try await synthesizeBailian(request, text: cleanedText)
        case .openAI:
            audioData = try await synthesizeOpenAI(request, text: cleanedText)
        case .system:
            throw CloudTTSError.invalidResponse(
                FerryLocalization.text(zh: "系统语音不通过云端接口合成", en: "System voice does not use cloud synthesis")
            )
        }

        storeCache(audioData, forKey: cacheKey)
        return audioData
    }

    // MARK: - Alibaba Bailian (DashScope Qwen-TTS)

    private func synthesizeBailian(_ request: CloudTTSRequest, text: String) async throws -> Data {
        let key = request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw CloudTTSError.missingAPIKey(ProviderKind.bailian.displayName)
        }
        guard let endpoint = Self.bailianTTSEndpoint(from: request.baseURL) else {
            throw CloudTTSError.invalidEndpoint(request.baseURL)
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var inputDict: [String: Any] = [
            "text": text,
            "voice": request.voice.isEmpty ? "Cherry" : request.voice
        ]
        if let lang = request.languageType, !lang.isEmpty {
            inputDict["language_type"] = lang
        }

        let body: [String: Any] = [
            "model": request.model.isEmpty ? "qwen3-tts-flash" : request.model,
            "input": inputDict
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)
        try validateHTTP(response: response, data: data)

        // Parse output.audio.url or output.audio.data (base64)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudTTSError.invalidResponse(
                FerryLocalization.text(zh: "返回不是有效的 JSON", en: "Response is not valid JSON")
            )
        }

        if let code = json["code"] as? String, !code.isEmpty {
            let msg = (json["message"] as? String) ?? code
            throw CloudTTSError.invalidResponse("\(code): \(msg)")
        }

        if let output = json["output"] as? [String: Any],
           let audio = output["audio"] as? [String: Any] {
            if let base64 = audio["data"] as? String,
               !base64.isEmpty,
               let decoded = Data(base64Encoded: base64) {
                return decoded
            }
            if let urlString = audio["url"] as? String,
               let audioURL = Self.upgradedAudioURL(from: urlString) {
                let (audioBytes, audioResp) = try await session.data(from: audioURL)
                try validateHTTP(response: audioResp, data: audioBytes)
                return audioBytes
            }
        }

        throw CloudTTSError.invalidResponse(
            FerryLocalization.text(zh: "响应中未包含音频地址或数据", en: "Response did not contain audio URL or data")
        )
    }

    // MARK: - OpenAI Compatible /audio/speech

    private func synthesizeOpenAI(_ request: CloudTTSRequest, text: String) async throws -> Data {
        let key = request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerURL = request.baseURL.lowercased()
        let isLocal = lowerURL.contains("localhost") || lowerURL.contains("127.0.0.1")
        guard !key.isEmpty || isLocal else {
            throw CloudTTSError.missingAPIKey(ProviderKind.custom.displayName)
        }
        guard let endpoint = Self.openAITTSEndpoint(from: request.baseURL) else {
            throw CloudTTSError.invalidEndpoint(request.baseURL)
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        if !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let clampedSpeed = min(max(request.speed, 0.25), 4.0)
        let body: [String: Any] = [
            "model": request.model.isEmpty ? "gpt-4o-mini-tts" : request.model,
            "input": text,
            "voice": request.voice.isEmpty ? "coral" : request.voice,
            "speed": clampedSpeed,
            "response_format": "mp3"
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)
        try validateHTTP(response: response, data: data)

        guard !data.isEmpty else {
            throw CloudTTSError.invalidResponse(
                FerryLocalization.text(zh: "服务端返回了空的音频流", en: "Server returned an empty audio stream")
            )
        }
        return data
    }

    // MARK: - URL Helpers & Text Sanitization

    public static func bailianTTSEndpoint(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed.isEmpty ? ProviderKind.bailian.defaultBaseURL : trimmed),
              let scheme = parsed.scheme,
              let host = parsed.host
        else {
            return URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation")
        }
        let portPart = parsed.port.map { ":\($0)" } ?? ""
        return URL(string: "\(scheme)://\(host)\(portPart)/api/v1/services/aigc/multimodal-generation/generation")
    }

    public static func openAITTSEndpoint(from baseURL: String) -> URL? {
        var cleaned = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            cleaned = ProviderKind.custom.defaultBaseURL
        }
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        if cleaned.hasSuffix("/chat/completions") {
            cleaned.removeLast("/chat/completions".count)
        }
        if cleaned.hasSuffix("/audio/speech") {
            return URL(string: cleaned)
        }
        return URL(string: "\(cleaned)/audio/speech")
    }

    /// Upgrades DashScope OSS `http://` audio download URLs to `https://` so macOS App Transport Security allows them.
    public static func upgradedAudioURL(from urlString: String) -> URL? {
        guard var components = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        if components.scheme?.lowercased() == "http" {
            let host = components.host?.lowercased() ?? ""
            if host != "localhost" && host != "127.0.0.1" {
                components.scheme = "https"
            }
        }
        return components.url
    }

    /// Cleans markdown markers and trims whitespace so TTS doesn't read raw syntax aloud.
    public static func sanitizeForSpeech(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip common markdown emphasis & heading markers
        for token in ["**", "__", "```", "`", "### ", "## ", "# "] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internal Helpers

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let detail = extractErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw CloudTTSError.httpError(http.statusCode, detail)
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw?.isEmpty == false ? String(raw!.prefix(180)) : nil
        }
        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
            return msg
        }
        if let msg = json["message"] as? String {
            return msg
        }
        return nil
    }

    private func storeCache(_ data: Data, forKey key: String) {
        if cache[key] == nil {
            cacheOrder.append(key)
        }
        cache[key] = data
        while cacheOrder.count > maxCacheEntries {
            let oldest = cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}
