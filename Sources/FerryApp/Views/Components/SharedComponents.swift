import AppKit
import FerryCore
import SwiftUI

/// Native macOS visual effect backdrop for floating panels and cards.
public struct VisualEffectBackground: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Custom NSTextView supporting Enter-to-submit (or Cmd+Enter), placeholder text, and reliable focus in NSPopover/NSPanel.
public struct SmartTextView: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public var submitOnEnter: Bool
    public var fontSize: CGFloat
    public var focusTrigger: Int
    public var onSubmit: () -> Void

    public init(
        text: Binding<String>,
        placeholder: String,
        submitOnEnter: Bool = true,
        fontSize: CGFloat = 13.5,
        focusTrigger: Int = 0,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.submitOnEnter = submitOnEnter
        self.fontSize = fontSize
        self.focusTrigger = focusTrigger
        self.onSubmit = onSubmit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = SubmitHandlingTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.placeholderText = placeholder
        textView.submitOnEnter = submitOnEnter
        textView.onSubmit = onSubmit
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastFocusTrigger = focusTrigger
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? SubmitHandlingTextView else { return }

        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
        if textView.placeholderText != placeholder {
            textView.placeholderText = placeholder
            textView.needsDisplay = true
        }
        textView.submitOnEnter = submitOnEnter
        textView.onSubmit = onSubmit
        textView.font = NSFont.systemFont(ofSize: fontSize)

        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SmartTextView
        weak var textView: SubmitHandlingTextView?
        var lastFocusTrigger: Int = 0

        init(parent: SmartTextView) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let value = textView.string
            if parent.text != value {
                parent.text = value
            }
            textView.needsDisplay = true
        }
    }
}

final class SubmitHandlingTextView: NSTextView {
    var placeholderText: String = ""
    var submitOnEnter: Bool = true
    var onSubmit: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && !placeholderText.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? NSFont.systemFont(ofSize: 13.5)
            ]
            let inset = textContainerInset
            let linePadding = textContainer?.lineFragmentPadding ?? 5
            let rect = NSRect(
                x: inset.width + linePadding,
                y: inset.height,
                width: bounds.width - (inset.width + linePadding) * 2,
                height: bounds.height - inset.height * 2
            )
            placeholderText.draw(in: rect, withAttributes: attributes)
        }
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn && !hasMarkedText() {
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if submitOnEnter {
                if flags.isEmpty {
                    onSubmit?()
                    return
                }
                if flags == .shift {
                    insertNewline(nil)
                    return
                }
            } else {
                if flags == .command {
                    onSubmit?()
                    return
                }
            }
        }
        super.keyDown(with: event)
    }
}

public struct LanguagePickerControl: View {
    @Binding public var selection: TargetLanguage
    public var compact: Bool
    @Environment(\.appLanguage) private var appLanguage

    public init(selection: Binding<TargetLanguage>, compact: Bool = false) {
        self._selection = selection
        self.compact = compact
    }

    public var body: some View {
        Menu {
            ForEach(TargetLanguage.allCases) { lang in
                Button {
                    selection = lang
                } label: {
                    HStack {
                        Text(lang.displayName(in: appLanguage))
                        if lang == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                Text(compact ? selection.shortName(in: appLanguage) : selection.displayName(in: appLanguage))
                    .font(.system(size: 11.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

public struct CopyResultButton: View {
    public let copied: Bool
    public let disabled: Bool
    public let action: () -> Void
    @Environment(\.appLanguage) private var appLanguage

    public init(copied: Bool, disabled: Bool, action: @escaping () -> Void) {
        self.copied = copied
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                Text(copied ? l10n.copied : l10n.copy)
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(copied ? Color.green : Color.primary)
        }
        .buttonStyle(FerryButtonStyle(kind: .secondary, compact: true))
        .fixedSize()
        .disabled(disabled)
        .animation(FerryMotion.animation(FerryMotion.spring), value: copied)
    }
}

public struct ErrorBannerView: View {
    public let message: String
    public let showSettingsAction: Bool
    public let onOpenSettings: () -> Void
    @Environment(\.appLanguage) private var appLanguage

    public init(message: String, showSettingsAction: Bool = false, onOpenSettings: @escaping () -> Void) {
        self.message = message
        self.showSettingsAction = showSettingsAction
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
                    .padding(.top, 1)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            if showSettingsAction {
                Button(l10n.openSettingsForAPIKey) {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

public struct SpeakButton: View {
    public let speechService: SpeechService
    public let id: String
    public let text: String
    public var languageHint: TargetLanguage? = nil
    public var help: String? = nil
    public var size: CGFloat = 26
    @Environment(\.appLanguage) private var appLanguage

    public init(
        speechService: SpeechService,
        id: String,
        text: String,
        languageHint: TargetLanguage? = nil,
        help: String? = nil,
        size: CGFloat = 26
    ) {
        self.speechService = speechService
        self.id = id
        self.text = text
        self.languageHint = languageHint
        self.help = help
        self.size = size
    }

    private var isDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isLoading: Bool {
        speechService.isLoading(id: id)
    }

    private var isSpeaking: Bool {
        speechService.isSpeaking(id: id)
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        let idleHelp = help ?? l10n.speak
        Button {
            speechService.toggleSpeak(text: text, id: id, languageHint: languageHint)
        } label: {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else if isSpeaking {
                Image(systemName: "speaker.wave.2.fill")
                    .symbolEffect(.variableColor.iterative)
            } else {
                Image(systemName: "speaker.wave.2")
            }
        }
        .buttonStyle(HoverIconButtonStyle(isOn: isSpeaking || isLoading, size: size))
        .disabled(isDisabled)
        .help(isSpeaking ? l10n.stopSpeaking : (isLoading ? l10n.synthesizingSpeech : idleHelp))
        .accessibilityLabel(isSpeaking ? l10n.stopSpeaking : idleHelp)
    }
}

public struct SpeechErrorBanner: View {
    public let speechService: SpeechService

    public init(speechService: SpeechService) {
        self.speechService = speechService
    }

    public var body: some View {
        if let message = speechService.lastErrorMessage {
            HStack(spacing: 6) {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button {
                    speechService.clearError()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
