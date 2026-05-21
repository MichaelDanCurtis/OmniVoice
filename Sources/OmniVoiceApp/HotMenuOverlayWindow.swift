import AppKit
import Observation
import OmniVoiceCore
import SwiftUI

@MainActor
final class HotMenuOverlayWindow {
    private static let menuSize = CGSize(width: 380, height: 318)
    private static let deadZoneRadius = 34.0
    private static let mouseOverrideDistance = 6.0
    private static let selectionAnimation = Animation.interpolatingSpring(
        mass: 0.72,
        stiffness: 166,
        damping: 21,
        initialVelocity: 0
    )

    private var window: NSWindow?
    private let overlayState = HotMenuOverlayState()
    private var timer: Timer?
    private var center: CGPoint = .zero
    private var theme: OmniVoiceTheme = .defaultTheme
    private var actions: [HotMenuDirection: [HotMenuAction]] = [:]
    private var actionLabels: [HotMenuAction: String] = [:]
    private var selectionState = HotMenuActionRingState()
    private var presentationMode: HotMenuPresentationMode = .momentary
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var lastMouseLocation: CGPoint = .zero
    private var selectionSource: SelectionSource = .mouse
    private var onConfirm: (() -> Void)?
    private var onCancel: (() -> Void)?

    var isPresented: Bool {
        window?.isVisible == true
    }

    func show(
        center requestedCenter: CGPoint,
        theme: OmniVoiceTheme,
        actions: [HotMenuDirection: [HotMenuAction]],
        actionLabels: [HotMenuAction: String],
        mode: HotMenuPresentationMode,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.theme = theme
        self.actions = actions
        self.actionLabels = actionLabels
        self.selectionState = HotMenuActionRingState()
        self.presentationMode = mode
        self.lastMouseLocation = NSEvent.mouseLocation
        self.selectionSource = .mouse
        self.onConfirm = onConfirm
        self.onCancel = onCancel

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = CaptionOverlayPlacement.origin(
            forCenter: requestedCenter,
            screenFrame: screenFrame,
            overlaySize: Self.menuSize
        )
        center = CGPoint(
            x: origin.x + Self.menuSize.width / 2,
            y: origin.y + Self.menuSize.height / 2
        )

        if window == nil {
            let created = NSWindow(
                contentRect: CGRect(origin: origin, size: Self.menuSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.level = .floating
            created.ignoresMouseEvents = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.contentView = NSHostingView(rootView: HotMenuOverlayView(state: overlayState))
            window = created
        }

        overlayState.configure(theme: theme, actions: actions, actionLabels: actionLabels, presentationMode: mode)
        window?.alphaValue = 1
        window?.setFrame(CGRect(origin: origin, size: Self.menuSize), display: true)
        window?.orderFrontRegardless()
        startTracking()
        installKeyMonitors()
    }

    func finish() -> HotMenuAction? {
        tearDownInteraction()
        window?.orderOut(nil)
        return selectionState.selectedAction(in: actions)
    }

    func cancel() {
        tearDownInteraction()
        selectionState = HotMenuActionRingState()
        window?.orderOut(nil)
    }

    func select(_ direction: HotMenuDirection, cycleIfSameDirection: Bool = true) {
        selectionSource = .keyboard
        selectionState.select(direction, cycleIfSameDirection: cycleIfSameDirection, actions: actions)
        updateOverlaySelection()
    }

    private func startTracking() {
        stopTracking()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 45.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSelection()
            }
        }
        updateSelection()
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
    }

    private func tearDownInteraction() {
        stopTracking()
        removeKeyMonitors()
        onConfirm = nil
        onCancel = nil
    }

    private func updateSelection() {
        let mouse = NSEvent.mouseLocation
        if selectionSource == .keyboard,
           hypot(mouse.x - lastMouseLocation.x, mouse.y - lastMouseLocation.y) < Self.mouseOverrideDistance {
            return
        }

        selectionSource = .mouse
        lastMouseLocation = mouse
        let nextDirection = HotMenuSelection.direction(
            deltaX: Double(mouse.x - center.x),
            deltaY: Double(mouse.y - center.y),
            deadZoneRadius: Self.deadZoneRadius
        )

        guard nextDirection != selectionState.selectedDirection else {
            return
        }

        selectionState.select(nextDirection, cycleIfSameDirection: false, actions: actions)
        updateOverlaySelection()
    }

    private func updateOverlaySelection() {
        withAnimation(Self.selectionAnimation) {
            overlayState.selectionState = selectionState
        }
    }

