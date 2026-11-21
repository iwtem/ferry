import AVFoundation
import FerryCore
import Foundation
import Observation

@MainActor
@Observable
public final class SpeechService: NSObject {
    /// Identifier of the UI control currently loading or playing audio (e.g. `"main-source"`).
    public var activeSpeakingID: String? = nil
    /// `true` while waiting for a cloud TTS response before audio playback begins.
    public var isLoadingCloudAudio: Bool = false
    /// Most recent error message from cloud TTS or audio playback.
    public var lastErrorMessage: String? = nil

    private let settingsStore: SettingsStore
    private let cloudTTS = CloudTTSService()
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var cloudTask: Task<Void, Never>?
    private var playbackToken: UInt64 = 0

    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init()
        self.synthesizer.delegate = self
    }

    public func isActive(id: String) -> Bool {
        activeSpeakingID == id
    }

    public func isLoading(id: String) -> Bool {
        activeSpeakingID == id && isLoadingCloudAudio
    }

    public func isSpeaking(id: String) -> Bool {
        activeSpeakingID == id && !isLoadingCloudAudio
    }

    /// Speaks `text` using the currently selected engine (macOS system voice or cloud TTS).
    /// Calling again with the same `id` while active stops playback.
    public func toggleSpeak(
        text: String,
        id: String,
        languageHint: TargetLanguage? = nil,
        accentOverride: EnglishAccent? = nil
    ) {
        if activeSpeakingID == id {
            stop()
            return
        }
        speak(text: text, id: id, languageHint: languageHint, accentOverride: accentOverride)
    }

    public func speak(
        text: String,
        id: String,
        languageHint: TargetLanguage? = nil,
        accentOverride: EnglishAccent? = nil
    ) {
        let cleaned = CloudTTSService.sanitizeForSpeech(text)
        guard !cleaned.isEmpty else { return }

        stop()
        lastErrorMessage = nil

        let speech = settingsStore.settings.speech
        let accent = accentOverride ?? speech.englishAccent
        let languageCode = LanguageDetection.speechLanguageCode(
            for: cleaned,
            hint: languageHint,
            englishAccent: accent
        )

        playbackToken &+= 1
        let token = playbackToken
        activeSpeakingID = id

        switch speech.engine {
        case .system:
            speakWithSystemVoice(text: cleaned, languageCode: languageCode, rateMultiplier: speech.rate)
        case .bailian:
            let profile = settingsStore.profile(for: .bailian)
            let apiKey = settingsStore.apiKey(for: .bailian)
            let request = CloudTTSRequest(
                engine: .bailian,
                text: cleaned,
                model: speech.bailianModel,
                voice: speech.bailianVoice,
                speed: speech.rate,
                baseURL: profile.baseURL,
                apiKey: apiKey,
                languageType: LanguageDetection.dashScopeLanguageType(for: languageCode)
            )
            speakWithCloudTTS(request: request, token: token)
        case .openAI:
            let profile = settingsStore.profile(for: .custom)
            let apiKey = settingsStore.apiKey(for: .custom)
            let request = CloudTTSRequest(
                engine: .openAI,
                text: cleaned,
                model: speech.openAIModel,
                voice: speech.openAIVoice,
                speed: speech.rate,
                baseURL: profile.baseURL,
                apiKey: apiKey,
                languageType: nil
            )
            speakWithCloudTTS(request: request, token: token)
        }
    }

    public func stop() {
        playbackToken &+= 1
        cloudTask?.cancel()
        cloudTask = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        audioPlayer?.stop()
        audioPlayer = nil
        isLoadingCloudAudio = false
        activeSpeakingID = nil
    }

    public func clearError() {
        lastErrorMessage = nil
    }

    // MARK: - Option 1: macOS System Voice (AVSpeechSynthesizer)

    private func speakWithSystemVoice(text: String, languageCode: String, rateMultiplier: Double) {
        isLoadingCloudAudio = false

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestSystemVoice(for: languageCode)
        // Map 0.7...1.5 around AVSpeechUtteranceDefaultSpeechRate (~0.5)
        let defaultRate = Double(AVSpeechUtteranceDefaultSpeechRate)
        let mapped = defaultRate * (0.55 + 0.45 * rateMultiplier)
        utterance.rate = Float(min(max(mapped, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
        synthesizer.speak(utterance)
    }

    /// Selects the highest-quality installed voice for `languageCode` (`premium > enhanced > default`).
    private static func bestSystemVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let normalizedTarget = languageCode.lowercased()
        let langPrefix = normalizedTarget.split(separator: "-").first.map(String.init) ?? normalizedTarget

        let exactMatches = voices.filter { $0.language.lowercased() == normalizedTarget }
        let candidates = exactMatches.isEmpty
            ? voices.filter { $0.language.lowercased().hasPrefix(langPrefix) }
            : exactMatches

        if let best = candidates.max(by: { voiceQualityRank($0) < voiceQualityRank($1) }) {
            return best
        }
        return AVSpeechSynthesisVoice(language: languageCode) ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func voiceQualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }

    // MARK: - Option 3: Cloud TTS (Alibaba Bailian / OpenAI Compatible)

    private func speakWithCloudTTS(request: CloudTTSRequest, token: UInt64) {
        isLoadingCloudAudio = true
        cloudTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audioData = try await self.cloudTTS.synthesize(request)
                guard !Task.isCancelled, self.playbackToken == token else { return }

                let player = try AVAudioPlayer(data: audioData)
                player.delegate = self
                player.prepareToPlay()
                self.audioPlayer = player
                self.isLoadingCloudAudio = false

                if !player.play() {
                    self.activeSpeakingID = nil
                    self.lastErrorMessage = L10n().audioPlaybackFailed
                }
            } catch {
                guard !Task.isCancelled, self.playbackToken == token else { return }
                self.isLoadingCloudAudio = false
                self.activeSpeakingID = nil
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.synthesizer.isSpeaking && self.audioPlayer == nil {
                self.activeSpeakingID = nil
            }
        }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.synthesizer.isSpeaking && self.audioPlayer == nil && !self.isLoadingCloudAudio {
                self.activeSpeakingID = nil
            }
        }
    }
}

extension SpeechService: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let current = self.audioPlayer, ObjectIdentifier(current) == playerID {
                self.audioPlayer = nil
                self.activeSpeakingID = nil
            }
        }
    }

    public nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let playerID = ObjectIdentifier(player)
        let message = error?.localizedDescription ?? L10n().audioDecodeFailed
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let current = self.audioPlayer, ObjectIdentifier(current) == playerID {
                self.audioPlayer = nil
                self.activeSpeakingID = nil
                self.lastErrorMessage = message
            }
        }
    }
}
