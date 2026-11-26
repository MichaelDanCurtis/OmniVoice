import AppKit
import Observation
import OmniVoiceCore
import SwiftUI

/// Sleek single-row Dynamic Island-style floating Quick Bar with feathered translucent
/// backdrop, icon-first actions, sliding selection glow, and expandable inline Translation picker.
@MainActor
final class HotMenuOverlayWindow {
    private static let barSize = CGSize(width: 560, height: 100)

    private var panel: NSPanel?
    private let overlayState = HotMenuOverlayState()
    private var actions: [HotMenuDirection: [HotMenuAction]] = [:]
    private var actionLabels: [HotMenuAction: String] = [:]
    private var selectionState = HotMenuActionRingState()
    private var presentationMode: HotMenuPresentationMode = .momentary
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalClickMonitor: Any?
    private var onConfirm: (() -> Void)?
    private var onCancel: (() -> Void)?
    var onSelectTranslationLanguage: ((String?) -> Void)?
    var onExecuteAction: ((HotMenuAction) -> Void)?

    var isPresented: Bool {
        panel?.isVisible == true
    }

    func show(
        center requestedCenter: CGPoint,
        theme: OmniVoiceTheme,
        actions: [HotMenuDirection: [HotMenuAction]],
        actionLabels: [HotMenuAction: String],
        mode: HotMenuPresentationMode,
        liveTranslationEnabled: Bool = false,
        activeLanguageCode: String = "es",
        quickLanguages: [String] = ["es", "fr", "ja", "de", "zh"],
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.actions = actions
        self.actionLabels = actionLabels
        self.selectionState = HotMenuActionRingState()
        self.presentationMode = mode
        self.onConfirm = onConfirm
        self.onCancel = onCancel

        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let origin = CaptionOverlayPlacement.origin(
            forCenter: requestedCenter,
            screenFrame: screenFrame,
            overlaySize: Self.barSize
        )

        if panel == nil {
            let created = NSPanel(
                contentRect: CGRect(origin: origin, size: Self.barSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isFloatingPanel = true
            created.becomesKeyOnlyIfNeeded = true
            created.hidesOnDeactivate = false
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.level = .floating
            created.ignoresMouseEvents = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.contentView = NSHostingView(
                rootView: DynamicQuickBarView(
                    state: overlayState,
                    onTapAction: { [weak self] action in
                        guard let self else { return }
                        let handler = self.onExecuteAction
                        self.cancel()
                        handler?(action)
                    },
                    onTapLanguage: { [weak self] code in
                        guard let self else { return }
                        let handler = self.onSelectTranslationLanguage
                        self.cancel()
                        handler?(code)
                    }
                )
            )
            panel = created
        }

        let orderedActions = Self.deduplicatedActions(from: actions)
        let chips = Self.resolvedLanguageCodes(quickLanguages: quickLanguages, active: activeLanguageCode)
        overlayState.configure(
            theme: theme,
            actions: orderedActions,
            actionLabels: actionLabels,
            liveTranslationEnabled: liveTranslationEnabled,
            activeLanguageCode: activeLanguageCode,
            quickLanguages: chips,
            selectedIndex: 0
        )
        panel?.alphaValue = 0
        panel?.setFrame(CGRect(origin: origin, size: Self.barSize), display: true)
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }
        installMonitors()
    }

    func finish() -> HotMenuAction? {
        let selected = currentSelectedAction()
        tearDownInteraction()
        panel?.orderOut(nil)
        return selected
    }

    func cancel() {
        tearDownInteraction()
        selectionState = HotMenuActionRingState()
        panel?.orderOut(nil)
    }

    func select(_ direction: HotMenuDirection, cycleIfSameDirection: Bool = true) {
        let count = overlayState.actions.count
        guard count > 0 else { return }
        switch direction {
        case .left, .up:
            overlayState.selectedIndex = (overlayState.selectedIndex - 1 + count) % count
        case .right, .down:
            overlayState.selectedIndex = (overlayState.selectedIndex + 1) % count
        }
    }

    private func currentSelectedAction() -> HotMenuAction? {
        guard overlayState.actions.indices.contains(overlayState.selectedIndex) else {
            return selectionState.selectedAction(in: actions)
        }
        return overlayState.actions[overlayState.selectedIndex]
    }

    private func tearDownInteraction() {
        removeMonitors()
        onConfirm = nil
        onCancel = nil
    }

    private func installMonitors() {
        removeMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handleKeyDown(event)
            }
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let frame = self.panel?.frame, self.isPresented else { return }
                let clickLoc = NSEvent.mouseLocation
                if !frame.contains(clickLoc) {
                    let cancelHandler = self.onCancel
                    self.cancel()
                    cancelHandler?()
                }
            }
        }
    }

    private func removeMonitors() {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localKeyMonitor = nil
        globalKeyMonitor = nil
        globalClickMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123, 126:
            select(.left)
        case 124, 125:
            select(.right)
        case 36, 76:
            onConfirm?()
        case 53:
            let cancelHandler = onCancel
            cancel()
            cancelHandler?()
        default:
            return false
        }
        return true
    }

    /// Strips redundant translation-cycle actions since the inline globe pill handles translation directly.
    private static func deduplicatedActions(from actions: [HotMenuDirection: [HotMenuAction]]) -> [HotMenuAction] {
        let translationActions: Set<HotMenuAction> = [
            .toggleTranslation, .translationOff, .translationOn,
            .cycleTranslationLanguage, .translationQuickTarget1,
            .translationQuickTarget2, .translationQuickTarget3,
            .translationQuickTarget4,
        ]
        var seen = Set<HotMenuAction>()
        var result: [HotMenuAction] = []
        for direction in [HotMenuDirection.left, .up, .right, .down] {
            for action in actions[direction] ?? [] where !translationActions.contains(action) && action != .none {
                if seen.insert(action).inserted {
                    result.append(action)
                }
            }
        }
        return result
    }

    private static func resolvedLanguageCodes(quickLanguages: [String], active: String) -> [String] {
        var codes = quickLanguages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if codes.isEmpty {
            codes = ["es", "fr", "ja", "de", "zh"]
        }
        let cleanActive = active.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cleanActive.isEmpty && !codes.contains(cleanActive) {
            codes.insert(cleanActive, at: 0)
        }
        return Array(codes.prefix(5))
    }
}