    private func installKeyMonitors() {
        removeKeyMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            _ = self?.handleKeyDown(event)
        }
    }

    private func removeKeyMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        localKeyMonitor = nil
        globalKeyMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126:
            select(.up)
        case 123:
            select(.left)
        case 124:
            select(.right)
        case 125:
            select(.down)
        case 36, 76:
            onConfirm?()
        case 53:
            onCancel?()
        default:
            return false
        }

        return true
    }

    private enum SelectionSource {
        case mouse
        case keyboard
    }
}

@MainActor
@Observable
private final class HotMenuOverlayState {
    var actions: [HotMenuDirection: [HotMenuAction]] = [:]
    var actionLabels: [HotMenuAction: String] = [:]
    var selectionState = HotMenuActionRingState()
    var presentationMode: HotMenuPresentationMode = .momentary
    var theme: OmniVoiceTheme = .defaultTheme

    func configure(
        theme: OmniVoiceTheme,
        actions: [HotMenuDirection: [HotMenuAction]],
        actionLabels: [HotMenuAction: String],
        presentationMode: HotMenuPresentationMode
    ) {
        self.theme = theme
        self.actions = actions
        self.actionLabels = actionLabels
        self.presentationMode = presentationMode
        selectionState = HotMenuActionRingState()
    }
}

private struct HotMenuOverlayView: View {
    var state: HotMenuOverlayState

    @Namespace private var glassNamespace
    @Environment(\.colorScheme) private var colorScheme

    private let horizontalRadius: CGFloat = 132
    private let verticalRadius: CGFloat = 102
    private var actions: [HotMenuDirection: [HotMenuAction]] { state.actions }
    private var actionLabels: [HotMenuAction: String] { state.actionLabels }
    private var selectionState: HotMenuActionRingState { state.selectionState }
    private var presentationMode: HotMenuPresentationMode { state.presentationMode }
    private var theme: OmniVoiceTheme { state.theme }
    private var palette: ResolvedThemePalette { theme.resolvedPalette(for: colorScheme) }
    private var accent: Color { Color(themeColor: palette.accentGraphic) }
    private var secondary: Color { Color(themeColor: palette.secondaryAccentGraphic) }
    private var accentText: Color { Color(themeColor: palette.accentText) }
    private var tint: Color { Color(themeColor: theme.surfaceTint) }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 22) {
                    menuContent
                }
            } else {
                menuContent
            }
        }
        .padding(22)
        .frame(width: 380, height: 318)
    }

    private var menuContent: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(selectionState.selectedDirection == nil ? 0.08 : 0.14),
                            secondary.opacity(0.045),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 166
                    )
                )
                .frame(width: 328, height: 250)
                .blur(radius: 22)
                .opacity(0.58)

            ForEach(HotMenuDirection.allCases, id: \.self) { direction in
                let directionActions = selectionState.actionsForDirection(direction, actions: actions)
                if !directionActions.isEmpty {
                    HotMenuOptionHint(
                        direction: direction,
                        actions: directionActions,
                        selectedIndex: selectionState.selectedIndex(for: direction, actions: actions),
                        actionLabels: actionLabels,
                        isSelected: direction == selectionState.selectedDirection,
                        accent: accent,
                        accentText: accentText,
                        secondary: secondary,
                        tint: tint,
                        isMenuActive: selectionState.selectedDirection != nil
                    )
                    .offset(offset(for: direction))
                    .hotMenuGlassID("hot-menu-slot-\(direction.rawValue)", in: glassNamespace)
                }
            }

            HotMenuFocusBlob(
                selectedDirection: selectionState.selectedDirection,
                selectedAction: selectionState.selectedAction(in: actions),
                selectedActionLabel: selectedActionLabel,
                selectedIndex: selectedIndex,
                actionCount: selectedActionCount,
                centerText: centerText,
                accent: accent,
                accentText: accentText,
                secondary: secondary,
                tint: tint
            )
            .offset(focusOffset)
            .hotMenuGlassID("hot-menu-focus", in: glassNamespace)
            .animation(.interpolatingSpring(mass: 0.72, stiffness: 166, damping: 21), value: selectionState.selectedDirection)
            .animation(.smooth(duration: 0.18), value: selectedIndex)
        }
    }

    private var centerText: String {
        switch (presentationMode, selectionState.selectedDirection) {
        case (.latched, nil):
            "Arrow to choose"
        case (.latched, _):
            "Arrow cycles"
        case (.momentary, nil):
            "Release to cancel"
        case (.momentary, _):
            "Release to run"
        }
    }

    private var selectedIndex: Int {
        guard let direction = selectionState.selectedDirection else {
            return 0
        }
        return selectionState.selectedIndex(for: direction, actions: actions)
    }

    private var selectedActionCount: Int {
        guard let direction = selectionState.selectedDirection else {
            return 0
        }
        return selectionState.actionsForDirection(direction, actions: actions).count
    }

    private var selectedActionLabel: String? {
        guard let action = selectionState.selectedAction(in: actions) else {
            return nil
        }
        return actionLabels[action] ?? action.displayName
    }

    private var focusOffset: CGSize {
        guard let direction = selectionState.selectedDirection else {
            return .zero
        }

        let distance: CGFloat = 24
        switch direction {
        case .up:
            return CGSize(width: 0, height: -distance)
        case .left:
            return CGSize(width: -distance, height: 0)
        case .right:
            return CGSize(width: distance, height: 0)
        case .down:
            return CGSize(width: 0, height: distance)
        }
    }

    private func offset(for direction: HotMenuDirection) -> CGSize {
        switch direction {
        case .up:
            CGSize(width: 0, height: -verticalRadius)
        case .left:
            CGSize(width: -horizontalRadius, height: 0)
        case .right:
            CGSize(width: horizontalRadius, height: 0)
        case .down:
            CGSize(width: 0, height: verticalRadius)
        }
    }
}

