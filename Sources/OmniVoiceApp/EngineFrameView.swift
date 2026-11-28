import AppKit
import SwiftUI
import OmniVoiceCore

/// Hosts the exterior sticking-out Transcript History pull-tab and its floating drawer
/// as borderless child `NSPanel`s attached cleanly outside the left or right edge of the
/// main OmniSpeak window — leaving 100% of the window interior unobstructed.
struct EngineFrameView: View {
    static let drawerWidth: CGFloat = 410
    static let handleHeight: CGFloat = 82
    static let handleWidth: CGFloat = 30
    static let handleOverlapIntoParent: CGFloat = 2

    @Bindable var model: AppModel
    let side: EngineFrameSide
    @Binding var isExpanded: Bool
    let insertTranscript: (EngineTranscriptRecord) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .background {
                EngineFrameHandleFloatingPanelBridge(
                    model: model,
                    side: side,
                    isExpanded: $isExpanded
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

                TranscriptHistoryFloatingPanelBridge(
                    model: model,
                    side: side,
                    isExpanded: $isExpanded,
                    insertTranscript: insertTranscript,
                    copyTranscript: copyTranscript
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            .task {
                await model.refreshTranscripts()
            }
    }

    private func copyTranscript(_ transcript: EngineTranscriptRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript.displayText, forType: .string)
        model.statusText = "Transcript copied"
    }
}

/// Attaches the tactile exterior pull-tab as a child `NSPanel` flush against the outside
/// left or right edge of the main OmniSpeak window so it physically sticks out past the
/// window frame, moves 1:1 with the window, and never overlaps any card inside.
struct EngineFrameHandleFloatingPanelBridge: NSViewRepresentable {
    @Bindable var model: AppModel
    let side: EngineFrameSide
    @Binding var isExpanded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = ExteriorHandleAnchorNSView(frame: .zero)
        let coordinator = context.coordinator
        view.onWindowChanged = { [weak coordinator] window in
            DispatchQueue.main.async {
                coordinator?.handleWindowChanged(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let appModel = model
        let currentSide = side
        let expanded = isExpanded
        let toggleExpanded: () -> Void = {
            isExpanded.toggle()
        }

        DispatchQueue.main.async {
            coordinator.storeLatest(
                model: appModel,
                side: currentSide,
                isExpanded: expanded,
                onToggle: toggleExpanded
            )
            guard let parentWindow = nsView.window else {
                coordinator.hide()
                return
            }
            coordinator.attachAndUpdate(
                parentWindow: parentWindow,
                model: appModel,
                side: currentSide,
                isExpanded: expanded,
                onToggle: toggleExpanded
            )
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        MainActor.assumeIsolated {
            coordinator.hide()
        }
    }

    @MainActor
    final class Coordinator {
        private var panel: NSPanel?
        private weak var attachedParent: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var liveModel: AppModel?
        private var liveSide: EngineFrameSide = .right
        private var liveIsExpanded = false
        private var liveOnToggle: (() -> Void)?
        private var isDragging = false

        func storeLatest(
            model: AppModel,
            side: EngineFrameSide,
            isExpanded: Bool,
            onToggle: @escaping () -> Void
        ) {
            self.liveModel = model
            self.liveSide = side
            self.liveIsExpanded = isExpanded
            self.liveOnToggle = onToggle
        }

        func handleWindowChanged(_ window: NSWindow?) {
            guard let window else {
                hide()
                return
            }
            guard let model = liveModel, let onToggle = liveOnToggle else { return }
            attachAndUpdate(
                parentWindow: window,
                model: model,
                side: liveSide,
                isExpanded: liveIsExpanded,
                onToggle: onToggle
            )
        }

        func attachAndUpdate(
            parentWindow: NSWindow,
            model: AppModel,
            side: EngineFrameSide,
            isExpanded: Bool,
            onToggle: @escaping () -> Void
        ) {
            self.liveModel = model
            self.liveSide = side
            self.liveIsExpanded = isExpanded
            self.liveOnToggle = onToggle

            let panel = ensurePanel()
            updateContent(on: panel, model: model, side: side, isExpanded: isExpanded)

            if attachedParent !== parentWindow {
                detachFromParent()
                attachedParent = parentWindow
                parentWindow.addChildWindow(panel, ordered: .above)

                let resizeObs = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: parentWindow,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.reposition(animated: false) }
                }
                let screenObs = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeScreenNotification,
                    object: parentWindow,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.reposition(animated: false) }
                }
                let closeObs = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: parentWindow,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.hide() }
                }
                let miniaturizeObs = NotificationCenter.default.addObserver(
                    forName: NSWindow.willMiniaturizeNotification,
                    object: parentWindow,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.panel?.orderOut(nil) }
                }
                let deminiaturizeObs = NotificationCenter.default.addObserver(
                    forName: NSWindow.didDeminiaturizeNotification,
                    object: parentWindow,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let parent = self.attachedParent, let panel = self.panel else { return }
                        self.reposition(animated: false)
                        panel.order(.above, relativeTo: parent.windowNumber)
                    }
                }
                observers = [resizeObs, screenObs, closeObs, miniaturizeObs, deminiaturizeObs]
            }

            if !isDragging {
                let targetFrame = Self.handleFrame(
                    for: parentWindow,
                    side: side,
                    normalizedPosition: model.preferences.engineFrameHandlePosition
                )
                if !panel.isVisible {
                    panel.setFrame(targetFrame, display: true)
                    panel.order(.above, relativeTo: parentWindow.windowNumber)
                } else if abs(panel.frame.origin.x - targetFrame.origin.x) > 0.5
                            || abs(panel.frame.origin.y - targetFrame.origin.y) > 0.5 {
                    panel.setFrame(targetFrame, display: true, animate: false)
                }
            }
        }

        func hide() {
            detachFromParent()
            panel?.orderOut(nil)
        }

        private func detachFromParent() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            if let parent = attachedParent, let panel {
                parent.removeChildWindow(panel)
            }
            attachedParent = nil
        }

        private func ensurePanel() -> NSPanel {
            if let existing = panel {
                return existing
            }
            let created = NSPanel(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: EngineFrameView.handleWidth,
                    height: EngineFrameView.handleHeight
                ),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            created.isReleasedWhenClosed = false
            created.hidesOnDeactivate = false
            created.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            self.panel = created
            return created
        }

        private func updateContent(
            on panel: NSPanel,
            model: AppModel,
            side: EngineFrameSide,
            isExpanded: Bool
        ) {
            let rootView = ExteriorPullTabView(
                theme: model.activeTheme,
                side: side,
                isExpanded: isExpanded,
                onClick: { [weak self] in
                    self?.liveOnToggle?()
                },
                onDragChanged: { [weak self] screenPoint in
                    self?.handleScreenDragChanged(screenPoint)
                },
                onDragEnded: { [weak self] screenPoint in
                    self?.handleScreenDragEnded(screenPoint)
                }
            )
            .preferredColorScheme(model.preferences.appearanceMode.colorScheme)

            if let hosting = panel.contentView as? NSHostingView<AnyView> {
                hosting.rootView = AnyView(rootView)
            } else {
                panel.contentView = NSHostingView(rootView: AnyView(rootView))
            }
        }

        private func reposition(animated: Bool) {
            guard !isDragging,
                  let parent = attachedParent,
                  let panel,
                  let model = liveModel else {
                return
            }
            let target = Self.handleFrame(
                for: parent,
                side: model.activeTheme.engineFrameSide,
                normalizedPosition: model.preferences.engineFrameHandlePosition
            )
            panel.setFrame(target, display: true, animate: animated)
        }

        private func handleScreenDragChanged(_ screenPoint: NSPoint) {
            guard let parent = attachedParent, let panel else { return }
            isDragging = true
            let nextPos = Self.normalizedPosition(forScreenY: screenPoint.y, in: parent)
            let previewSide: EngineFrameSide = screenPoint.x < parent.frame.midX ? .left : .right
            let nextFrame = Self.handleFrame(for: parent, side: previewSide, normalizedPosition: nextPos)
            panel.setFrame(nextFrame, display: true)
            if let model = liveModel, previewSide != liveSide {
                liveSide = previewSide
                updateContent(on: panel, model: model, side: previewSide, isExpanded: liveIsExpanded)
            }
        }

        private func handleScreenDragEnded(_ screenPoint: NSPoint) {
            defer { isDragging = false }
            guard let parent = attachedParent, let model = liveModel else { return }
            let nextPos = Self.normalizedPosition(forScreenY: screenPoint.y, in: parent)
            let nextSide: EngineFrameSide = screenPoint.x < parent.frame.midX ? .left : .right
            if nextSide != model.activeTheme.engineFrameSide {
                model.setEngineFrameSide(nextSide)
            }
            model.setEngineFrameHandlePosition(nextPos)
            reposition(animated: true)
        }

        /// Computes the exterior tab rect flush against the outside edge of `parent`.
        /// Note: AppKit coordinates have Y=0 at the bottom, whereas `normalizedPosition`
        /// has `0.0` near the top and `1.0` near the bottom (matching SwiftUI).
        static func handleFrame(
            for parent: NSWindow,
            side: EngineFrameSide,
            normalizedPosition: Double
        ) -> NSRect {
            let w = EngineFrameView.handleWidth
            let h = EngineFrameView.handleHeight
            let overlap = EngineFrameView.handleOverlapIntoParent
            let topInset: CGFloat = 54    // stay clear of macOS titlebar & traffic lights
            let bottomInset: CGFloat = 22
            let minY = parent.frame.minY + bottomInset
            let maxY = max(minY, parent.frame.maxY - topInset - h)
            let clamped = CGFloat(OmniVoicePreferences.clampedHandlePosition(normalizedPosition))
            let y = round(maxY - (clamped * (maxY - minY)))

            let x: CGFloat
            switch side {
            case .right:
                x = round(parent.frame.maxX - overlap)
            case .left:
                x = round(parent.frame.minX - w + overlap)
            }
            return NSRect(x: x, y: y, width: w, height: h)
        }

        private static func normalizedPosition(forScreenY screenY: CGFloat, in parent: NSWindow) -> Double {
            let h = EngineFrameView.handleHeight
            let topInset: CGFloat = 54
            let bottomInset: CGFloat = 22
            let minCenterY = parent.frame.minY + bottomInset + (h / 2)
            let maxCenterY = max(minCenterY + 1, parent.frame.maxY - topInset - (h / 2))
            let clampedY = min(max(screenY, minCenterY), maxCenterY)
            let normalized = Double((maxCenterY - clampedY) / (maxCenterY - minCenterY))
            return OmniVoicePreferences.clampedHandlePosition(normalized)
        }
    }
}

