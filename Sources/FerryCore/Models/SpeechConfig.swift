import Foundation

public enum SpeechEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case bailian
    case openAI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "系统语音"
        case .bailian: return "阿里百炼 TTS"
        case .openAI: return "OpenAI TTS"
        }
    }

    public var subtitle: String {
        switch self {
        case .system: return "离线秒响 · 免费"
        case .bailian: return "Qwen-TTS · 复用百炼 Key"
        case .openAI: return "/audio/speech · 复用自定义 Key"
        }
    }
}

public enum EnglishAccent: String, CaseIterable, Codable, Identifiable, Sendable {
    case us = "en-US"
    case gb = "en-GB"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .us: return "美式英语 (US)"
        case .gb: return "英式英语 (UK)"
        }
    }
}

public struct SpeechSettings: Codable, Equatable, Sendable {
    public var engine: SpeechEngine
    public var englishAccent: EnglishAccent
    /// Playback speed multiplier (`0.7 ... 1.5`, default `1.0`).
    public var rate: Double
    public var bailianModel: String
    public var bailianVoice: String
    public var openAIModel: String
    public var openAIVoice: String

    public static let bailianVoices: [String] = [
        "Cherry",
        "Serena",
        "Ethan",
        "Chelsie",
        "Nofish"
    ]

    public static let openAIVoices: [String] = [
        "coral",
        "alloy",
        "nova",
        "sage",
        "shimmer",
        "onyx",
        "ash"
    ]

    public init(
        engine: SpeechEngine = .system,
        englishAccent: EnglishAccent = .us,
        rate: Double = 1.0,
        bailianModel: String = "qwen3-tts-flash",
        bailianVoice: String = "Cherry",
        openAIModel: String = "gpt-4o-mini-tts",
        openAIVoice: String = "coral"
    ) {
        self.engine = engine
        self.englishAccent = englishAccent
        self.rate = rate
        self.bailianModel = bailianModel
        self.bailianVoice = bailianVoice
        self.openAIModel = openAIModel
        self.openAIVoice = openAIVoice
    }

    private enum CodingKeys: String, CodingKey {
        case engine, englishAccent, rate, bailianModel, bailianVoice, openAIModel, openAIVoice
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SpeechSettings()
        engine = try c.decodeIfPresent(SpeechEngine.self, forKey: .engine) ?? d.engine
        englishAccent = try c.decodeIfPresent(EnglishAccent.self, forKey: .englishAccent) ?? d.englishAccent
        rate = try c.decodeIfPresent(Double.self, forKey: .rate) ?? d.rate
        bailianModel = try c.decodeIfPresent(String.self, forKey: .bailianModel) ?? d.bailianModel
        bailianVoice = try c.decodeIfPresent(String.self, forKey: .bailianVoice) ?? d.bailianVoice
        openAIModel = try c.decodeIfPresent(String.self, forKey: .openAIModel) ?? d.openAIModel
        openAIVoice = try c.decodeIfPresent(String.self, forKey: .openAIVoice) ?? d.openAIVoice
    }
}
