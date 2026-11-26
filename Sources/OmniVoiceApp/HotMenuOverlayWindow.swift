import AppKit
import Observation
import OmniVoiceCore
import SwiftUI

/// Unified command produced by the Hot Menu (either from a primary quick-bar item
/// or from any option inside its upward-expanding options drawer).
enum HotMenuCommand: Equatable {
    case action(HotMenuAction)
    case setLLMCleanupEnabled(Bool)
    case setServiceModeEnabled(Bool)
    case setMuteBackgroundAudioWhileDictating(Bool)
    case selectTranslationLanguage(String?)
}

/// A single selectable sub-option inside a category's upward-expanding drawer.
struct HotMenuDrawerOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let isActive: Bool
    let isDestructiveOrOff: Bool
    let command: HotMenuCommand
}

/// A primary item on the Quick Bar with an upward-expanding drawer of sub-options.
struct HotMenuBarItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let badgeText: String?
    let isActive: Bool
    let primaryCommand: HotMenuCommand
    let drawerTitle: String
    let drawerOptions: [HotMenuDrawerOption]
}

/// Sleek, rock-steady floating Quick Bar that opens **right on the mouse cursor** and uses
/// direct 1:1 `NSEvent.mouseLocation` hit-testing (zero SwiftUI `.onHover` lag or wobble on
/// non-activating panels) plus full arrow-key and scroll-wheel navigation.
@MainActor
final class HotMenuOverlayWindow {
    private static let panelSize = CGSize(width: 640, height: 276)
    /// Distance from the bottom edge of the panel to the vertical center of the Quick Bar pills.
    private static let barCenterFromBottom: CGFloat = 52

    private var panel: NSPanel?
    private let overlayState = HotMenuOverlayState()
    private var presentationMode: HotMenuPresentationMode = .momentary
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var globalClickMonitor: Any?
    private var pointerTrackTimer: Timer?
    private var lastTrackedScreenPoint: CGPoint?
    private var scrollAccumulator: CGFloat = 0
    private var onConfirm: (() -> Void)?
    private var onCancel: (() -> Void)?
    var onExecuteCommand: ((HotMenuCommand) -> Void)?

    var isPresented: Bool {
        panel?.isVisible == true
    }

