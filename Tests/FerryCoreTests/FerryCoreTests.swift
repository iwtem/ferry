import Foundation
import Testing
@testable import FerryCore

@Suite("FerryCore Tests")
struct FerryCoreTests {
    @Test("Auto language detection resolves Chinese to English and others to Chinese")
    func testAutoLanguageDetection() {
        #expect(TargetLanguage.auto.resolvedTarget(for: "你好，世界！") == .en)
        #expect(TargetLanguage.auto.resolvedTarget(for: "今天天气真不错，我们去散步吧") == .en)
        #expect(TargetLanguage.auto.resolvedTarget(for: "SwiftUI 是苹果推出的声明式 UI 框架") == .en)

        #expect(TargetLanguage.auto.resolvedTarget(for: "Hello, world!") == .zhCN)
        #expect(TargetLanguage.auto.resolvedTarget(for: "Machine learning models translate text fluently.") == .zhCN)
        #expect(TargetLanguage.auto.resolvedTarget(for: "こんにちは、元気ですか？") == .zhCN)
        #expect(TargetLanguage.auto.resolvedTarget(for: "안녕하세요, 반갑습니다") == .zhCN)
        #expect(TargetLanguage.ja.resolvedTarget(for: "Hello") == .ja)
    }

    @Test("SSEParser parses OpenAI streaming chunks and [DONE]")
    func testSSEParser() {
        let deltaLine = #"data: {"id":"1","choices":[{"index":0,"delta":{"content":"你好"}}]}"#
        #expect(SSEParser.parseLine(deltaLine) == .delta("你好"))

        let roleOnlyLine = #"data: {"id":"1","choices":[{"index":0,"delta":{"role":"assistant"}}]}"#
        #expect(SSEParser.parseLine(roleOnlyLine) == .ignore)

        #expect(SSEParser.parseLine("data: [DONE]") == .done)
        #expect(SSEParser.parseLine(": keep-alive") == .ignore)
        #expect(SSEParser.parseLine("") == .ignore)
    }

    @Test("DoubleCopyDetector triggers on rapid double press and respects cooldown")
    func testDoubleCopyDetector() {
        var detector = DoubleCopyDetector(maxInterval: 0.45, cooldown: 0.55)

        // Single press should not trigger
        #expect(detector.registerPress(at: 10.00) == false)
        // Second press within 0.45s triggers
        #expect(detector.registerPress(at: 10.30) == true)
        // Immediate third press within cooldown should not trigger
        #expect(detector.registerPress(at: 10.45) == false)

        // Too slow (> 0.45s) should not trigger
        #expect(detector.registerPress(at: 12.00) == false)
        #expect(detector.registerPress(at: 12.60) == false)
        // Pressing again quickly after 12.60 DOES trigger
        #expect(detector.registerPress(at: 12.90) == true)
    }

