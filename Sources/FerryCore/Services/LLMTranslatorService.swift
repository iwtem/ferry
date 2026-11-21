import Foundation

public enum TranslationError: LocalizedError, Sendable {
    case emptyInput
    case missingAPIKey(ProviderKind)
    case invalidBaseURL(String)
    case httpError(statusCode: Int, message: String)
    case networkError(String)
    case invalidResponse

    public var errorDescription: String? {
        let lang = FerryLocalization.resolved
        switch self {
        case .emptyInput:
            return FerryLocalization.text(
                zh: "请输入需要翻译的文本",
                en: "Please enter text to translate.",
                in: lang
            )
        case .missingAPIKey(let provider):
            return FerryLocalization.text(
                zh: "尚未配置 \(provider.shortName(in: .zhHans)) 的 API Key，请先打开「设置」填写。",
                en: "No API Key configured for \(provider.shortName(in: .en)). Open Settings to add one.",
                in: lang
            )
        case .invalidBaseURL(let url):
            return FerryLocalization.text(
                zh: "接口地址格式无效：\(url)",
                en: "Invalid endpoint URL: \(url)",
                in: lang
            )
        case .httpError(let statusCode, let message):
            switch statusCode {
            case 401:
                return FerryLocalization.text(
                    zh: "API Key 无效或未授权 (401)，请检查设置中的 Key 是否正确。",
                    en: "Invalid or unauthorized API Key (401). Please check your key in Settings.",
                    in: lang
                )
            case 402:
                return FerryLocalization.text(
                    zh: "账户余额不足 (402)，请检查模型服务商控制台余额。",
                    en: "Insufficient account balance (402). Please check your provider billing.",
                    in: lang
                )
            case 404:
                return FerryLocalization.text(
                    zh: "接口地址或模型名称不存在 (404)：\(message)",
                    en: "Endpoint or model not found (404): \(message)",
                    in: lang
                )
            case 429:
                return FerryLocalization.text(
                    zh: "请求过于频繁或触发限流 (429)，请稍后再试。",
                    en: "Too many requests or rate limited (429). Please try again shortly.",
                    in: lang
                )
            default:
                return FerryLocalization.text(
                    zh: "请求失败 (HTTP \(statusCode))：\(message)",
                    en: "Request failed (HTTP \(statusCode)): \(message)",
                    in: lang
                )
            }
        case .networkError(let message):
            return FerryLocalization.text(
                zh: "网络连接失败：\(message)",
                en: "Network error: \(message)",
                in: lang
            )
        case .invalidResponse:
            return FerryLocalization.text(
                zh: "服务端返回了无法解析的响应",
                en: "Received an unreadable response from the server.",
                in: lang
            )
        }
    }
}

public struct TranslationRequestConfig: Sendable {
    public let provider: ProviderKind
    public let profile: ProviderProfile
    public let apiKey: String
    public let temperature: Double
    /// Answer single words and short terms with a compact dictionary entry.
    public let wordLookup: Bool

    public init(
        provider: ProviderKind,
        profile: ProviderProfile,
        apiKey: String,
        temperature: Double = 0.2,
        wordLookup: Bool = false
    ) {
        self.provider = provider
        self.profile = profile
        self.apiKey = apiKey
        self.temperature = temperature
        self.wordLookup = wordLookup
    }
}