    func show(
        center requestedCenter: CGPoint,
        theme: OmniVoiceTheme,
        mode: HotMenuPresentationMode,
        llmCleanupEnabled: Bool,
        activeAILabel: String,
        activeStyle: StyleProfile,
        serviceModeEnabled: Bool,
        serviceModeSummary: String,
        asrProviderLabel: String,
        muteBackgroundAudioWhileDictating: Bool,
        liveTranslationEnabled: Bool,
        activeLanguageCode: String,
        quickLanguages: [String],
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.presentationMode = mode
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.scrollAccumulator = 0

        let items = Self.buildBarItems(
            llmCleanupEnabled: llmCleanupEnabled,
            activeAILabel: activeAILabel,
            activeStyle: activeStyle,
            serviceModeEnabled: serviceModeEnabled,
            serviceModeSummary: serviceModeSummary,
            asrProviderLabel: asrProviderLabel,
            muteBackgroundAudioWhileDictating: muteBackgroundAudioWhileDictating,
            liveTranslationEnabled: liveTranslationEnabled,
            activeLanguageCode: activeLanguageCode,
            quickLanguages: quickLanguages
        )

        // Anchor the panel directly on the screen containing the mouse cursor, with the
        // Quick Bar's center placed right under the mouse pointer!
        let screen = NSScreen.screens.first(where: { $0.frame.contains(requestedCenter) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? .zero
        let rawOrigin = CGPoint(
            x: requestedCenter.x - Self.panelSize.width / 2,
            y: requestedCenter.y - Self.barCenterFromBottom
        )
        let clampedOrigin = CGPoint(
            x: min(max(rawOrigin.x, screenFrame.minX + 8), max(screenFrame.minX + 8, screenFrame.maxX - Self.panelSize.width - 8)),
            y: min(max(rawOrigin.y, screenFrame.minY + 8), max(screenFrame.minY + 8, screenFrame.maxY - Self.panelSize.height - 8))
        )

        if panel == nil {
            let created = NSPanel(
                contentRect: CGRect(origin: clampedOrigin, size: Self.panelSize),
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
            created.acceptsMouseMovedEvents = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.contentView = NSHostingView(
                rootView: DynamicQuickBarView(
                    state: overlayState,
                    onExecute: { [weak self] command in
                        guard let self else { return }
                        let handler = self.onExecuteCommand
                        self.cancel()
                        handler?(command)
                    }
                )
            )
            panel = created
        }

        // Start centered on the middle pill (right under the mouse!).
        let centerIndex = items.count / 2
        overlayState.configure(theme: theme, items: items, selectedIndex: centerIndex)
        panel?.alphaValue = 0
        panel?.setFrame(CGRect(origin: clampedOrigin, size: Self.panelSize), display: true)
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }
        installMonitors()
        // Sync initial pointer position once the layout pass reports exact item frames.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPresented else { return }
            self.lastTrackedScreenPoint = nil
            self.handlePointerMove(screenPoint: NSEvent.mouseLocation)
        }
    }

    func finish() -> HotMenuCommand? {
        let command = overlayState.currentCommand
        tearDownInteraction()
        panel?.orderOut(nil)
        return command
    }

    func cancel() {
        tearDownInteraction()
        panel?.orderOut(nil)
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
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handlePointerMove(screenPoint: NSEvent.mouseLocation)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            let loc = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handlePointerMove(screenPoint: loc)
            }
        }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self, self.isPresented else { return event }
            return self.handleScroll(event) ? nil : event
        }
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handleScroll(event)
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
        // High-precision 60Hz cursor tracker directly reading NSEvent.mouseLocation while visible.
        // Immune to macOS .nonactivatingPanel event-routing gaps when another app is frontmost
        // or modifier keys (Option+Shift) are held down.
        lastTrackedScreenPoint = nil
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPresented else { return }
                let loc = NSEvent.mouseLocation
                if let prev = self.lastTrackedScreenPoint,
                   abs(loc.x - prev.x) < 0.25 && abs(loc.y - prev.y) < 0.25 {
                    return
                }
                self.lastTrackedScreenPoint = loc
                self.handlePointerMove(screenPoint: loc)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTrackTimer = timer
    }

    private func removeMonitors() {
        pointerTrackTimer?.invalidate()
        pointerTrackTimer = nil
        lastTrackedScreenPoint = nil
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localScrollMonitor { NSEvent.removeMonitor(localScrollMonitor) }
        if let globalScrollMonitor { NSEvent.removeMonitor(globalScrollMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localKeyMonitor = nil
        globalKeyMonitor = nil
        localMouseMonitor = nil
        globalMouseMonitor = nil
        localScrollMonitor = nil
        globalScrollMonitor = nil
        globalClickMonitor = nil
    }

    /// Direct, zero-lag 1:1 pointer hit-testing in SwiftUI top-left panel coordinates.
    private func handlePointerMove(screenPoint: CGPoint) {
        guard isPresented, let frame = panel?.frame else { return }
        // Convert AppKit bottom-left screen coordinates -> SwiftUI top-left panel coordinates.
        let localPoint = CGPoint(
            x: screenPoint.x - frame.minX,
            y: frame.maxY - screenPoint.y
        )
        guard localPoint.x >= -12, localPoint.x <= frame.width + 12,
              localPoint.y >= -12, localPoint.y <= frame.height + 12 else {
            return
        }
        overlayState.updatePointerLocation(localPoint)
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let frame = panel?.frame, frame.contains(NSEvent.mouseLocation) else { return false }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        scrollAccumulator += delta
        let stepThreshold: CGFloat = event.hasPreciseScrollingDeltas ? 28 : 1.5
        if abs(scrollAccumulator) >= stepThreshold {
            let forward = scrollAccumulator < 0
            scrollAccumulator = 0
            if overlayState.drawerExpanded, overlayState.selectedDrawerIndex != nil {
                overlayState.stepDrawer(delta: forward ? 1 : -1)
            } else {
                overlayState.stepBar(delta: forward ? 1 : -1)
            }
        }
        return true
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123: // Left arrow
            if overlayState.drawerExpanded, overlayState.selectedDrawerIndex != nil {
                overlayState.stepDrawer(delta: -1)
            } else {
                overlayState.stepBar(delta: -1)
            }
        case 124: // Right arrow
            if overlayState.drawerExpanded, overlayState.selectedDrawerIndex != nil {
                overlayState.stepDrawer(delta: 1)
            } else {
                overlayState.stepBar(delta: 1)
            }
        case 126: // Up arrow — reveal & navigate into the upward options drawer
            overlayState.moveUpIntoDrawer()
        case 125: // Down arrow — return from drawer to main bar
            overlayState.moveDownFromDrawer()
        case 36, 76: // Return / Enter
            onConfirm?()
        case 53: // Escape
            let cancelHandler = onCancel
            cancel()
            cancelHandler?()
        default:
            return false
        }
        return true
    }

    // MARK: - Full Action Builder

    private static func buildBarItems(
        llmCleanupEnabled: Bool,
        activeAILabel: String,
        activeStyle: StyleProfile,
        serviceModeEnabled: Bool,
        serviceModeSummary: String,
        asrProviderLabel: String,
        muteBackgroundAudioWhileDictating: Bool,
        liveTranslationEnabled: Bool,
        activeLanguageCode: String,
        quickLanguages: [String]
    ) -> [HotMenuBarItem] {
        // 1. Conversation & Workspace Modes
        let modeOptions: [HotMenuDrawerOption] = [
            HotMenuDrawerOption(
                id: "mode-conversation",
                title: "Conversation",
                subtitle: "Live meeting & speaker transcript",
                systemImage: "person.2.wave.2",
                isActive: false,
                isDestructiveOrOff: false,
                command: .action(.openConversation)
            ),
            HotMenuDrawerOption(
                id: "mode-notes",
                title: "Editor Notes",
                subtitle: "Capture & refine notes",
                systemImage: "doc.text.magnifyingglass",
                isActive: false,
                isDestructiveOrOff: false,
                command: .action(.transcriptionMode)
            ),
            HotMenuDrawerOption(
                id: "mode-askai",
                title: "Ask AI",
                subtitle: activeAILabel,
                systemImage: "sparkles",
                isActive: false,
                isDestructiveOrOff: false,
                command: .action(.askAI)
            ),
            HotMenuDrawerOption(
                id: "mode-dictation",
                title: "Dictation",
                subtitle: "Cursor-direct voice typing",
                systemImage: "mic.fill",
                isActive: false,
                isDestructiveOrOff: false,
                command: .action(.dictation)
            ),
            HotMenuDrawerOption(
                id: "mode-mute-media",
                title: muteBackgroundAudioWhileDictating ? "Mute Media: On" : "Mute Media: Off",
                subtitle: muteBackgroundAudioWhileDictating
                    ? "Mutes music while mic is keyed"
                    : "Tap to mute music on mic key-up",
                systemImage: muteBackgroundAudioWhileDictating ? "speaker.slash.fill" : "speaker.wave.2",
                isActive: muteBackgroundAudioWhileDictating,
                isDestructiveOrOff: !muteBackgroundAudioWhileDictating,
                command: .setMuteBackgroundAudioWhileDictating(!muteBackgroundAudioWhileDictating)
            ),
            HotMenuDrawerOption(
                id: "mode-dashboard",
                title: "Dashboard",
                subtitle: "Open engine status",
                systemImage: "slider.horizontal.3",
                isActive: false,
                isDestructiveOrOff: false,
                command: .action(.openDashboard)
            ),
        ]

        // 2. Smart AI Cleanup & Style (including 1-click Disable AI Cleanup!)
        var cleanupOptions: [HotMenuDrawerOption] = [
            HotMenuDrawerOption(
                id: "cleanup-off",
                title: "AI Cleanup Off",
                subtitle: "Instant raw — zero wait",
                systemImage: "bolt.slash.fill",
                isActive: !llmCleanupEnabled,
                isDestructiveOrOff: true,
                command: .setLLMCleanupEnabled(false)
            ),
            HotMenuDrawerOption(
                id: "cleanup-on",
                title: "AI Cleanup On",
                subtitle: activeAILabel,
                systemImage: "wand.and.stars",
                isActive: llmCleanupEnabled,
                isDestructiveOrOff: false,
                command: .setLLMCleanupEnabled(true)
            ),
        ]
        for style in StyleProfile.allCases {
            cleanupOptions.append(
                HotMenuDrawerOption(
                    id: "style-\(style.rawValue)",
                    title: style.displayName,
                    subtitle: style == .raw ? "No rewrites" : "Dictation style",
                    systemImage: style == .raw ? "text.alignleft" : "textformat",
                    isActive: activeStyle == style,
                    isDestructiveOrOff: style == .raw,
                    command: .action(HotMenuAction.styleAction(for: style))
                )
            )
        }

        // 3. Ask AI Quick Launch
        let askAIOptions: [HotMenuDrawerOption] = [
            HotMenuDrawerOption(
                id: "ask-workspace",
                title: "Ask AI Workspace",
                subtitle: activeAILabel,
                systemImage: "sparkles",
                isActive: true,
                isDestructiveOrOff: false,
                command: .action(.askAI)
            ),
            HotMenuDrawerOption(
                id: "ask-notes",
                title: "Editor Notes",
                subtitle: "Draft & revise with AI",
                systemImage: "doc.text.magnifyingglass",
                isActive: false,
                isDestructiveOrOff: false,
                command: .action(.transcriptionMode)
            ),
            HotMenuDrawerOption(
                id: "ask-conversation",
                title: "Conversation Mode",
                subtitle: "Live AI insights & Q&A",
                systemImage: "person.2.wave.2",
                isActive: false,
                isDestructiveOrOff: false,
                command: .action(.openConversation)
            ),
        ]

        // 4. Service Mode (Cloud / Outbound) vs Local Mode
        let serviceOptions: [HotMenuDrawerOption] = [
            HotMenuDrawerOption(
                id: "service-on",
                title: "Service Mode (Cloud)",
                subtitle: "Deepgram + Subscriptions · 0 local RAM",
                systemImage: "cloud.bolt.fill",
                isActive: serviceModeEnabled,
                isDestructiveOrOff: false,
                command: .setServiceModeEnabled(true)
            ),
            HotMenuDrawerOption(
                id: "service-off",
                title: "Local Mode (On-Device)",
                subtitle: asrProviderLabel,
                systemImage: "desktopcomputer",
                isActive: !serviceModeEnabled,
                isDestructiveOrOff: true,
                command: .setServiceModeEnabled(false)
            ),
            HotMenuDrawerOption(
                id: "service-cycle-asr",
                title: "Cycle Local ASR",
                subtitle: "Current: \(asrProviderLabel)",
                systemImage: "waveform",
                isActive: false,
                isDestructiveOrOff: false,
                command: .action(.cycleASRProvider)
            ),
        ]

        // 5. Translation (Off + Quick Languages)
        let chips = resolvedLanguageCodes(quickLanguages: quickLanguages, active: activeLanguageCode)
        var translationOptions: [HotMenuDrawerOption] = [
            HotMenuDrawerOption(
                id: "trans-off",
                title: "Translation Off",
                subtitle: "Dictate in original language",
                systemImage: "xmark.circle",
                isActive: !liveTranslationEnabled,
                isDestructiveOrOff: true,
                command: .selectTranslationLanguage(nil)
            ),
        ]
        for code in chips {
            let name = InlineTranslationParser.languageInfo(forCode: code)?.name ?? code.uppercased()
            let active = liveTranslationEnabled && activeLanguageCode.lowercased() == code.lowercased()
            translationOptions.append(
                HotMenuDrawerOption(
                    id: "trans-\(code)",
                    title: name,
                    subtitle: code.uppercased(),
                    systemImage: "globe",
                    isActive: active,
                    isDestructiveOrOff: false,
                    command: .selectTranslationLanguage(code)
                )
            )
        }

        let activeLangLabel = InlineTranslationParser.languageInfo(forCode: activeLanguageCode)?.name
            ?? activeLanguageCode.uppercased()

        return [
            HotMenuBarItem(
                id: "modes",
                title: "Conversation",
                subtitle: "Move up for Conversation, Notes, Ask AI, Dictation",
                systemImage: "person.2.wave.2",
                badgeText: nil,
                isActive: false,
                primaryCommand: .action(.openConversation),
                drawerTitle: "Modes",
                drawerOptions: modeOptions
            ),
            HotMenuBarItem(
                id: "cleanup",
                title: llmCleanupEnabled ? "AI Cleanup: On" : "AI Cleanup: Off",
                subtitle: llmCleanupEnabled
                    ? "\(activeStyle.displayName) · Move up to disable or switch style"
                    : "Instant raw · Move up to enable or switch style",
                systemImage: llmCleanupEnabled ? "wand.and.stars" : "bolt.slash",
                badgeText: llmCleanupEnabled ? nil : "OFF",
                isActive: llmCleanupEnabled,
                primaryCommand: .setLLMCleanupEnabled(!llmCleanupEnabled),
                drawerTitle: "AI Cleanup & Style",
                drawerOptions: cleanupOptions
            ),
            HotMenuBarItem(
                id: "ask-ai",
                title: "Ask AI",
                subtitle: "\(activeAILabel) · Move up for workspace options",
                systemImage: "sparkles",
                badgeText: nil,
                isActive: false,
                primaryCommand: .action(.askAI),
                drawerTitle: "AI Workspace",
                drawerOptions: askAIOptions
            ),
            HotMenuBarItem(
                id: "service",
                title: serviceModeEnabled ? "Service Mode" : "Local Mode",
                subtitle: serviceModeEnabled
                    ? "\(serviceModeSummary) · Move up to switch"
                    : "\(asrProviderLabel) · Move up for Cloud Service Mode",
                systemImage: serviceModeEnabled ? "cloud.bolt.fill" : "desktopcomputer",
                badgeText: serviceModeEnabled ? "CLOUD" : nil,
                isActive: serviceModeEnabled,
                primaryCommand: .setServiceModeEnabled(!serviceModeEnabled),
                drawerTitle: "Voice & Model Runtime",
                drawerOptions: serviceOptions
            ),
            HotMenuBarItem(
                id: "translate",
                title: liveTranslationEnabled ? "Translate: \(activeLangLabel)" : "Translate",
                subtitle: liveTranslationEnabled ? "Move up to disable or switch language" : "Move up to choose language",
                systemImage: "globe",
                badgeText: liveTranslationEnabled ? activeLanguageCode.uppercased() : nil,
                isActive: liveTranslationEnabled,
                primaryCommand: .selectTranslationLanguage(liveTranslationEnabled ? nil : activeLanguageCode),
                drawerTitle: "Live Translation",
                drawerOptions: translationOptions
            ),
        ]
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

// MARK: - Observable State with Direct Geometry Hit-Testing

@MainActor
@Observable
private final class HotMenuOverlayState {
    var theme: OmniVoiceTheme = .defaultTheme
    var items: [HotMenuBarItem] = []
    var selectedBarIndex: Int = 0
    var drawerExpanded: Bool = true
    var selectedDrawerIndex: Int? = nil

    // Exact panel-local frames collected via SwiftUI GeometryReader/onGeometryChange
    // (non-observed so layout updates never trigger extra SwiftUI view re-renders!).
    @ObservationIgnored var barContainerFrame: CGRect = .zero
    @ObservationIgnored var barItemFrames: [Int: CGRect] = [:]
    @ObservationIgnored var drawerContainerFrame: CGRect = .zero
    @ObservationIgnored var drawerItemFrames: [Int: CGRect] = [:]

    func configure(theme: OmniVoiceTheme, items: [HotMenuBarItem], selectedIndex: Int) {
        self.theme = theme
        self.items = items
        self.selectedBarIndex = max(0, min(selectedIndex, max(0, items.count - 1)))
        // Open with drawer immediately ready above the bar so moving straight up is instant & zero-lag!
        self.drawerExpanded = !(items.isEmpty)
        self.selectedDrawerIndex = nil
    }

    func applyLayout(_ snapshot: HotMenuLayoutSnapshot) {
        if snapshot.barContainerFrame != .zero {
            barContainerFrame = snapshot.barContainerFrame
        }
        if !snapshot.barItemFrames.isEmpty {
            barItemFrames = snapshot.barItemFrames
        }
        if snapshot.drawerContainerFrame != .zero {
            drawerContainerFrame = snapshot.drawerContainerFrame
        }
        drawerItemFrames = snapshot.drawerItemFrames
    }

    var activeBarItem: HotMenuBarItem? {
        guard items.indices.contains(selectedBarIndex) else { return nil }
        return items[selectedBarIndex]
    }

    var currentCommand: HotMenuCommand? {
        guard let item = activeBarItem else { return nil }
        if drawerExpanded, let dIdx = selectedDrawerIndex, item.drawerOptions.indices.contains(dIdx) {
            return item.drawerOptions[dIdx].command
        }
        return item.primaryCommand
    }

    var captionTitle: String {
        guard let item = activeBarItem else { return "" }
        if drawerExpanded, let dIdx = selectedDrawerIndex, item.drawerOptions.indices.contains(dIdx) {
            let opt = item.drawerOptions[dIdx]
            if let sub = opt.subtitle, !sub.isEmpty {
                return "\(opt.title) — \(sub)"
            }
            return opt.title
        }
        return "\(item.title)  ·  \(item.subtitle)"
    }

    /// Direct 1:1 mouse-position hit-testing in panel-local top-left coordinates.
    /// Uses exact SwiftUI PreferenceKey frames — never stale, never overlapping, zero wobble.
    func updatePointerLocation(_ point: CGPoint) {
        guard !items.isEmpty else { return }

        // 1. Exact non-overlapping hit inside any visible drawer option card.
        if drawerExpanded, !drawerItemFrames.isEmpty {
            if let exactDrawerIdx = drawerItemFrames.first(where: { $0.value.contains(point) })?.key {
                if selectedDrawerIndex != exactDrawerIdx {
                    withAnimation(.easeOut(duration: 0.08)) {
                        selectedDrawerIndex = exactDrawerIdx
                    }
                }
                return
            }
        }

        // 2. Exact non-overlapping hit inside any Quick Bar pill (both X and Y strictly inside the bar).
        let barTop = barContainerFrame.minY > 0 ? barContainerFrame.minY : 196
        let barBottom = barContainerFrame.maxY > 0 ? barContainerFrame.maxY : 256
        if point.y >= barTop - 2, point.y <= barBottom + 6, !barItemFrames.isEmpty {
            if selectedDrawerIndex != nil {
                withAnimation(.easeOut(duration: 0.08)) {
                    selectedDrawerIndex = nil
                }
            }
            if let matchedIndex = barItemFrames.first(where: {
                point.x >= $0.value.minX && point.x <= $0.value.maxX
            })?.key, matchedIndex != selectedBarIndex {
                withAnimation(.easeOut(duration: 0.10)) {
                    selectedBarIndex = matchedIndex
                    selectedDrawerIndex = nil
                    drawerExpanded = !items[matchedIndex].drawerOptions.isEmpty
                }
            }
        }
    }

    func stepBar(delta: Int) {
        guard !items.isEmpty else { return }
        let next = (selectedBarIndex + delta + items.count) % items.count
        withAnimation(.snappy(duration: 0.14)) {
            selectedBarIndex = next
            selectedDrawerIndex = nil
            drawerExpanded = !items[next].drawerOptions.isEmpty
        }
    }

    func moveUpIntoDrawer() {
        guard let item = activeBarItem, !item.drawerOptions.isEmpty else { return }
        withAnimation(.snappy(duration: 0.16)) {
            if !drawerExpanded {
                drawerExpanded = true
                selectedDrawerIndex = 0
            } else if let idx = selectedDrawerIndex {
                let count = item.drawerOptions.count
                selectedDrawerIndex = (idx - 1 + count) % count
            } else {
                selectedDrawerIndex = 0
            }
        }
    }

    func moveDownFromDrawer() {
        withAnimation(.snappy(duration: 0.16)) {
            if selectedDrawerIndex != nil {
                selectedDrawerIndex = nil
            } else {
                drawerExpanded = false
            }
        }
    }

    func stepDrawer(delta: Int) {
        guard let item = activeBarItem, !item.drawerOptions.isEmpty else { return }
        let count = item.drawerOptions.count
        let current = selectedDrawerIndex ?? 0
        let next = (current + delta + count) % count
        withAnimation(.snappy(duration: 0.14)) {
            selectedDrawerIndex = next
        }
    }
}

// MARK: - Atomic Layout Geometry PreferenceKey

private struct HotMenuLayoutSnapshot: Equatable, Sendable {
    var barContainerFrame: CGRect = .zero
    var barItemFrames: [Int: CGRect] = [:]
    var drawerContainerFrame: CGRect = .zero
    var drawerItemFrames: [Int: CGRect] = [:]
}

private struct HotMenuLayoutPreferenceKey: PreferenceKey {
    static let defaultValue = HotMenuLayoutSnapshot()
    static func reduce(value: inout HotMenuLayoutSnapshot, nextValue: () -> HotMenuLayoutSnapshot) {
        let next = nextValue()
        if next.barContainerFrame != .zero {
            value.barContainerFrame = next.barContainerFrame
        }
        for (idx, rect) in next.barItemFrames {
            value.barItemFrames[idx] = rect
        }
        if next.drawerContainerFrame != .zero {
            value.drawerContainerFrame = next.drawerContainerFrame
        }
        for (idx, rect) in next.drawerItemFrames {
            value.drawerItemFrames[idx] = rect
        }
    }
}

// MARK: - SwiftUI View

private struct DynamicQuickBarView: View {
    @Bindable var state: HotMenuOverlayState
    let onExecute: (HotMenuCommand) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ResolvedThemePalette { state.theme.resolvedPalette(for: colorScheme) }
    private var accent: Color { Color(themeColor: palette.accentGraphic) }
    private var secondary: Color { Color(themeColor: palette.secondaryAccentGraphic) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Upward-expanding options drawer right above the bar
            if state.drawerExpanded, let activeItem = state.activeBarItem, !activeItem.drawerOptions.isEmpty {
                drawerCard(for: activeItem)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: HotMenuLayoutPreferenceKey.self,
                                value: HotMenuLayoutSnapshot(drawerContainerFrame: geo.frame(in: .named("hotmenu-root")))
                            )
                        }
                    )
                    .padding(.bottom, 8)
            }

            // Primary Quick Bar (anchored right on the mouse cursor!)
            HStack(spacing: 8) {
                ForEach(state.items.indices, id: \.self) { idx in
                    let item = state.items[idx]
                    let isSelected = idx == state.selectedBarIndex
                    barButton(item: item, index: idx, isSelected: isSelected)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                featheredBarBackdrop(cornerRadius: 26)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: HotMenuLayoutPreferenceKey.self,
                        value: HotMenuLayoutSnapshot(barContainerFrame: geo.frame(in: .named("hotmenu-root")))
                    )
                }
            )

            // Live caption & hint line underneath
            Text(state.captionTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: (colorScheme == .dark ? Color.black : Color.white).opacity(0.85), radius: 6, x: 0, y: 1)
                .padding(.top, 7)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 14)
        .coordinateSpace(name: "hotmenu-root")
        .onPreferenceChange(HotMenuLayoutPreferenceKey.self) { snapshot in
            state.applyLayout(snapshot)
        }
    }

    private func barButton(item: HotMenuBarItem, index: Int, isSelected: Bool) -> some View {
        Button {
            onExecute(item.primaryCommand)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(isSelected ? accent.opacity(0.85) : .clear)
                    .frame(height: 7)

                HStack(spacing: 5) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 14.5, weight: .semibold))
                    if let badge = item.badgeText {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(
                    isSelected
                        ? accent
                        : (item.isActive ? accent.opacity(0.82) : .primary.opacity(0.84))
                )
            }
            .padding(.horizontal, item.badgeText == nil ? 13 : 11)
            .frame(minWidth: 48, minHeight: 38)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(0.24))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(accent.opacity(0.42), lineWidth: 0.85)
                        }
                } else if item.isActive {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(0.09))
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: HotMenuLayoutPreferenceKey.self,
                        value: HotMenuLayoutSnapshot(barItemFrames: [index: geo.frame(in: .named("hotmenu-root"))])
                    )
                }
            )
        }
        .buttonStyle(.plain)
    }

    private func drawerCard(for item: HotMenuBarItem) -> some View {
        let options = item.drawerOptions
        let columns: [GridItem] = options.count <= 3
            ? Array(repeating: GridItem(.flexible(minimum: 110, maximum: 190), spacing: 6), count: options.count)
            : [
                GridItem(.flexible(minimum: 115, maximum: 175), spacing: 6),
                GridItem(.flexible(minimum: 115, maximum: 175), spacing: 6),
                GridItem(.flexible(minimum: 115, maximum: 175), spacing: 6),
            ]

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(accent)
                Text(item.drawerTitle.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Glide up or ↑↓←→ · Release to apply")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.78))
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(options.indices, id: \.self) { idx in
                    let option = options[idx]
                    let isHighlighted = state.selectedDrawerIndex == idx
                    drawerOptionButton(option: option, index: idx, isHighlighted: isHighlighted)
                }
            }
        }
        .id(item.id)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 560)
        .background {
            featheredBarBackdrop(cornerRadius: 18)
        }
    }

    private func drawerOptionButton(option: HotMenuDrawerOption, index: Int, isHighlighted: Bool) -> some View {
        let tintColor: Color = option.isDestructiveOrOff && option.isActive ? .orange : accent
        return Button {
            onExecute(option.command)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isHighlighted || option.isActive ? tintColor : .primary.opacity(0.75))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(option.title)
                            .font(.system(size: 11.5, weight: isHighlighted || option.isActive ? .semibold : .medium))
                            .foregroundStyle(Color.primary.opacity(isHighlighted ? 1.0 : 0.90))
                            .lineLimit(1)
                        if option.isActive {
                            Circle()
                                .fill(tintColor)
                                .frame(width: 5, height: 5)
                        }
                    }
                    if let sub = option.subtitle {
                        Text(sub)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tintColor.opacity(0.24))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(tintColor.opacity(0.48), lineWidth: 0.9)
                        }
                } else if option.isActive {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tintColor.opacity(0.10))
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04))
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: HotMenuLayoutPreferenceKey.self,
                        value: HotMenuLayoutSnapshot(drawerItemFrames: [index: geo.frame(in: .named("hotmenu-root"))])
                    )
                }
            )
        }
        .buttonStyle(.plain)
    }

    private func featheredBarBackdrop(cornerRadius: CGFloat) -> some View {
        let base = colorScheme == .dark ? Color.black : Color.white
        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(base.opacity(colorScheme == .dark ? 0.76 : 0.78))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), accent.opacity(0.22), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
        }
        .allowsHitTesting(false)
    }
}