    @Test("ProviderProfile constructs valid chat completions URLs")
    func testProviderURLConstruction() {
        let deepseek = ProviderProfile.defaultProfile(for: .deepseek)
        #expect(deepseek.chatCompletionsURL?.absoluteString == "https://api.deepseek.com/v1/chat/completions")

        let bailian = ProviderProfile.defaultProfile(for: .bailian)
        #expect(bailian.chatCompletionsURL?.absoluteString == "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")

        let trailingSlash = ProviderProfile(baseURL: "https://example.com/v1///", model: "test")
        #expect(trailingSlash.chatCompletionsURL?.absoluteString == "https://example.com/v1/chat/completions")

        let alreadyFull = ProviderProfile(baseURL: "https://example.com/v1/chat/completions", model: "test")
        #expect(alreadyFull.chatCompletionsURL?.absoluteString == "https://example.com/v1/chat/completions")

        let customModelOverride = ProviderProfile(baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", customModel: "deepseek-v3.2")
        #expect(customModelOverride.effectiveModel == "deepseek-v3.2")
    }

    @Test("Model list parsing keeps chat models, drops embeddings/speech/image, sorts naturally")
    func testModelListParser() throws {
        let json = #"""
        {"object":"list","data":[
          {"id":"qwen-plus","object":"model"},
          {"id":"text-embedding-v3","object":"model"},
          {"id":"qwen-max","object":"model"},
          {"id":"cosyvoice-v1","object":"model"},
          {"id":"wanx2.1-t2i-turbo","object":"model"},
          {"id":"qwen2.5-72b-instruct","object":"model"},
          {"id":"qwen2.5-7b-instruct","object":"model"},
          {"id":"qwen-plus","object":"model"}
        ]}
        """#
        let models = try ModelListParser.parse(Data(json.utf8))
        #expect(models == ["qwen-max", "qwen-plus", "qwen2.5-7b-instruct", "qwen2.5-72b-instruct"])
    }

    @Test("Models URL is derived from the base URL")
    func testModelsURL() {
        #expect(ProviderProfile(baseURL: "https://api.deepseek.com/v1/", model: "x").modelsURL?.absoluteString
                == "https://api.deepseek.com/v1/models")
        #expect(ProviderProfile(baseURL: "http://localhost:11434/v1/chat/completions", model: "x").modelsURL?.absoluteString
                == "http://localhost:11434/v1/models")
        #expect(ProviderProfile(baseURL: "http://localhost:11434/v1/chat/completions", model: "x").chatCompletionsURL?.absoluteString
                == "http://localhost:11434/v1/chat/completions")
    }

    @Test("Profiles saved before fetchedModels existed still decode")
    func testLegacyProfileDecoding() throws {
        let legacy = #"{"baseURL":"https://api.deepseek.com/v1","model":"deepseek-chat","customModel":""}"#
        let profile = try JSONDecoder().decode(ProviderProfile.self, from: Data(legacy.utf8))
        #expect(profile.fetchedModels.isEmpty)
        #expect(profile.selectableModels(for: .deepseek) == ProviderKind.deepseek.recommendedModels)

        var fetched = profile
        fetched.fetchedModels = ["deepseek-reasoner"]
        #expect(fetched.selectableModels(for: .deepseek) == ["deepseek-chat", "deepseek-reasoner"])
    }

    @Test("qwen-mt models get translation_options and no system message")
    func testQwenMTPayload() throws {
        let payload = LLMTranslatorService.makePayload(
            text: "Gold prices crash", resolvedTarget: .zhCN, model: "qwen-mt-plus", temperature: 0.2, stream: true
        )
        let messages = try #require(payload["messages"] as? [[String: String]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] == "user")
        #expect(messages[0]["content"] == "Gold prices crash")
        let options = try #require(payload["translation_options"] as? [String: String])
        #expect(options["source_lang"] == "auto")
        #expect(options["target_lang"] == "Chinese")
        #expect(payload["temperature"] == nil)
    }

    @Test("Chat models get the translation prompt as a system message")
    func testChatPayload() throws {
        let payload = LLMTranslatorService.makePayload(
            text: "你好", resolvedTarget: .en, model: "deepseek-chat", temperature: 0.2, stream: true
        )
        let messages = try #require(payload["messages"] as? [[String: String]])
        // system prompt, two few-shot pairs, then the real request
        #expect(messages.map { $0["role"] } == ["system", "user", "assistant", "user", "assistant", "user"])
        #expect(messages[0]["content"]?.contains("native English") == true)
        #expect(messages[0]["content"]?.contains("translationese") == true)
        #expect(messages.last?["content"] == "Translate into English (output the translation only):\n\n你好")
        #expect(payload["translation_options"] == nil)
        #expect(payload["temperature"] as? Double == 0.2)

        let reasoner = LLMTranslatorService.makePayload(
            text: "你好", resolvedTarget: .en, model: "deepseek-reasoner", temperature: 0.2, stream: true
        )
        #expect(reasoner["temperature"] == nil)
    }

    @Test("Stream accumulator handles both delta and cumulative chunks")
    func testStreamAccumulator() {
        var delta = StreamTextAccumulator(cumulativeChunks: false)
        #expect(delta.append("今日") == "今日")
        #expect(delta.append("黄金") == "黄金")
        #expect(delta.text == "今日黄金")

        var cumulative = StreamTextAccumulator(cumulativeChunks: true)
        #expect(cumulative.append("今日") == "今日")
        #expect(cumulative.append("今日黄金") == "黄金")
        #expect(cumulative.append("今日黄金暴跌") == "暴跌")
        #expect(cumulative.text == "今日黄金暴跌")
        // A provider that actually sends deltas for an mt model still works.
        #expect(cumulative.append("。") == "。")
        #expect(cumulative.text == "今日黄金暴跌。")
    }

    @Test("Single words and short terms are detected for dictionary lookup")
    func testLookupTermDetection() {
        #expect(TranslationPrompt.isLookupTerm("raven"))
        #expect(TranslationPrompt.isLookupTerm("  ferry crossing \n"))
        #expect(TranslationPrompt.isLookupTerm("渡口"))
        #expect(TranslationPrompt.isLookupTerm("Patriot battery"))

        #expect(!TranslationPrompt.isLookupTerm("Gold prices crash today."))
        #expect(!TranslationPrompt.isLookupTerm("How are you?"))
        #expect(!TranslationPrompt.isLookupTerm("今天天气真不错，我们去散步吧"))
        #expect(!TranslationPrompt.isLookupTerm("the quick brown fox jumps"))
        #expect(!TranslationPrompt.isLookupTerm("https://example.com/path"))
        #expect(!TranslationPrompt.isLookupTerm("user_id"))
        #expect(!TranslationPrompt.isLookupTerm("line one\nline two"))
    }

    @Test("Word lookup uses the dictionary prompt only when enabled and the input is a term")
    func testDictionaryPayload() throws {
        let lookup = LLMTranslatorService.makePayload(
            text: "raven", resolvedTarget: .zhCN, model: "deepseek-chat", temperature: 0.2, stream: true, wordLookup: true
        )
        let lookupMessages = try #require(lookup["messages"] as? [[String: String]])
        #expect(lookupMessages[0]["content"]?.contains("bilingual dictionary") == true)
        #expect(lookupMessages.last?["content"] == "raven")

        let disabled = LLMTranslatorService.makePayload(
            text: "raven", resolvedTarget: .zhCN, model: "deepseek-chat", temperature: 0.2, stream: true, wordLookup: false
        )
        let disabledMessages = try #require(disabled["messages"] as? [[String: String]])
        #expect(disabledMessages[0]["content"]?.contains("professional translator") == true)

        let sentence = LLMTranslatorService.makePayload(
            text: "Ravens are smart birds.", resolvedTarget: .zhCN, model: "deepseek-chat", temperature: 0.2, stream: true, wordLookup: true
        )
        let sentenceMessages = try #require(sentence["messages"] as? [[String: String]])
        #expect(sentenceMessages[0]["content"]?.contains("professional translator") == true)

        // Dedicated MT models never get the dictionary prompt.
        let mt = LLMTranslatorService.makePayload(
            text: "raven", resolvedTarget: .zhCN, model: "qwen-mt-turbo", temperature: 0.2, stream: true, wordLookup: true
        )
        #expect(mt["translation_options"] != nil)
    }

    @Test("Settings files from older versions still load, with new fields defaulted")
    func testLegacyAppSettingsDecoding() throws {
        let legacy = #"""
        {"activeProvider":"bailian","defaultTargetLanguage":"en","doubleCopyEnabled":false,
         "doubleCopyIntervalMs":500,"desktopWidgetAlwaysOnTop":true,"temperature":0.3,
         "profiles":["bailian",{"baseURL":"https://dashscope.aliyuncs.com/compatible-mode/v1","model":"qwen-plus","customModel":""}]}
        """#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        #expect(settings.activeProvider == .bailian)
        #expect(settings.defaultTargetLanguage == .en)
        #expect(settings.doubleCopyEnabled == false)
        #expect(settings.doubleCopyIntervalMs == 500)
        #expect(settings.profiles[.bailian]?.model == "qwen-plus")
        #expect(settings.wordLookupEnabled == true)
        #expect(settings.speech == SpeechSettings())
    }

    @Test("CloudTTSService derives DashScope and OpenAI endpoints cleanly")
    func testCloudTTSEndpoints() {
        #expect(
            CloudTTSService.bailianTTSEndpoint(from: "https://dashscope.aliyuncs.com/compatible-mode/v1")?.absoluteString
            == "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
        )
        #expect(
            CloudTTSService.bailianTTSEndpoint(from: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")?.absoluteString
            == "https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
        )
        #expect(
            CloudTTSService.openAITTSEndpoint(from: "https://api.openai.com/v1/")?.absoluteString
            == "https://api.openai.com/v1/audio/speech"
        )
        #expect(
            CloudTTSService.openAITTSEndpoint(from: "https://proxy.example.com/v1/chat/completions")?.absoluteString
            == "https://proxy.example.com/v1/audio/speech"
        )
        #expect(
            CloudTTSService.upgradedAudioURL(from: "http://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/a.wav?Expires=123")?.absoluteString
            == "https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/a.wav?Expires=123"
        )
        #expect(
            CloudTTSService.upgradedAudioURL(from: "http://localhost:8000/a.wav")?.absoluteString
            == "http://localhost:8000/a.wav"
        )
    }

    @Test("Speech language detection respects hints and English accent")
    func testSpeechLanguageDetection() {
        #expect(LanguageDetection.speechLanguageCode(for: "你好世界", englishAccent: .us) == "zh-CN")
        #expect(LanguageDetection.speechLanguageCode(for: "Serendipity", englishAccent: .gb) == "en-GB")
        #expect(LanguageDetection.speechLanguageCode(for: "Hello", hint: .ja, englishAccent: .us) == "ja-JP")
        #expect(LanguageDetection.dashScopeLanguageType(for: "en-GB") == "English")
        #expect(LanguageDetection.dashScopeLanguageType(for: "zh-CN") == "Chinese")
    }
}
