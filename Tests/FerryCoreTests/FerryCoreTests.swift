import CoreGraphics
import CoreText
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
        #expect(settings.pdfLineBreakFixEnabled == true)
        #expect(settings.translationCacheEnabled == true)
        #expect(settings.speech == SpeechSettings())
        #expect(settings.language == .system)
        #expect(settings.quickTranslateShortcutEnabled == true)
        #expect(settings.quickTranslateShortcut == .defaultQuickTranslate)
        #expect(settings.mainWindowShortcutEnabled == true)
        #expect(settings.mainWindowShortcut == .defaultMainWindow)
        #expect(settings.screenshotOCREnabled == true)
        #expect(settings.screenshotOCRShortcut == .defaultScreenshotOCR)
        #expect(settings.selectionShortcutEnabled == true)
        #expect(settings.selectionShortcut == .defaultSelectionTranslate)
        #expect(settings.autoCheckForUpdates == true)
        #expect(settings.autoDownloadUpdates == true)
        #expect(settings.realtimeUpdatePushEnabled == true)
        #expect(settings.secondaryModel == nil)
        #expect(settings.skippedUpdateVersion == nil)
    }

    @Test("AppLanguage resolves explicit overrides and system preferred languages")
    func testAppLanguageResolution() {
        #expect(ResolvedAppLanguage.resolve(.zhHans, preferredLanguages: ["en-US"]) == .zhHans)
        #expect(ResolvedAppLanguage.resolve(.en, preferredLanguages: ["zh-Hans-CN"]) == .en)

        #expect(ResolvedAppLanguage.resolve(.system, preferredLanguages: ["zh-Hans-CN", "en-US"]) == .zhHans)
        #expect(ResolvedAppLanguage.resolve(.system, preferredLanguages: ["zh-Hant-TW", "en-US"]) == .zhHans)
        #expect(ResolvedAppLanguage.resolve(.system, preferredLanguages: ["en-US", "zh-Hans-CN"]) == .en)
        #expect(ResolvedAppLanguage.resolve(.system, preferredLanguages: ["ja-JP", "zh-Hans-CN"]) == .zhHans)
        #expect(ResolvedAppLanguage.resolve(.system, preferredLanguages: ["ja-JP", "en-GB"]) == .en)
        #expect(ResolvedAppLanguage.resolve(.system, preferredLanguages: ["fr-FR"]) == .en)
        #expect(ResolvedAppLanguage.resolve(.system, preferredLanguages: []) == .en)
    }

    @Test("Localized model display names and errors reflect Chinese and English")
    func testLocalizedModelStrings() {
        #expect(AppLanguage.system.displayName(in: .zhHans) == "跟随系统")
        #expect(AppLanguage.system.displayName(in: .en) == "System")
        #expect(AppLanguage.zhHans.displayName(in: .en) == "简体中文")
        #expect(AppLanguage.en.displayName(in: .zhHans) == "English")

        #expect(AppearanceMode.system.displayName(in: .zhHans) == "跟随系统")
        #expect(AppearanceMode.dark.displayName(in: .en) == "Dark")

        #expect(ProviderKind.bailian.shortName(in: .zhHans) == "阿里百炼")
        #expect(ProviderKind.bailian.shortName(in: .en) == "Bailian")
        #expect(ProviderKind.custom.shortName(in: .en) == "Custom")

        #expect(TargetLanguage.auto.displayName(in: .zhHans) == "自动 (中↔英)")
        #expect(TargetLanguage.auto.displayName(in: .en) == "Auto (Zh↔En)")
        #expect(TargetLanguage.auto.shortName(in: .en) == "Zh↔En")
        #expect(TargetLanguage.zhCN.shortName(in: .en) == "Chinese")

        #expect(EnglishAccent.us.displayName(in: .en) == "American (US)")
        #expect(EnglishAccent.gb.displayName(in: .zhHans) == "英式英语 (UK)")

        let previous = FerryLocalization.languageSetting
        defer { FerryLocalization.languageSetting = previous }

        FerryLocalization.languageSetting = .en
        #expect(TranslationError.missingAPIKey(.deepseek).errorDescription?.contains("API Key") == true)
        #expect(TranslationError.httpError(statusCode: 401, message: "bad").errorDescription?.contains("401") == true)
        #expect(CloudTTSError.missingAPIKey("Bailian").errorDescription?.contains("API Key") == true)

        FerryLocalization.languageSetting = .zhHans
        #expect(TranslationError.missingAPIKey(.deepseek).errorDescription?.contains("尚未配置") == true)
        #expect(CloudTTSError.missingAPIKey("阿里百炼").errorDescription?.contains("请先在") == true)
    }

    @Test("LanguageDetection displayName localizes for Chinese and English")
    func testLocalizedLanguageDetectionDisplayName() {
        let zhName = LanguageDetection.displayName(for: "This is a clear English sentence for testing.", in: .zhHans)
        let enName = LanguageDetection.displayName(for: "This is a clear English sentence for testing.", in: .en)
        #expect(zhName == "英语")
        #expect(enName == "English")

        let zhForChinese = LanguageDetection.displayName(for: "今天天气真不错，我们去公园散步吧。", in: .zhHans)
        let enForChinese = LanguageDetection.displayName(for: "今天天气真不错，我们去公园散步吧。", in: .en)
        #expect(zhForChinese == "简体中文")
        #expect(enForChinese == "Simplified Chinese")
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

    @Test("HotkeyShortcut formats keycaps and enforces primary modifiers")
    func testHotkeyShortcut() throws {
        let def = HotkeyShortcut.defaultScreenshotOCR
        #expect(def.isValid)
        #expect(def.displayTokens == ["⌥", "⇧", "S"])
        #expect(def.displayString == "⌥⇧S")

        let shiftOnly = HotkeyShortcut(keyCode: 1, modifiers: [.shift])
        #expect(!shiftOnly.isValid)

        let noMod = HotkeyShortcut(keyCode: 1, modifiers: [])
        #expect(!noMod.isValid)

        let unknownKey = HotkeyShortcut(keyCode: 999, modifiers: [.command])
        #expect(!unknownKey.isValid)

        let cmdShift = HotkeyShortcut(keyCode: 2, modifiers: [.command, .control, .shift])
        #expect(cmdShift.isValid)
        #expect(cmdShift.displayString == "⌃⇧⌘D")

        let data = try JSONEncoder().encode(cmdShift)
        let decoded = try JSONDecoder().decode(HotkeyShortcut.self, from: data)
        #expect(decoded == cmdShift)

        // Default global hotkeys are all valid, distinct, and have unique Carbon IDs
        #expect(HotkeyShortcut.defaultQuickTranslate.displayString == "⌥Space")
        #expect(HotkeyShortcut.defaultMainWindow.displayString == "⌥⇧F")
        #expect(HotkeyShortcut.defaultSelectionTranslate.displayString == "⌥⇧R")
        #expect(HotkeyShortcut.defaultScreenshotOCR.displayString == "⌥⇧S")

        let allActions = GlobalHotkeyAction.allCases
        #expect(Set(allActions.map(\.carbonID)).count == allActions.count)
        #expect(Set(allActions.map(\.defaultShortcut)).count == allActions.count)

        var settings = AppSettings()
        #expect(settings.conflictingHotkeyActions().isEmpty)

        // Duplicate enabled shortcuts are flagged for both actions
        settings.mainWindowShortcut = .defaultQuickTranslate
        #expect(settings.conflictingHotkeyActions() == [.quickTranslate, .mainWindow])

        // Disabling one side clears the conflict
        settings.mainWindowShortcutEnabled = false
        #expect(settings.conflictingHotkeyActions().isEmpty)
    }

    @Test("OCRTextFormatter sorts lines, joins wrapped paragraphs, de-hyphenates, and preserves breaks")
    func testOCRTextFormatter() {
        // Wrapped English paragraph with hyphenated word and out-of-order observations
        let englishBlocks = [
            OCRTextBlock(text: "rithm for fast", boundingBox: CGRect(x: 0.05, y: 0.68, width: 0.70, height: 0.06)),
            OCRTextBlock(text: "We design a new algo-", boundingBox: CGRect(x: 0.05, y: 0.78, width: 0.78, height: 0.06)),
            OCRTextBlock(text: "translation.", boundingBox: CGRect(x: 0.05, y: 0.58, width: 0.35, height: 0.06)),
            // Large vertical gap -> new paragraph
            OCRTextBlock(text: "Second paragraph starts here.", boundingBox: CGRect(x: 0.05, y: 0.35, width: 0.75, height: 0.06)),
            // Bullet item -> new line
            OCRTextBlock(text: "• Item one", boundingBox: CGRect(x: 0.05, y: 0.25, width: 0.40, height: 0.06))
        ]
        let formattedEnglish = OCRTextFormatter.format(englishBlocks)
        #expect(formattedEnglish == "We design a new algorithm for fast translation.\nSecond paragraph starts here.\n• Item one")

        // Wrapped CJK lines join without inserting spaces
        let cjkBlocks = [
            OCRTextBlock(text: "渡是一款轻量优雅的", boundingBox: CGRect(x: 0.1, y: 0.70, width: 0.75, height: 0.08)),
            OCRTextBlock(text: "桌面大模型翻译工具。", boundingBox: CGRect(x: 0.1, y: 0.59, width: 0.72, height: 0.08))
        ]
        #expect(OCRTextFormatter.format(cjkBlocks) == "渡是一款轻量优雅的桌面大模型翻译工具。")

        // Two fragments on the same horizontal visual line are sorted left-to-right
        let sameLineBlocks = [
            OCRTextBlock(text: "world", boundingBox: CGRect(x: 0.45, y: 0.50, width: 0.25, height: 0.08)),
            OCRTextBlock(text: "Hello", boundingBox: CGRect(x: 0.10, y: 0.505, width: 0.25, height: 0.08))
        ]
        #expect(OCRTextFormatter.format(sameLineBlocks) == "Hello world")
    }

    @Test("SemanticVersion parses tags and compares versions including prereleases")
    func testSemanticVersionComparison() throws {
        let v010 = try #require(SemanticVersion(parsing: "0.1.0"))
        let v020Beta = try #require(SemanticVersion(parsing: "v0.2.0-beta.1"))
        let v020 = try #require(SemanticVersion(parsing: "v0.2.0"))
        let v0100 = try #require(SemanticVersion(parsing: "0.10.0"))
        let v10 = try #require(SemanticVersion(parsing: "1.0"))

        #expect(v010 < v020Beta)
        #expect(v020Beta < v020)
        #expect(v020 < v0100)
        #expect(v0100 < v10)
        #expect(v10.description == "1.0.0")
        #expect(v020Beta.description == "0.2.0-beta.1")
        #expect(SemanticVersion(parsing: "not-a-version") == nil)
    }

    @Test("UpdateFeedParser extracts GitHub Release zip asset, checksum URL, and SHA-256")
    func testUpdateFeedParser() throws {
        let digestHex = String(repeating: "a1b2c3d4", count: 8)
        let json = """
        {
          "tag_name": "v0.2.0",
          "name": "渡 Ferry v0.2.0",
          "body": "Added Screenshot OCR & Auto-Update\\n\\nSHA-256: `\(digestHex)`",
          "html_url": "https://github.com/iwtem/ferry/releases/tag/v0.2.0",
          "draft": false,
          "prerelease": false,
          "published_at": "2026-11-20T12:00:00Z",
          "assets": [
            {
              "name": "Ferry-0.2.0.zip.sha256",
              "browser_download_url": "https://github.com/iwtem/ferry/releases/download/v0.2.0/Ferry-0.2.0.zip.sha256",
              "size": 84
            },
            {
              "name": "Ferry-0.2.0.zip",
              "browser_download_url": "https://github.com/iwtem/ferry/releases/download/v0.2.0/Ferry-0.2.0.zip",
              "size": 4194304,
              "digest": "sha256:\(digestHex.uppercased())"
            }
          ]
        }
        """

        let info = try UpdateFeedParser.parseLatestRelease(from: Data(json.utf8))
        #expect(info.version == SemanticVersion(major: 0, minor: 2, patch: 0))
        #expect(info.assetFileName == "Ferry-0.2.0.zip")
        #expect(info.assetSize == 4_194_304)
        #expect(info.sha256 == digestHex)
        #expect(info.checksumURL?.absoluteString.hasSuffix("Ferry-0.2.0.zip.sha256") == true)
        #expect(info.publishedAt != nil)
        #expect(UpdateFeedParser.latestReleaseEndpoint(for: "iwtem/ferry")?.absoluteString
                == "https://api.github.com/repos/iwtem/ferry/releases/latest")
        #expect(UpdateFeedParser.parseSHA256(from: "\(digestHex)  Ferry-0.2.0.zip") == digestHex)
        #expect(UpdateFeedParser.parseSHA256(from: "too-short-abc") == nil)
    }

    @Test("UpdatePushParser handles ntfy SSE control frames and release wake-up messages")
    func testUpdatePushParser() {
        #expect(UpdatePushParser.parseSSELine(#"data: {"id":"1","event":"open","topic":"ferry"}"#) == .connected)
        #expect(UpdatePushParser.parseSSELine(#"data: {"id":"2","event":"keepalive","topic":"ferry"}"#) == .keepalive)
        #expect(UpdatePushParser.parseSSELine(": comment") == .ignore)
        #expect(UpdatePushParser.parseSSELine("event: open") == .ignore)

        let ntfyMsg = #"data: {"id":"3","event":"message","topic":"ferry","message":"0.2.1"}"#
        #expect(UpdatePushParser.parseSSELine(ntfyMsg) == .releaseAvailable(versionHint: SemanticVersion(major: 0, minor: 2, patch: 1)))

        let customJSON = #"data: {"version":"v0.3.0-beta.1"}"#
        #expect(UpdatePushParser.parseSSELine(customJSON) == .releaseAvailable(versionHint: SemanticVersion(major: 0, minor: 3, patch: 0, prerelease: "beta.1")))

        #expect(UpdatePushParser.parseSSELine("data: v0.2.2") == .releaseAvailable(versionHint: SemanticVersion(major: 0, minor: 2, patch: 2)))
        #expect(UpdatePushParser.parseSSELine("data: check-now") == .releaseAvailable(versionHint: nil))
    }

    @Test("TextPreprocessor cleans wrapped PDF line breaks and hyphenation while preserving structure")
    func testPDFLineBreakPreprocessor() {
        let englishPDF = """
        We introduce a novel algo-
        rithm for efficient trans-
        former inference on edge devices.

        Key findings:
        • Faster decoding with GPT-
        4 scale models.
        • Lower memory footprint.

        ```swift
        let a = 1
        let b = 2
        ```
        """
        let cleanedEnglish = TextPreprocessor.cleanPDFLineBreaks(englishPDF)
        #expect(cleanedEnglish.contains("We introduce a novel algorithm for efficient transformer inference on edge devices."))
        #expect(cleanedEnglish.contains("Key findings:\n• Faster decoding with GPT-4 scale models.\n• Lower memory footprint."))
        #expect(cleanedEnglish.contains("```swift\nlet a = 1\nlet b = 2\n```"))

        let cjkPDF = "在本文中，我们提出了一种高效的\n端侧大语言模型推理框架，能够显著\n降低显存占用。"
        #expect(TextPreprocessor.cleanPDFLineBreaks(cjkPDF) == "在本文中，我们提出了一种高效的端侧大语言模型推理框架，能够显著降低显存占用。")
    }

    @Test("Writing modes preserve source language on .auto, skip word lookup, and build dedicated prompts")
    func testWritingModePayloadsAndRecords() throws {
        #expect(TranslationMode.translate.isWritingMode == false)
        #expect(TranslationMode.polish.preservesSourceLanguage(for: .auto) == true)
        #expect(TranslationMode.polish.preservesSourceLanguage(for: .en) == false)
        #expect(TranslationMode.translate.preservesSourceLanguage(for: .auto) == false)

        // Polish mode with nil target (auto) preserves source language and never triggers dictionary lookup
        let polishPayload = LLMTranslatorService.makePayload(
            text: "raven",
            resolvedTarget: nil,
            model: "deepseek-chat",
            temperature: 0.2,
            stream: true,
            wordLookup: true,
            mode: .polish
        )
        let polishMessages = try #require(polishPayload["messages"] as? [[String: String]])
        #expect(polishMessages[0]["content"]?.contains("original language") == true)
        #expect(polishMessages[0]["content"]?.contains("bilingual dictionary") == false)

        // Concise mode with explicit target language translates & rewrites directly into that language
        let conciseEN = LLMTranslatorService.makePayload(
            text: "麻烦尽快帮我看一下这个 PR",
            resolvedTarget: .en,
            model: "deepseek-chat",
            temperature: 0.2,
            stream: true,
            wordLookup: false,
            mode: .concise
        )
        let conciseMessages = try #require(conciseEN["messages"] as? [[String: String]])
        #expect(conciseMessages[0]["content"]?.contains("workplace communication") == true)
        #expect(conciseMessages[0]["content"]?.contains("English") == true)

        // Grammar & Academic modes emit their specialized system prompts
        let grammarPayload = LLMTranslatorService.makePayload(
            text: "He go to work.",
            resolvedTarget: nil,
            model: "deepseek-chat",
            temperature: 0.2,
            stream: false,
            mode: .grammar
        )
        let grammarMessages = try #require(grammarPayload["messages"] as? [[String: String]])
        #expect(grammarMessages[0]["content"]?.contains("proofreader") == true)

        let academicPayload = LLMTranslatorService.makePayload(
            text: "This works well.",
            resolvedTarget: nil,
            model: "deepseek-chat",
            temperature: 0.2,
            stream: false,
            mode: .academic
        )
        let academicMessages = try #require(academicPayload["messages"] as? [[String: String]])
        #expect(academicMessages[0]["content"]?.contains("academic") == true)

        // Legacy TranslationRecord without `mode` field decodes cleanly as `.translate`
        let legacyRecordJSON = #"""
        {"id":"11111111-1111-1111-1111-111111111111","sourceText":"Hello","translatedText":"你好",
         "targetLanguage":"auto","resolvedLanguage":"zh-CN","provider":"deepseek","model":"deepseek-chat",
         "createdAt":0}
        """#
        let decodedRecord = try JSONDecoder().decode(TranslationRecord.self, from: Data(legacyRecordJSON.utf8))
        #expect(decodedRecord.mode == .translate)
    }

    @Test("TranslationLRUCache promotes hits, evicts least-recently-used, and round-trips order")
    func testTranslationLRUCache() throws {
        func key(_ text: String) -> TranslationCacheKey {
            TranslationCacheKey(
                sourceText: text,
                resolvedTarget: .zhCN,
                mode: .translate,
                provider: .deepseek,
                model: "deepseek-chat",
                endpoint: ProviderKind.deepseek.defaultBaseURL,
                wordLookup: false
            )
        }

        var cache = TranslationLRUCache(capacity: 3)
        #expect(cache.isEmpty)
        #expect(cache.get(key("missing")) == nil)
        #expect(cache.hitCount == 0)

        cache.set("一", for: key("one"))
        cache.set("二", for: key("two"))
        cache.set("三", for: key("three"))
        #expect(cache.count == 3)
        #expect(cache.orderedEntries().map(\.key.sourceText) == ["three", "two", "one"])

        // Access "one" -> promotes it to MRU, making "two" the LRU entry
        let hit = cache.get(key("one"))
        #expect(hit?.translatedText == "一")
        #expect(cache.hitCount == 1)
        #expect(cache.orderedEntries().map(\.key.sourceText) == ["one", "three", "two"])

        // Peek does not mutate order or hitCount
        #expect(cache.peek(key("two"))?.translatedText == "二")
        #expect(cache.hitCount == 1)
        #expect(cache.orderedEntries().map(\.key.sourceText) == ["one", "three", "two"])

        // Inserting a 4th item evicts "two" (LRU)
        cache.set("四", for: key("four"))
        #expect(cache.count == 3)
        #expect(cache.peek(key("two")) == nil)
        #expect(cache.orderedEntries().map(\.key.sourceText) == ["four", "one", "three"])

        // Updating an existing item replaces its text and moves it to MRU
        cache.set("参", for: key("three"))
        #expect(cache.count == 3)
        #expect(cache.peek(key("three"))?.translatedText == "参")
        #expect(cache.orderedEntries().map(\.key.sourceText) == ["three", "four", "one"])

        // Removing head, middle, and tail works cleanly and reuses slots
        #expect(cache.remove(key("four"))?.translatedText == "四")
        #expect(cache.orderedEntries().map(\.key.sourceText) == ["three", "one"])
        #expect(cache.remove(key("three"))?.translatedText == "参")
        #expect(cache.orderedEntries().map(\.key.sourceText) == ["one"])
        cache.set("五", for: key("five"))
        #expect(cache.orderedEntries().map(\.key.sourceText) == ["five", "one"])

        // Empty or excessively long entries are ignored
        cache.set("   ", for: key("blank"))
        cache.set("ok", for: key(""))
        let huge = String(repeating: "a", count: TranslationLRUCache.maxCacheableTextLength + 1)
        cache.set("too big", for: key(huge))
        #expect(cache.count == 2)

        // JSON persistence round-trip preserves MRU-to-LRU order and respects capacity
        let encoded = try JSONEncoder().encode(cache.orderedEntries())
        let decoded = try JSONDecoder().decode([TranslationCacheEntry].self, from: encoded)
        var restored = TranslationLRUCache(capacity: 2)
        restored.load(entries: decoded + decoded) // duplicate entries ignored
        #expect(restored.count == 2)
        #expect(restored.orderedEntries().map(\.key.sourceText) == ["five", "one"])

        // Capacity 1 edge case
        var single = TranslationLRUCache(capacity: 1)
        single.set("A", for: key("a"))
        single.set("A2", for: key("a"))
        #expect(single.count == 1)
        #expect(single.get(key("a"))?.translatedText == "A2")
        single.set("B", for: key("b"))
        #expect(single.count == 1)
        #expect(single.peek(key("a")) == nil)
        #expect(single.peek(key("b"))?.translatedText == "B")
        single.clear()
        #expect(single.isEmpty)
        #expect(single.hitCount == 0)
    }

    @Test("TranslationCacheKey canonicalizes auto target, endpoints, and word lookup applicability")
    func testTranslationCacheKeyCanonicalization() {
        let profile = ProviderProfile(
            baseURL: "https://api.deepseek.com/v1/chat/completions",
            model: "deepseek-chat"
        )
        let profileSlash = ProviderProfile(
            baseURL: "https://api.deepseek.com/v1///",
            model: "deepseek-chat"
        )
        let cfgLookup = TranslationRequestConfig(
            provider: .deepseek, profile: profile, apiKey: "sk-test", wordLookup: true, mode: .translate
        )
        let cfgNoLookup = TranslationRequestConfig(
            provider: .deepseek, profile: profileSlash, apiKey: "sk-test", wordLookup: false, mode: .translate
        )

        // Auto-resolved English -> zhCN matches explicit zhCN, and endpoint/whitespace normalize identically
        let autoSentence = TranslationCacheKey.make(text: "  Hello, how are you? \n", targetLanguage: .auto, config: cfgLookup)
        let explicitSentence = TranslationCacheKey.make(text: "Hello, how are you?", targetLanguage: .zhCN, config: cfgNoLookup)
        #expect(autoSentence == explicitSentence)
        #expect(autoSentence.wordLookup == false)

        // Single lookup term distinguishes wordLookup enabled vs disabled
        let wordWithDict = TranslationCacheKey.make(text: "raven", targetLanguage: .auto, config: cfgLookup)
        let wordPlain = TranslationCacheKey.make(text: "raven", targetLanguage: .zhCN, config: cfgNoLookup)
        #expect(wordWithDict != wordPlain)
        #expect(wordWithDict.wordLookup == true)
        #expect(wordPlain.wordLookup == false)

        // Writing mode with .auto preserves source language (resolvedTarget == nil), distinct from explicit .en
        let polishCfg = TranslationRequestConfig(
            provider: .deepseek, profile: profile, apiKey: "sk-test", wordLookup: true, mode: .polish
        )
        let polishAuto = TranslationCacheKey.make(text: "raven", targetLanguage: .auto, config: polishCfg)
        let polishEN = TranslationCacheKey.make(text: "raven", targetLanguage: .en, config: polishCfg)
        #expect(polishAuto.resolvedTarget == nil)
        #expect(polishAuto.wordLookup == false)
        #expect(polishEN.resolvedTarget == .en)
        #expect(polishAuto != polishEN)

        // Dedicated MT models ignore wordLookup
        let mtProfile = ProviderProfile(baseURL: ProviderKind.bailian.defaultBaseURL, model: "qwen-mt-turbo")
        let mtOn = TranslationCacheKey.make(
            text: "raven",
            targetLanguage: .zhCN,
            config: TranslationRequestConfig(provider: .bailian, profile: mtProfile, apiKey: "sk", wordLookup: true)
        )
        let mtOff = TranslationCacheKey.make(
            text: "raven",
            targetLanguage: .zhCN,
            config: TranslationRequestConfig(provider: .bailian, profile: mtProfile, apiKey: "sk", wordLookup: false)
        )
        #expect(mtOn == mtOff)
        #expect(mtOn.wordLookup == false)
    }

    @Test("SettingsStore persists LRU cache to disk, respects toggle, and supports clear")
    @MainActor
    func testSettingsStoreTranslationCachePersistence() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ferry-cache-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SettingsStore(directory: tempDir, cacheCapacity: 2)
        let cfg = TranslationRequestConfig(
            provider: .deepseek,
            profile: store.profile(for: .deepseek),
            apiKey: "sk-test",
            wordLookup: false,
            mode: .translate
        )
        let keyA = TranslationCacheKey.make(text: "Hello world.", targetLanguage: .auto, config: cfg)
        let keyB = TranslationCacheKey.make(text: "Good morning.", targetLanguage: .auto, config: cfg)
        let keyC = TranslationCacheKey.make(text: "Good night.", targetLanguage: .auto, config: cfg)

        store.cacheTranslation("你好，世界。", for: keyA)
        store.cacheTranslation("早上好。", for: keyB)
        #expect(store.cachedTranslationCount == 2)
        #expect(store.cachedTranslation(for: keyA) == "你好，世界。")
        #expect(store.cacheHitCount == 1)

        // Inserting keyC evicts keyB because keyA was just accessed
        store.cacheTranslation("晚安。", for: keyC)
        #expect(store.cachedTranslationCount == 2)
        #expect(store.cachedTranslation(for: keyB) == nil)
        #expect(store.cachedTranslation(for: keyA) == "你好，世界。")
        store.flushTranslationCache()

        // Reloading from the same directory restores persisted LRU cache
        let reloaded = SettingsStore(directory: tempDir, cacheCapacity: 2)
        #expect(reloaded.cachedTranslationCount == 2)
        #expect(reloaded.cachedTranslation(for: keyA) == "你好，世界。")
        #expect(reloaded.cachedTranslation(for: keyC) == "晚安。")
        #expect(reloaded.cachedTranslation(for: keyB) == nil)

        // Disabling cache bypasses lookups and writes
        reloaded.settings.translationCacheEnabled = false
        #expect(reloaded.cachedTranslation(for: keyA) == nil)
        reloaded.cacheTranslation("早安。", for: keyB)
        reloaded.settings.translationCacheEnabled = true
        #expect(reloaded.cachedTranslation(for: keyB) == nil)

        // Clear removes in-memory and persisted entries
        reloaded.clearTranslationCache()
        #expect(reloaded.cachedTranslationCount == 0)
        #expect(reloaded.cacheHitCount == 0)
        let afterClear = SettingsStore(directory: tempDir, cacheCapacity: 2)
        #expect(afterClear.cachedTranslationCount == 0)
    }

    @Test("ModelChoice selection, secondary model suggestion, and profile pinning work across providers")
    @MainActor
    func testModelChoiceAndSecondarySuggestion() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ferry-model-choice-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SettingsStore(directory: tempDir)
        store.setAPIKey("sk-deepseek", for: .deepseek)

        // With only DeepSeek configured on deepseek-chat, suggested secondary picks deepseek-reasoner
        #expect(store.activeModelChoice == ModelChoice(provider: .deepseek, model: "deepseek-chat"))
        #expect(store.suggestedSecondaryModel() == ModelChoice(provider: .deepseek, model: "deepseek-reasoner"))

        // Adding Bailian key prefers cross-provider comparison when no explicit preference is set
        store.setAPIKey("sk-bailian", for: .bailian)
        #expect(store.suggestedSecondaryModel() == ModelChoice(provider: .bailian, model: "qwen-plus"))

        // Explicit secondaryModel overrides auto-suggestion unless identical to primary
        let explicit = ModelChoice(provider: .bailian, model: "qwen-max")
        store.settings.secondaryModel = explicit
        #expect(store.suggestedSecondaryModel() == explicit)
        #expect(store.suggestedSecondaryModel(for: explicit) != explicit)

        // profile(for:) pins the chosen model while clearing customModel override & keeping baseURL
        var customDeepSeek = store.profile(for: .deepseek)
        customDeepSeek.baseURL = "https://proxy.example.com/v1"
        customDeepSeek.customModel = "deepseek-v3"
        store.updateProfile(customDeepSeek, for: .deepseek)
        let pinned = store.profile(for: ModelChoice(provider: .deepseek, model: "deepseek-reasoner"))
        #expect(pinned.effectiveModel == "deepseek-reasoner")
        #expect(pinned.baseURL == "https://proxy.example.com/v1")

        // quickSwitchModelGroups puts active provider first and includes other configured providers
        let groups = store.quickSwitchModelGroups()
        #expect(groups.map(\.provider) == [.deepseek, .bailian])
        #expect(groups[1].choices.contains(explicit))

        // Codable round-trip for ModelChoice & AppSettings.secondaryModel
        let encoded = try JSONEncoder().encode(store.settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        #expect(decoded.secondaryModel == explicit)
        #expect(explicit.displayLabel(in: .zhHans) == "阿里百炼 · qwen-max")
        #expect(explicit.displayLabel(in: .en) == "Bailian · qwen-max")
    }

    @Test("OCRService recognizes rendered text on a CGImage via Apple Vision")
    func testVisionOCRService() async throws {
        let image = try #require(Self.renderTextImage("Hello Ferry OCR"))
        let service = OCRService()
        let text = try await service.recognizeText(from: image)
        #expect(text.lowercased().contains("hello"))
        #expect(text.lowercased().contains("ferry"))
        #expect(text.lowercased().contains("ocr"))
    }

    private static func renderTextImage(_ text: String) -> CGImage? {
        let width = 640
        let height = 160
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrString)
        context.textPosition = CGPoint(x: 40, y: 60)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