@MainActor
@Observable
private final class HotMenuOverlayState {
    var theme: OmniVoiceTheme = .defaultTheme
    var actions: [HotMenuAction] = []
    var actionLabels: [HotMenuAction: String] = [:]
    var liveTranslationEnabled = false
    var activeLanguageCode = "es"
    var quickLanguages: [String] = ["es", "fr", "ja", "de", "zh"]
    var selectedIndex = 0
    var showLanguagePicker = false

    func configure(
        theme: OmniVoiceTheme,
        actions: [HotMenuAction],
        actionLabels: [HotMenuAction: String],
        liveTranslationEnabled: Bool,
        activeLanguageCode: String,
        quickLanguages: [String],
        selectedIndex: Int
    ) {
        self.theme = theme
        self.actions = actions
        self.actionLabels = actionLabels
        self.liveTranslationEnabled = liveTranslationEnabled
        self.activeLanguageCode = activeLanguageCode
        self.quickLanguages = quickLanguages
        self.selectedIndex = selectedIndex
        self.showLanguagePicker = false
    }
}

private struct DynamicQuickBarView: View {
    @Bindable var state: HotMenuOverlayState
    let onTapAction: (HotMenuAction) -> Void
    let onTapLanguage: (String?) -> Void
    @State private var hoveredLabel: String?
    @Namespace private var highlightNamespace
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ResolvedThemePalette { state.theme.resolvedPalette(for: colorScheme) }
    private var accent: Color { Color(themeColor: palette.accentGraphic) }
    private var secondary: Color { Color(themeColor: palette.secondaryAccentGraphic) }

    private var captionText: String? {
        if let hoveredLabel { return hoveredLabel }
        if state.showLanguagePicker {
            return state.liveTranslationEnabled
                ? "Translating to \(InlineTranslationParser.languageInfo(forCode: state.activeLanguageCode)?.name ?? state.activeLanguageCode.uppercased())"
                : "Choose translation language"
        }
        guard state.actions.indices.contains(state.selectedIndex) else { return nil }
        let action = state.actions[state.selectedIndex]
        return state.actionLabels[action] ?? action.displayName
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                if !state.showLanguagePicker {
                    actionIcons
                }

                if !state.actions.isEmpty && !state.showLanguagePicker {
                    Capsule()
                        .fill(Color.primary.opacity(0.16))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 4)
                }

