import AppKit
import Observation
import OmniVoiceCore
import SwiftUI

@MainActor
@Observable
final class CaptionOverlayState {
    var text = ""
    var styleName = ""
    var translationStatus: String?
    var level: Float = 0
    var theme: OmniVoiceTheme = .defaultTheme
    var appearanceMode: AppAppearanceMode = .system
    var glassOpacity: Double = 0.05
    var phase: CaptionOverlayPhase = .live
    var appearanceToken = 0
}

@MainActor
final class CaptionOverlayWindow: NSObject, NSWindowDelegate {
    private enum DefaultsKey {
        static let originX = "CaptionOverlayWindow.originX"
        static let originY = "CaptionOverlayWindow.originY"
        static let centerX = "CaptionOverlayWindow.centerX"
        static let centerY = "CaptionOverlayWindow.centerY"
    }

    private struct Presentation {
        let text: String
        let styleName: String
        let translationStatus: String?
        let level: Float
        let theme: OmniVoiceTheme
        let appearanceMode: AppAppearanceMode
        let anchorFrame: CGRect?
    }

    private var window: NSPanel?
    private var hostingView: DraggableCaptionHostingView?
    private let state = CaptionOverlayState()
    private var presentation: Presentation?
    private var commitHideTask: Task<Void, Never>?

    func show(
        text: String,
        styleName: String,
        translationStatus: String? = nil,
        level: Float = 0,
        theme: OmniVoiceTheme,
        appearanceMode: AppAppearanceMode,
        glassOpacity: Double = 0.05,
        anchorFrame: CGRect? = nil
    ) {
        commitHideTask?.cancel()
        commitHideTask = nil

        let wasLiveAndVisible = window?.isVisible == true && state.phase == .live
        let previousAnchorFrame = presentation?.anchorFrame
        presentation = Presentation(
            text: text,
            styleName: styleName,
            translationStatus: translationStatus,
            level: level,
            theme: theme,
            appearanceMode: appearanceMode,
            anchorFrame: anchorFrame
        )

        state.text = text
        state.styleName = styleName
        state.translationStatus = translationStatus
        state.level = level
        state.theme = theme
        state.appearanceMode = appearanceMode
        state.glassOpacity = glassOpacity
        state.phase = .live
        if !wasLiveAndVisible {
            state.appearanceToken &+= 1
        }

        let hosting: DraggableCaptionHostingView
        if let existing = hostingView {
            hosting = existing
        } else {
            let created = DraggableCaptionHostingView(rootView: CaptionOverlayLiveHost(state: state))
            hostingView = created
            hosting = created
        }

        hosting.layoutSubtreeIfNeeded()
        let targetSize = hosting.fittingSize
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let currentCenter = previousAnchorFrame == nil ? window?.frame.center ?? savedCenter : savedCenter
        let origin: CGPoint
        if let anchorFrame {
            origin = CaptionOverlayPlacement.caretAnchoredOrigin(
                caretFrame: anchorFrame,
                screenFrame: screenFrame,
                overlaySize: targetSize
            )
        } else {
            origin = CaptionOverlayPlacement.resolvedOrigin(
                savedCenter: currentCenter,
                savedOrigin: savedOrigin,
                screenFrame: screenFrame,
                overlaySize: targetSize
            )
        }

        if window == nil {
            let created = NSPanel(
                contentRect: CGRect(origin: origin, size: targetSize),
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
            created.isMovableByWindowBackground = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.delegate = self
            created.contentView = hosting
            window = created
        }

        // Pin the floating panel's appearance so the glass material AND the SwiftUI
        // colorScheme environment match the resolved mode. Without this the borderless
        // panel's colorScheme resolved to dark under a light system -> white caption text
        // on the light background.
        window?.appearance = Self.resolvedAppearance(for: appearanceMode)
        window?.alphaValue = 1
        let targetFrame = CGRect(origin: origin, size: targetSize)
        if let currentFrame = window?.frame,
           abs(currentFrame.origin.x - targetFrame.origin.x) > 0.5
            || abs(currentFrame.origin.y - targetFrame.origin.y) > 0.5
            || abs(currentFrame.width - targetFrame.width) > 0.5
            || abs(currentFrame.height - targetFrame.height) > 0.5 {
            window?.setFrame(targetFrame, display: true)
        }
        window?.orderFrontRegardless()
    }

    private static func resolvedAppearance(for mode: AppAppearanceMode) -> NSAppearance? {
        switch mode {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: NSApp.effectiveAppearance
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow else { return }
        guard presentation?.anchorFrame == nil else { return }
        saveCenter(movedWindow.frame.center)
    }

    func updateGlassOpacity(_ opacity: Double) {
        state.glassOpacity = opacity
    }

    func hide() {
        commitHideTask?.cancel()
        commitHideTask = nil
        state.phase = .live
        window?.orderOut(nil)
    }

    func commitSourceFrame() -> CGRect? {
        window?.frame
    }

    func preferredHotMenuCenter() -> CGPoint {
        if let window {
            return window.frame.center
        }

        if let savedCenter {
            return savedCenter
        }

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let overlaySize = CGSize(
            width: CaptionOverlayLayout.windowMaxWidth,
            height: 160
        )
        return CaptionOverlayPlacement.defaultCenter(
            screenFrame: screenFrame,
            overlaySize: overlaySize
        )
    }

    func commitAndHide(mode: CommitAnimationMode) {
        guard let window else { return }
        guard mode != .none else {
            hide()
            return
        }
        guard let presentation else {
            hide()
            return
        }

        commitHideTask?.cancel()
        commitHideTask = nil

        let originalFrame = window.frame
        state.phase = .committing(mode)
        window.orderFrontRegardless()

        if mode == .magicPoof {
            // Keep the full spacious panel frame so stardust particles and mist rings
            // can burst outward cleanly without clipping against the window bounds.
            let poofDuration = duration(for: mode) + 0.06
            commitHideTask = Task { @MainActor [weak self, weak window] in
                try? await Task.sleep(for: .seconds(poofDuration))
                guard !Task.isCancelled, let self, let window else { return }
                window.orderOut(nil)
                window.alphaValue = 1
                self.state.phase = .live
                if self.presentation?.anchorFrame == nil {
                    self.saveCenter(originalFrame.center)
                }
                self.presentation = nil
                self.commitHideTask = nil
            }
            return
        }

        let targetFrame = commitTargetFrame(
            from: originalFrame,
            anchorFrame: presentation.anchorFrame,
            mode: mode
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration(for: mode)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0.02
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                guard let self, let window else { return }
                guard self.state.phase == .committing(mode) else { return }
                window.orderOut(nil)
                window.alphaValue = 1
                window.setFrame(originalFrame, display: false)
                self.state.phase = .live
                if self.presentation?.anchorFrame == nil {
                    self.saveCenter(originalFrame.center)
                }
                self.presentation = nil
            }
        }
    }

    private var savedOrigin: CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: DefaultsKey.originX) != nil,
              defaults.object(forKey: DefaultsKey.originY) != nil else {
            return nil
        }

