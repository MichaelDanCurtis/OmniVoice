import AppKit
import OmniVoiceCore
import SwiftUI

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

    private var window: NSWindow?
    private var presentation: Presentation?

    func show(
        text: String,
        styleName: String,
        translationStatus: String? = nil,
        level: Float = 0,
        theme: OmniVoiceTheme,
        appearanceMode: AppAppearanceMode,
        anchorFrame: CGRect? = nil
    ) {
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
        let content = DraggableCaptionHostingView(
            rootView: CaptionOverlayView(
                text: text,
                styleName: styleName,
                translationStatus: translationStatus,
                level: level,
                theme: theme,
                appearanceMode: appearanceMode
            )
        )
        let targetSize = content.fittingSize
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
            let created = NSWindow(
                contentRect: CGRect(origin: origin, size: targetSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.level = .floating
            created.ignoresMouseEvents = false
            created.isMovableByWindowBackground = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.delegate = self
            window = created
        }

        window?.alphaValue = 1
        window?.contentView = content
        window?.setFrame(CGRect(origin: origin, size: targetSize), display: true)
        window?.orderFrontRegardless()
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow else { return }
        guard presentation?.anchorFrame == nil else { return }
        saveCenter(movedWindow.frame.center)
    }

    func hide() {
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

        let originalFrame = window.frame
        let targetFrame = commitTargetFrame(
            from: originalFrame,
            anchorFrame: presentation.anchorFrame,
            mode: mode
        )
        let content = DraggableCaptionHostingView(
            rootView: CaptionOverlayView(
                text: presentation.text,
                styleName: presentation.styleName,
                translationStatus: presentation.translationStatus,
                level: presentation.level,
                theme: presentation.theme,
                appearanceMode: presentation.appearanceMode,
                phase: .committing(mode)
            )
        )
        window.contentView = content
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration(for: mode)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0.02
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                guard let window else { return }
                window.orderOut(nil)
                window.alphaValue = 1
                window.setFrame(originalFrame, display: false)
                if self?.presentation?.anchorFrame == nil {
                    self?.saveCenter(originalFrame.center)
                }
                self?.presentation = nil
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

private final class DraggableCaptionHostingView: NSHostingView<CaptionOverlayView> {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