                translationControl
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                featheredBarBackdrop
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: state.showLanguagePicker)

            if let captionText {
                Text(captionText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.86))
                    .shadow(color: (colorScheme == .dark ? Color.black : Color.white).opacity(0.8), radius: 6, x: 0, y: 1)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var actionIcons: some View {
        let items = Array(state.actions.prefix(5))
        return HStack(spacing: 3) {
            ForEach(items.indices, id: \.self) { idx in
                let action = items[idx]
                let isSelected = idx == state.selectedIndex
                let label = state.actionLabels[action] ?? action.displayName
                Button {
                    onTapAction(action)
                } label: {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? accent : .primary.opacity(0.84))
                        .frame(width: 34, height: 32)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(accent.opacity(0.22))
                                    .matchedGeometryEffect(id: "quickbar-selection", in: highlightNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                            state.selectedIndex = idx
                        }
                        hoveredLabel = label
                    } else if hoveredLabel == label {
                        hoveredLabel = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var translationControl: some View {
        if state.showLanguagePicker {
            HStack(spacing: 3) {
                languagePill(label: "Off", fullName: "Turn translation off", isActive: !state.liveTranslationEnabled) {
                    onTapLanguage(nil)
                }
                ForEach(state.quickLanguages, id: \.self) { code in
                    let name = InlineTranslationParser.languageInfo(forCode: code)?.name ?? code.uppercased()
                    let active = state.liveTranslationEnabled && state.activeLanguageCode.lowercased() == code.lowercased()
                    languagePill(label: name, fullName: "Translate to \(name)", isActive: active) {
                        onTapLanguage(code)
                    }
                }
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        state.showLanguagePicker = false
                    }
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 28)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                    state.showLanguagePicker = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 13.5, weight: .semibold))
                    if state.liveTranslationEnabled {
                        Text(state.activeLanguageCode.uppercased())
                            .font(.caption.weight(.bold))
                    }
                }
                .foregroundStyle(state.liveTranslationEnabled ? accent : .primary.opacity(0.82))
                .padding(.horizontal, state.liveTranslationEnabled ? 10 : 8)
                .frame(height: 32)
                .background {
                    if state.liveTranslationEnabled {
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.20))
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredLabel = hovering
                    ? (state.liveTranslationEnabled ? "Switch translation language" : "Translate dictation")
                    : nil
            }
        }
    }

    private func languagePill(
        label: String,
        fullName: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? accent : .primary.opacity(0.84))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background {
                    if isActive {
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.20))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredLabel = hovering ? fullName : nil
        }
    }

    private var featheredBarBackdrop: some View {
        let base = colorScheme == .dark ? Color.black : Color.white
        return ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.18), secondary.opacity(0.14)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.horizontal, -8)
                .padding(.vertical, -5)
                .blur(radius: 16)

            Capsule(style: .continuous)
                .fill(base.opacity(colorScheme == .dark ? 0.34 : 0.42))
                .blur(radius: 6)

            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), accent.opacity(0.22), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
        .allowsHitTesting(false)
    }
}

private extension HotMenuAction {
    var systemImage: String {
        switch self {
        case .none: "circle.dotted"
        case .openConversation: "person.2.wave.2"
        case .transcriptionMode: "doc.text.magnifyingglass"
        case .askAI: "sparkles"
        case .selectionRewrite: "wand.and.stars"
        case .dictation: "mic.fill"
        case .toggleTranslation, .translationOff, .translationOn,
             .cycleTranslationLanguage, .translationQuickTarget1,
             .translationQuickTarget2, .translationQuickTarget3,
             .translationQuickTarget4: "globe"
        case .cycleStyle, .styleNeutral, .styleProfessional,
             .styleConcise, .styleExpanded, .styleRaw: "textformat"
        case .cycleASRProvider: "waveform"
        case .openDashboard: "slider.horizontal.3"
        }
    }
}
