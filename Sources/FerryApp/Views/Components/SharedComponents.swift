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

/// Custom NSTextView supporting Enter-to-submit (or Cmd+Enter), placeholder text, structure-preserving paste,
/// and reliable focus in NSPopover/NSPanel.
public struct SmartTextView: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public var submitOnEnter: Bool
    public var fontSize: CGFloat
    public var focusTrigger: Int
    public var preserveFormatting: Bool
    public var onPasteContent: ((CapturedContent) -> Void)?
    public var onSubmit: () -> Void

    public init(
        text: Binding<String>,
        placeholder: String,
        submitOnEnter: Bool = true,
        fontSize: CGFloat = 13.5,
        focusTrigger: Int = 0,
        preserveFormatting: Bool = true,
        onPasteContent: ((CapturedContent) -> Void)? = nil,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.submitOnEnter = submitOnEnter
        self.fontSize = fontSize
        self.focusTrigger = focusTrigger
        self.preserveFormatting = preserveFormatting
        self.onPasteContent = onPasteContent
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
        textView.preserveFormatting = preserveFormatting
        textView.onPasteContent = onPasteContent
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
        textView.preserveFormatting = preserveFormatting
        textView.onPasteContent = onPasteContent
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
    var preserveFormatting: Bool = true
    var onPasteContent: ((CapturedContent) -> Void)?
    var onSubmit: (() -> Void)?

    override func paste(_ sender: Any?) {
        if preserveFormatting,
           let captured = RichClipboardService.readContent(from: .general, preserveFormatting: true),
           captured.format == .richText || captured.format == .markdown {
            insertText(captured.text, replacementRange: selectedRange())
            onPasteContent?(captured)
            return
        }
        super.paste(sender)
    }

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
                LucideIcon(.globe, size: 12.5)
                    .foregroundStyle(.secondary)
                Text(compact ? selection.shortName(in: appLanguage) : selection.displayName(in: appLanguage))
                    .font(.system(size: 11.5, weight: .medium))
                LucideIcon(.chevronDown, size: 10.5, strokeWidth: 2.1)
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

/// Compact dropdown pill for choosing Translation vs. Writing modes (`标准翻译` / `地道润色` / `语法纠错` / `职场简洁` / `学术表达`).
public struct ModePickerControl: View {
    @Binding public var selection: TranslationMode
    public var compact: Bool
    @Environment(\.appLanguage) private var appLanguage

    public init(selection: Binding<TranslationMode>, compact: Bool = true) {
        self._selection = selection
        self.compact = compact
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        Menu {
            ForEach(TranslationMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack {
                        Image(systemName: mode.symbolName)
                        Text(mode.displayName(in: appLanguage))
                        if mode == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                LucideIcon(selection.lucideIcon, size: 12.5)
                    .foregroundStyle(selection.isWritingMode ? FerryTheme.accentText : .secondary)
                Text(compact ? selection.shortName(in: appLanguage) : selection.displayName(in: appLanguage))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(selection.isWritingMode ? FerryTheme.accentText : .primary)
                    .lineLimit(1)
                LucideIcon(.chevronDown, size: 10.5, strokeWidth: 2.1)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, 4)
            .background(
                selection.isWritingMode ? FerryTheme.accent.opacity(0.14) : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selection.isWritingMode ? FerryTheme.accent.opacity(0.32) : .clear, lineWidth: 1)
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(l10n.modePickerTooltip)
    }
}

/// Inline single-click pill strip for switching translation & writing modes in the Main Window.
public struct ModePillStrip: View {
    @Binding public var selection: TranslationMode
    @Environment(\.appLanguage) private var appLanguage

    public init(selection: Binding<TranslationMode>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(TranslationMode.allCases) { mode in
                let isSelected = selection == mode
                Button {
                    withAnimation(FerryMotion.animation(FerryMotion.quick)) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: 5) {
                        LucideIcon(mode.lucideIcon, size: 13)
                        Text(mode.pillTitle(in: appLanguage))
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(isSelected ? FerryTheme.accentText : Stage.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? FerryTheme.accent.opacity(0.15) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isSelected ? FerryTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("\(mode.displayName(in: appLanguage)) · \(mode.subtitle(in: appLanguage))")
            }
        }
        .padding(3)
        .background(Stage.controlFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Stage.controlStroke, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

public struct CopyResultButton: View {
    public let copied: Bool
    public let disabled: Bool
    public var size: CGFloat = 26
    public var autoFormat: OutputCopyFormat = .plainText
    public var isStructured: Bool = false
    public var onCopyFormat: ((OutputCopyFormat) -> Void)? = nil
    public let action: () -> Void
    @Environment(\.appLanguage) private var appLanguage

    public init(
        copied: Bool,
        disabled: Bool,
        size: CGFloat = 26,
        autoFormat: OutputCopyFormat = .plainText,
        isStructured: Bool = false,
        onCopyFormat: ((OutputCopyFormat) -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.copied = copied
        self.disabled = disabled
        self.size = size
        self.autoFormat = autoFormat
        self.isStructured = isStructured
        self.onCopyFormat = onCopyFormat
        self.action = action
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        let iconSize = max(13, (size * 0.58).rounded())
        let helpText = copied
            ? l10n.copied
            : l10n.copyAutoTooltip(for: autoFormat, structured: isStructured && onCopyFormat != nil)
        Button(action: action) {
            Group {
                if copied {
                    LucideIcon(.check, size: iconSize, strokeWidth: 2.2)
                        .transition(.scale(scale: 0.75).combined(with: .opacity))
                } else {
                    LucideIcon(.copy, size: iconSize)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
        .buttonStyle(HoverIconButtonStyle(isOn: copied, activeColor: Stage.ok, size: size))
        .disabled(disabled)
        .contextMenu {
            if isStructured, !disabled, let onCopyFormat {
                Button {
                    onCopyFormat(.richText)
                } label: {
                    Label(l10n.copyRichTextMenu, systemImage: "doc.richtext")
                }
                Button {
                    onCopyFormat(.markdown)
                } label: {
                    Label(l10n.copyMarkdownMenu, systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button {
                    onCopyFormat(.plainText)
                } label: {
                    Label(l10n.copyPlainTextMenu, systemImage: "doc.plaintext")
                }
            }
        }
        .help(helpText)
        .accessibilityLabel(helpText)
        .animation(FerryMotion.animation(FerryMotion.spring), value: copied)
    }
}

/// Toggle button for switching structured translation results between rendered layout and raw Markdown source.
public struct MarkdownModeToggleButton: View {
    @Binding public var showRawMarkdown: Bool
    public var size: CGFloat = 26
    @Environment(\.appLanguage) private var appLanguage

    public init(showRawMarkdown: Binding<Bool>, size: CGFloat = 26) {
        self._showRawMarkdown = showRawMarkdown
        self.size = size
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        let label = showRawMarkdown ? l10n.viewFormattedLayoutTooltip : l10n.viewMarkdownSourceTooltip
        let iconSize = max(13, (size * 0.56).rounded())
        Button {
            withAnimation(FerryMotion.animation(FerryMotion.quick)) {
                showRawMarkdown.toggle()
            }
        } label: {
            LucideIcon(.code, size: iconSize)
        }
        .buttonStyle(HoverIconButtonStyle(isOn: showRawMarkdown, size: size))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Compact capsule badge shown when rich document formatting was captured from the source.
public struct StructuredFormatBadge: View {
    public var compact: Bool = false
    @Environment(\.appLanguage) private var appLanguage

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        HStack(spacing: 3) {
            LucideIcon(.fileText, size: compact ? 9.5 : 10, strokeWidth: 2.0)
            Text(l10n.richFormatBadge)
                .font(.system(size: compact ? 10 : 10.5, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, compact ? 6 : 7)
        .padding(.vertical, compact ? 2 : 2.5)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75))
        .help(l10n.richFormatBadgeTooltip)
        .accessibilityLabel(l10n.richFormatBadgeTooltip)
        .fixedSize()
    }
}

/// Compact pill indicating a translation was served instantly from the local LRU cache.
public struct CachedResultBadge: View {
    public var compact: Bool = false
    @Environment(\.appLanguage) private var appLanguage

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        HStack(spacing: 3) {
            LucideIcon(.zap, size: compact ? 10 : 10.5, strokeWidth: 2.1)
            Text(l10n.cachedResultBadge)
                .font(.system(size: compact ? 10 : 10.5, weight: .medium))
        }
        .foregroundStyle(FerryTheme.accentText)
        .padding(.horizontal, compact ? 6 : 7)
        .padding(.vertical, compact ? 2 : 2.5)
        .background(FerryTheme.accent.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(FerryTheme.accent.opacity(0.22), lineWidth: 0.75))
        .help(l10n.cachedResultTooltip)
        .accessibilityLabel(l10n.cachedResultTooltip)
        .fixedSize()
    }
}

/// Icon button that bypasses the LRU cache and requests a fresh translation from the model.
public struct RetranslateButton: View {
    public var size: CGFloat = 26
    public var bypassCache: Bool = true
    public var disabled: Bool = false
    public let action: () -> Void
    @Environment(\.appLanguage) private var appLanguage

    public init(size: CGFloat = 26, bypassCache: Bool = true, disabled: Bool = false, action: @escaping () -> Void) {
        self.size = size
        self.bypassCache = bypassCache
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        let label = bypassCache ? l10n.retranslateBypassCacheTooltip : l10n.retranslateTooltip
        let iconSize = max(13, (size * 0.56).rounded())
        Button(action: action) {
            LucideIcon(.rotateCw, size: iconSize)
        }
        .buttonStyle(HoverIconButtonStyle(size: size))
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Subtle pill shown when the current primary translation came from a one-shot model override.
public struct ModelOverrideBadge: View {
    public let model: String
    public var compact: Bool = false

    public init(model: String, compact: Bool = false) {
        self.model = model
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: 3) {
            LucideIcon(.layers, size: compact ? 9.5 : 10, strokeWidth: 2.0)
            Text(model)
                .font(.system(size: compact ? 10 : 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, compact ? 6 : 7)
        .padding(.vertical, compact ? 2 : 2.5)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75))
        .frame(maxWidth: compact ? 120 : 160, alignment: .leading)
    }
}

/// One-shot model switcher menu: retranslate the current text with a stronger or alternative model
/// without changing the user's global default provider/model.
public struct QuickModelSwitchMenu: View {
    public var session: TranslatorSession
    public var settingsStore: SettingsStore
    public var showCompareOption: Bool = true
    public var chipStyle: Bool = false
    public var size: CGFloat = 26
    public var onOpenSettings: () -> Void
    @Environment(\.appLanguage) private var appLanguage

    public init(
        session: TranslatorSession,
        settingsStore: SettingsStore,
        showCompareOption: Bool = true,
        chipStyle: Bool = false,
        size: CGFloat = 26,
        onOpenSettings: @escaping () -> Void
    ) {
        self.session = session
        self.settingsStore = settingsStore
        self.showCompareOption = showCompareOption
        self.chipStyle = chipStyle
        self.size = size
        self.onOpenSettings = onOpenSettings
    }

    private var hasSource: Bool {
        !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        let current = session.effectiveResultModel
        let suggested = settingsStore.suggestedSecondaryModel(for: current)
        let groups = settingsStore.quickSwitchModelGroups()

        Menu {
            if let suggested {
                Button {
                    session.retranslate(with: suggested)
                } label: {
                    Label(l10n.retranslateWithModel(suggested.model), systemImage: "bolt.fill")
                }
                .disabled(!hasSource)

                if showCompareOption {
                    Button {
                        session.startComparison(with: suggested)
                    } label: {
                        Label(l10n.compareWithModelMenu(suggested.model), systemImage: "rectangle.split.2x1")
                    }
                    .disabled(!hasSource)
                }

                Divider()
            }

            if session.isModelOverridden {
                let defaultChoice = settingsStore.activeModelChoice
                Button {
                    session.retranslate(with: defaultChoice)
                } label: {
                    Label("\(l10n.restoreDefaultModel) (\(defaultChoice.model))", systemImage: "arrow.uturn.backward")
                }
                .disabled(!hasSource)
                Divider()
            }

            ForEach(groups, id: \.provider) { group in
                Section(group.provider.shortName(in: appLanguage)) {
                    ForEach(group.choices) { choice in
                        Button {
                            session.retranslate(with: choice)
                        } label: {
                            if choice == current {
                                Label(choice.model, systemImage: "checkmark")
                            } else {
                                Text(choice.model)
                            }
                        }
                        .disabled(!hasSource)
                    }
                }
            }

            Divider()
            Button(l10n.modelSettingsItem, action: onOpenSettings)
        } label: {
            if chipStyle {
                HStack(spacing: 4) {
                    LucideIcon(.layers, size: 11, strokeWidth: 2.0)
                        .foregroundStyle(session.isModelOverridden ? FerryTheme.accentText : .secondary)
                    Text(current.displayLabel(in: appLanguage))
                        .font(.system(size: 10.5, weight: session.isModelOverridden ? .medium : .regular))
                        .foregroundStyle(session.isModelOverridden ? FerryTheme.accentText : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    LucideIcon(.chevronDown, size: 9.5, strokeWidth: 2.2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    session.isModelOverridden ? FerryTheme.accent.opacity(0.12) : Color.primary.opacity(0.055),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        session.isModelOverridden ? FerryTheme.accent.opacity(0.24) : Color.primary.opacity(0.09),
                        lineWidth: 0.75
                    )
                )
            } else {
                let iconSize = max(13, (size * 0.56).rounded())
                LucideIcon(.layers, size: iconSize)
                    .foregroundStyle(session.isModelOverridden ? FerryTheme.accentText : .secondary)
                    .frame(width: size, height: size)
                    .background(
                        session.isModelOverridden ? FerryTheme.accent.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(!hasSource && !chipStyle)
        .opacity((!hasSource && !chipStyle) ? 0.35 : 1)
        .help(l10n.switchModelOnceTooltip)
        .accessibilityLabel(l10n.switchModelOnceTooltip)
    }
}

/// Toggle button that opens or closes dual-model comparison with a single click.
public struct CompareToggleButton: View {
    public var session: TranslatorSession
    public var settingsStore: SettingsStore
    public var size: CGFloat = 26
    @Environment(\.appLanguage) private var appLanguage

    public init(session: TranslatorSession, settingsStore: SettingsStore, size: CGFloat = 26) {
        self.session = session
        self.settingsStore = settingsStore
        self.size = size
    }

    private var hasSource: Bool {
        !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasAlternative: Bool {
        settingsStore.suggestedSecondaryModel(for: session.effectiveResultModel) != nil
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        let iconSize = max(13, (size * 0.56).rounded())
        let tooltip: String = {
            if session.isComparing { return l10n.closeCompareTooltip }
            if !hasAlternative { return l10n.compareNoAlternativeTooltip }
            return l10n.compareModelsTooltip
        }()

        Button {
            session.toggleComparison()
        } label: {
            LucideIcon(.columns2, size: iconSize)
        }
        .buttonStyle(HoverIconButtonStyle(isOn: session.isComparing, size: size))
        .disabled(!session.isComparing && (!hasSource || !hasAlternative))
        .help(tooltip)
        .accessibilityLabel(tooltip)
    }
}

/// Compact dropdown pill inside the comparison card header to pick or switch the second model on the fly.
public struct ComparisonModelPicker: View {
    public var session: TranslatorSession
    public var settingsStore: SettingsStore
    public var compact: Bool = false
    public var onOpenSettings: () -> Void
    @Environment(\.appLanguage) private var appLanguage

    public init(
        session: TranslatorSession,
        settingsStore: SettingsStore,
        compact: Bool = false,
        onOpenSettings: @escaping () -> Void
    ) {
        self.session = session
        self.settingsStore = settingsStore
        self.compact = compact
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        let selected = session.comparisonModel
        let groups = settingsStore.quickSwitchModelGroups()

        Menu {
            ForEach(groups, id: \.provider) { group in
                Section(group.provider.shortName(in: appLanguage)) {
                    ForEach(group.choices) { choice in
                        Button {
                            session.startComparison(with: choice)
                        } label: {
                            if choice == selected {
                                Label(choice.model, systemImage: "checkmark")
                            } else {
                                Text(choice.model)
                            }
                        }
                    }
                }
            }
            Divider()
            Button(l10n.modelSettingsItem, action: onOpenSettings)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(StageHue.azure.bottom)
                    .frame(width: 5.5, height: 5.5)
                Text(
                    selected.map { compact ? $0.model : $0.displayLabel(in: appLanguage) }
                        ?? l10n.compareMenuAction
                )
                .font(.system(size: compact ? 10.5 : 11.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                LucideIcon(.chevronDown, size: 9.5, strokeWidth: 2.2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, compact ? 2.5 : 3.5)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(l10n.switchCompareModelTooltip)
        .accessibilityLabel(l10n.switchCompareModelTooltip)
    }
}

public struct ErrorBannerView: View {
    public let message: String
    public let actionTitle: String?
    public let onAction: (() -> Void)?
    @Environment(\.appLanguage) private var appLanguage

    public init(message: String, showSettingsAction: Bool = false, onOpenSettings: @escaping () -> Void) {
        self.message = message
        self.actionTitle = showSettingsAction ? "" : nil
        self.onAction = showSettingsAction ? onOpenSettings : nil
    }

    public init(message: String, actionTitle: String?, onAction: (() -> Void)?) {
        self.message = message
        self.actionTitle = actionTitle
        self.onAction = onAction
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
            if let actionTitle, let onAction {
                Button(actionTitle.isEmpty ? l10n.openSettingsForAPIKey : actionTitle) {
                    onAction()
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
        let iconSize = max(13, (size * 0.58).rounded())
        Button {
            speechService.toggleSpeak(text: text, id: id, languageHint: languageHint)
        } label: {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                LucideIcon(.volume2, size: iconSize, filled: isSpeaking)
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
                LucideIcon(.volumeX, size: 13)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button {
                    speechService.clearError()
                } label: {
                    LucideIcon(.x, size: 11, strokeWidth: 2.2)
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

/// Compact glass notification banner shown in Popover / Main Window when a newer release is available or ready.
public struct UpdateBannerView: View {
    public let updateService: AppUpdateService
    public var compact: Bool = false
    @Environment(\.appLanguage) private var appLanguage

    public init(updateService: AppUpdateService, compact: Bool = false) {
        self.updateService = updateService
        self.compact = compact
    }

    public var body: some View {
        let l10n = L10n(appLanguage)
        if updateService.shouldShowUpdateBanner {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
                    .foregroundStyle(FerryTheme.accentText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle(l10n))
                        .font(.system(size: compact ? 11.5 : 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if case .downloading(_, let progress) = updateService.state {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .controlSize(.mini)
                    }
                }

                Spacer(minLength: 4)

                switch updateService.state {
                case .available:
                    Button(l10n.downloadUpdate) {
                        updateService.downloadUpdate()
                    }
                    .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal, height: compact ? 22 : 24))

                case .readyToInstall:
                    Button(l10n.restartToUpdate) {
                        updateService.installAndRelaunch()
                    }
                    .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal, height: compact ? 22 : 24))

                case .downloading:
                    ProgressView()
                        .controlSize(.mini)

                default:
                    EmptyView()
                }

                Button {
                    updateService.dismissBanner()
                } label: {
                    LucideIcon(.x, size: 11, strokeWidth: 2.2)
                        .foregroundStyle(.secondary)
                        .padding(3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 6 : 7)
            .glassSurface(cornerRadius: compact ? 10 : 12, fill: FerryTheme.accent.opacity(0.11))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var iconName: String {
        switch updateService.state {
        case .readyToInstall: return "arrow.clockwise.circle.fill"
        case .downloading: return "arrow.down.circle.fill"
        default: return "sparkles"
        }
    }

    private func statusTitle(_ l10n: L10n) -> String {
        switch updateService.state {
        case .available(let release):
            return l10n.updateAvailableTitle(release.version.description)
        case .downloading(let release, let progress):
            return l10n.downloadingUpdateProgress(release.version.description, percent: Int((progress * 100).rounded()))
        case .readyToInstall(let release, _):
            return l10n.updateReadyTitle(release.version.description)
        default:
            return ""
        }
    }
}