public final class LLMTranslatorService: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 45
            config.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: config)
        }
    }

    public func streamTranslate(
        text: String,
        targetLanguage: TargetLanguage,
        config: TranslationRequestConfig
    ) -> AsyncThrowingStream<String, Error> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTarget = targetLanguage.resolvedTarget(for: trimmed)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !trimmed.isEmpty else {
                        throw TranslationError.emptyInput
                    }

                    let request = try buildRequest(
                        text: trimmed,
                        resolvedTarget: resolvedTarget,
                        config: config,
                        stream: true
                    )

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw TranslationError.invalidResponse
                    }

                    if !(200...299).contains(httpResponse.statusCode) {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 600 { break }
                        }
                        let readable = Self.extractErrorMessage(from: errorBody)
                        throw TranslationError.httpError(statusCode: httpResponse.statusCode, message: readable)
                    }

                    var accumulator = StreamTextAccumulator(
                        cumulativeChunks: Self.isDedicatedTranslationModel(config.profile.effectiveModel)
                    )
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        switch SSEParser.parseLine(line) {
                        case .delta(let chunk):
                            let newText = accumulator.append(chunk)
                            if !newText.isEmpty {
                                continuation.yield(newText)
                            }
                        case .done:
                            continuation.finish()
                            return
                        case .ignore:
                            continue
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as TranslationError {
                    continuation.finish(throwing: error)
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: TranslationError.networkError(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func testConnection(config: TranslationRequestConfig) async throws -> String {
        let request = try buildRequest(
            text: "Hello",
            resolvedTarget: .zhCN,
            config: config,
            stream: false,
            allowWordLookup: false
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.httpError(
                statusCode: httpResponse.statusCode,
                message: Self.extractErrorMessage(from: body)
            )
        }

        struct NonStreamResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message?
            }
            let choices: [Choice]?
        }

        if let decoded = try? JSONDecoder().decode(NonStreamResponse.self, from: data),
           let content = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }
        return FerryLocalization.text(zh: "连接成功", en: "Connected")
    }

    /// Lists the provider's models via the OpenAI-compatible `GET {baseURL}/models` endpoint.
    /// Returns chat-capable model ids, sorted.
    public func fetchModels(config: TranslationRequestConfig) async throws -> [String] {
        let trimmedKey = try validatedAPIKey(for: config)
        guard let url = config.profile.modelsURL else {
            throw TranslationError.invalidBaseURL(config.profile.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TranslationError.networkError(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        if !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.httpError(
                statusCode: httpResponse.statusCode,
                message: Self.extractErrorMessage(from: body)
            )
        }
        guard let models = try? ModelListParser.parse(data) else {
            throw TranslationError.invalidResponse
        }
        return models
    }

    /// Returns the trimmed API key, or throws when one is required but missing.
    /// A key is optional only for a custom provider on localhost (e.g. Ollama).
    private func validatedAPIKey(for config: TranslationRequestConfig) throws -> String {
        let trimmedKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = config.profile.baseURL.lowercased()
        let isLocalhost = base.contains("localhost") || base.contains("127.0.0.1")
        if trimmedKey.isEmpty && !(config.provider == .custom && isLocalhost) {
            throw TranslationError.missingAPIKey(config.provider)
        }
        return trimmedKey
    }

    private func buildRequest(
        text: String,
        resolvedTarget: TargetLanguage,
        config: TranslationRequestConfig,
        stream: Bool,
        allowWordLookup: Bool = true
    ) throws -> URLRequest {
        let trimmedKey = try validatedAPIKey(for: config)

        guard let url = config.profile.chatCompletionsURL else {
            throw TranslationError.invalidBaseURL(config.profile.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let payload = Self.makePayload(
            text: text,
            resolvedTarget: resolvedTarget,
            model: config.profile.effectiveModel,
            temperature: config.temperature,
            stream: stream,
            wordLookup: config.wordLookup && allowWordLookup
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        return request
    }

    /// Dedicated machine-translation models (Alibaba qwen-mt-*) reject system messages and
    /// take the target language through `translation_options` instead of a prompt.
    static func isDedicatedTranslationModel(_ model: String) -> Bool {
        model.lowercased().contains("qwen-mt")
    }

    static func makePayload(
        text: String,
        resolvedTarget: TargetLanguage,
        model: String,
        temperature: Double,
        stream: Bool,
        wordLookup: Bool = false
    ) -> [String: Any] {
        var payload: [String: Any] = ["model": model, "stream": stream]

        if isDedicatedTranslationModel(model) {
            payload["messages"] = [["role": "user", "content": text]]
            payload["translation_options"] = [
                "source_lang": "auto",
                "target_lang": resolvedTarget.qwenMTLanguageName
            ]
            return payload
        }

        payload["messages"] = wordLookup && TranslationPrompt.isLookupTerm(text)
            ? TranslationPrompt.dictionaryMessages(term: text, target: resolvedTarget)
            : TranslationPrompt.textMessages(text: text, target: resolvedTarget)
        // Reasoning models (e.g. deepseek-reasoner) reject or ignore temperature.
        if !model.lowercased().contains("reasoner") {
            payload["temperature"] = temperature
        }
        return payload
    }

    private static func extractErrorMessage(from body: String) -> String {
        struct APIErrorWrapper: Decodable {
            struct APIErrorDetail: Decodable {
                let message: String?
            }
            let error: APIErrorDetail?
            let message: String?
        }

        if let data = body.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(APIErrorWrapper.self, from: data) {
            if let msg = decoded.error?.message, !msg.isEmpty {
                return msg
            }
            if let msg = decoded.message, !msg.isEmpty {
                return msg
            }
        }
        let compact = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? FerryLocalization.text(zh: "未知错误", en: "Unknown error") : String(compact.prefix(200))
    }
}

/// Turns streamed chunks into new text only. Most providers stream deltas, but qwen-mt
/// may resend the whole translation so far in every chunk; for those, only the unseen
/// suffix is passed on so the UI never shows repeated text.
struct StreamTextAccumulator {
    let cumulativeChunks: Bool
    private(set) var text = ""

    init(cumulativeChunks: Bool) {
        self.cumulativeChunks = cumulativeChunks
    }

    mutating func append(_ chunk: String) -> String {
        if cumulativeChunks && !text.isEmpty && chunk.hasPrefix(text) {
            let newPart = String(chunk.dropFirst(text.count))
            text = chunk
            return newPart
        }
        text += chunk
        return chunk
    }
}