private struct HotMenuFocusBlob: View {
    let selectedDirection: HotMenuDirection?
    let selectedAction: HotMenuAction?
    let selectedActionLabel: String?
    let selectedIndex: Int
    let actionCount: Int
    let centerText: String
    let accent: Color
    let accentText: Color
    let secondary: Color
    let tint: Color

    var body: some View {
        let isActive = selectedDirection != nil

        VStack(spacing: 5) {
            Image(systemName: selectedAction?.systemImage ?? "circle.grid.cross")
                .font(.system(size: selectedDirection == nil ? 24 : 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? accentText : Color.primary.opacity(0.82))

            Text(selectedActionLabel ?? selectedAction?.displayName ?? centerText)
                .font(.system(size: selectedDirection == nil ? 11 : 12.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.82))

            if let selectedDirection {
                Text(actionDetail(for: selectedDirection))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accentText.opacity(0.92))
            }
        }
        .frame(width: 108, height: 108)
        .hotMenuGlassSurface(
            accent: accent,
            secondary: secondary,
            tint: tint,
            fillOpacity: selectedDirection == nil ? 0.028 : 0.045,
            edgeOpacity: selectedDirection == nil ? 0.10 : 0.18,
            glowOpacity: selectedDirection == nil ? 0.10 : 0.20,
            shadowOpacity: 0.16,
            wispOpacity: selectedDirection == nil ? 0.18 : 0.32,
            wispRadius: selectedDirection == nil ? 14 : 20,
            wispScale: selectedDirection == nil ? 1.16 : 1.24,
            outlineOpacity: selectedDirection == nil ? 0 : 0.90,
            outlineWidth: selectedDirection == nil ? 0 : 2.2,
            shape: Circle(),
            interactive: true
        )
    }

    private func actionDetail(for direction: HotMenuDirection) -> String {
        if actionCount > 1 {
            return "\(direction.displayName) \(selectedIndex + 1)/\(actionCount)"
        }
        return direction.displayName
    }
}

private struct HotMenuOptionHint: View {
    let direction: HotMenuDirection
    let actions: [HotMenuAction]
    let selectedIndex: Int
    let actionLabels: [HotMenuAction: String]
    let isSelected: Bool
    let accent: Color
    let accentText: Color
    let secondary: Color
    let tint: Color
    let isMenuActive: Bool

    private var selectedAction: HotMenuAction {
        guard actions.indices.contains(selectedIndex) else {
            return .none
        }
        return actions[selectedIndex]
    }

    private var selectedActionLabel: String {
        actionLabels[selectedAction] ?? selectedAction.displayName
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(selectedActionLabel)
                .font(.system(size: isSelected ? 12 : 11, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.68)
                .foregroundStyle(isSelected ? Color.primary.opacity(0.92) : Color.primary.opacity(0.76))
        }
        .padding(.horizontal, 10)
        .frame(width: 104, height: 56)
        .hotMenuGlassSurface(
            accent: accent,
            secondary: secondary,
            tint: tint,
            fillOpacity: isSelected ? 0.036 : 0.016,
            edgeOpacity: isSelected ? 0.14 : 0.03,
            glowOpacity: isSelected ? 0.12 : 0.03,
            shadowOpacity: isSelected ? 0.10 : 0.04,
            wispOpacity: isSelected ? 0.22 : 0.10,
            wispRadius: isSelected ? 15 : 11,
            wispScale: isSelected ? 1.18 : 1.12,
            outlineOpacity: isSelected ? 0.70 : 0,
            outlineWidth: isSelected ? 1.4 : 0,
            shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
            interactive: true
        )
        .opacity(isSelected ? 1 : (isMenuActive ? 0.56 : 0.30))
        .scaleEffect(isSelected ? 1.02 : 0.92)
        .animation(.snappy(duration: 0.12), value: isSelected)
    }
}