private struct ExteriorPullTabView: View {
    let theme: OmniVoiceTheme
    let side: EngineFrameSide
    let isExpanded: Bool
    let onClick: () -> Void
    let onDragChanged: (NSPoint) -> Void
    let onDragEnded: (NSPoint) -> Void

    @State private var isHovered = false
    @State private var dragStartMouse: NSPoint?

    var body: some View {
        let accent = Color(themeColor: theme.accentColor)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: side == .left ? 14 : 0,
            bottomLeadingRadius: side == .left ? 14 : 0,
            bottomTrailingRadius: side == .right ? 14 : 0,
            topTrailingRadius: side == .right ? 14 : 0,
            style: .continuous
        )

        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(accent.opacity(isHovered || isExpanded ? 1.0 : 0.85))
                .frame(width: 2.5, height: 28)
                .shadow(color: accent.opacity(isHovered || isExpanded ? 0.65 : 0.38), radius: 8)

            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovered || isExpanded ? accent : accent.opacity(0.88))
        }
        .frame(width: EngineFrameView.handleWidth, height: EngineFrameView.handleHeight)
        .background {
            ExteriorPullTabSurface(theme: theme, shape: shape, isHighlighted: isHovered || isExpanded)
        }
        .clipShape(shape)
        .contentShape(shape)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    let mouse = NSEvent.mouseLocation
                    if dragStartMouse == nil {
                        dragStartMouse = mouse
                    } else if let start = dragStartMouse, hypot(mouse.x - start.x, mouse.y - start.y) >= 5 {
                        onDragChanged(mouse)
                    }
                }
                .onEnded { _ in
                    let mouse = NSEvent.mouseLocation
                    let start = dragStartMouse ?? mouse
                    dragStartMouse = nil
                    if hypot(mouse.x - start.x, mouse.y - start.y) < 5 {
                        onClick()
                    } else {
                        onDragEnded(mouse)
                    }
                }
        )
        .help(isExpanded ? "Close transcript history (drag to move or switch side)" : "Open transcript history (drag to move or switch side)")
    }

    private var iconName: String {
        if isExpanded {
            return side == .right ? "chevron.compact.left" : "chevron.compact.right"
        }
        return "bubble.left.and.text.bubble.right"
    }
}

private struct ExteriorPullTabSurface: View {
    let theme: OmniVoiceTheme
    let shape: UnevenRoundedRectangle
    let isHighlighted: Bool

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        let accent = Color(themeColor: theme.accentColor)
        let rimOpacity: Double = isHighlighted ? 0.55 : 0.24

        if #available(macOS 26.0, *), theme.look.usesGlassMaterial {
            Color.clear
                .glassEffect(
                    .regular
                        .tint(Color(themeColor: theme.surfaceTint).opacity(isHighlighted ? 0.16 : 0.09))
                        .interactive(),
                    in: shape
                )
                .overlay {
                    shape.stroke(accent.opacity(rimOpacity), lineWidth: 1)
                }
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    shape.fill((colorScheme == .dark ? Color.black : Color.white).opacity(colorScheme == .dark ? 0.28 : 0.45))
                }
                .overlay {
                    shape.stroke(accent.opacity(rimOpacity), lineWidth: 1)
                }
        }
    }
}

private final class ExteriorHandleAnchorNSView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