        return CGPoint(
            x: defaults.double(forKey: DefaultsKey.originX),
            y: defaults.double(forKey: DefaultsKey.originY)
        )
    }

    private var savedCenter: CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: DefaultsKey.centerX) != nil,
              defaults.object(forKey: DefaultsKey.centerY) != nil else {
            return nil
        }

        return CGPoint(
            x: defaults.double(forKey: DefaultsKey.centerX),
            y: defaults.double(forKey: DefaultsKey.centerY)
        )
    }

    private func saveCenter(_ center: CGPoint) {
        let defaults = UserDefaults.standard
        defaults.set(center.x, forKey: DefaultsKey.centerX)
        defaults.set(center.y, forKey: DefaultsKey.centerY)
    }

    private func commitTargetFrame(from frame: CGRect, anchorFrame: CGRect?, mode: CommitAnimationMode) -> CGRect {
        let center = anchorFrame?.center ?? frame.center
        let size: CGSize
        let yOffset: CGFloat

        switch mode {
        case .magicPoof:
            size = frame.size
            yOffset = 0
        case .glyphStream:
            size = CGSize(width: max(120, frame.width * 0.36), height: max(22, frame.height * 0.34))
            yOffset = 18
        case .beamSnap:
            size = CGSize(width: 96, height: 8)
            yOffset = 6
        case .cometCollapse:
            size = CGSize(width: 28, height: 28)
            yOffset = 28
        case .none:
            size = frame.size
            yOffset = 0
        }

        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2 + (anchorFrame == nil ? yOffset : 0),
            width: size.width,
            height: size.height
        )
    }

    private func duration(for mode: CommitAnimationMode) -> TimeInterval {
        switch mode {
        case .magicPoof:
            0.58
        case .glyphStream:
            0.52
        case .beamSnap:
            0.42
        case .cometCollapse:
            0.58
        case .none:
            0
        }
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private final class DraggableCaptionHostingView: NSHostingView<CaptionOverlayLiveHost> {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