private struct HotMenuGlassSurface<S: Shape>: ViewModifier {
    let accent: Color
    let secondary: Color
    let tint: Color
    let fillOpacity: Double
    let edgeOpacity: Double
    let glowOpacity: Double
    let shadowOpacity: Double
    let wispOpacity: Double
    let wispRadius: CGFloat
    let wispScale: CGFloat
    let outlineOpacity: Double
    let outlineWidth: CGFloat
    let shape: S
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    wispyEdge
                }
                .glassEffect(
                    .regular
                        .tint(tint.opacity(fillOpacity))
                        .interactive(interactive),
                    in: shape
                )
                .overlay {
                    readableAccentOutline
                }
                .shadow(color: accent.opacity(glowOpacity), radius: 18, x: 0, y: 8)
        } else {
            content
                .background {
                    wispyEdge
                }
                .background(.ultraThinMaterial, in: shape)
                .background(tint.opacity(fillOpacity), in: shape)
                .overlay {
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                accent.opacity(edgeOpacity),
                                secondary.opacity(edgeOpacity * 0.55),
                                Color.white.opacity(edgeOpacity * 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
                .overlay {
                    readableAccentOutline
                }
                .shadow(color: accent.opacity(glowOpacity), radius: 18, x: 0, y: 8)
                .shadow(color: .black.opacity(shadowOpacity), radius: 18, x: 0, y: 10)
        }
    }

    private var wispyEdge: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [
                        accent.opacity(wispOpacity),
                        tint.opacity(wispOpacity * 0.55),
                        secondary.opacity(wispOpacity * 0.30),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .scaleEffect(wispScale)
            .blur(radius: wispRadius)
            .opacity(wispOpacity > 0 ? 1 : 0)
    }

    private var readableAccentOutline: some View {
        ZStack {
            shape
                .stroke(accent.opacity(outlineOpacity * 0.34), lineWidth: outlineWidth + 8)
                .blur(radius: 7)

            shape
                .stroke(accent.opacity(outlineOpacity), lineWidth: outlineWidth)

            shape
                .stroke(Color.primary.opacity(outlineOpacity * 0.16), lineWidth: max(0.5, outlineWidth * 0.45))
                .blendMode(.overlay)
        }
        .opacity(outlineOpacity > 0 ? 1 : 0)
    }
}

private extension View {
    @ViewBuilder
    func hotMenuGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    func hotMenuGlassSurface<S: Shape>(
        accent: Color,
        secondary: Color,
        tint: Color,
        fillOpacity: Double,
        edgeOpacity: Double,
        glowOpacity: Double,
        shadowOpacity: Double,
        wispOpacity: Double,
        wispRadius: CGFloat,
        wispScale: CGFloat,
        outlineOpacity: Double,
        outlineWidth: CGFloat,
        shape: S,
        interactive: Bool
    ) -> some View {
        modifier(
            HotMenuGlassSurface(
                accent: accent,
                secondary: secondary,
                tint: tint,
                fillOpacity: fillOpacity,
                edgeOpacity: edgeOpacity,
                glowOpacity: glowOpacity,
                shadowOpacity: shadowOpacity,
                wispOpacity: wispOpacity,
                wispRadius: wispRadius,
                wispScale: wispScale,
                outlineOpacity: outlineOpacity,
                outlineWidth: outlineWidth,
                shape: shape,
                interactive: interactive
            )
        )
    }
}

private extension HotMenuAction {
    var systemImage: String {
        switch self {
        case .none, .selectionRewrite:
            "minus.circle"
        case .openConversation:
            "bubble.left.and.text.bubble.right"
        case .transcriptionMode:
            "captions.bubble"
        case .askAI:
            "sparkle.magnifyingglass"
        case .dictation:
            "mic"
        case .toggleTranslation, .translationOff, .translationOn:
            "globe"
        case .cycleTranslationLanguage:
            "globe.badge.chevron.backward"
        case .translationQuickTarget1, .translationQuickTarget2, .translationQuickTarget3, .translationQuickTarget4:
            "globe"
        case .cycleStyle, .styleNeutral, .styleProfessional, .styleConcise, .styleExpanded, .styleRaw:
            "paintbrush"
        case .cycleASRProvider:
            "waveform.badge.magnifyingglass"
        case .openDashboard:
            "gauge.with.dots.needle.33percent"
        }
    }
}
