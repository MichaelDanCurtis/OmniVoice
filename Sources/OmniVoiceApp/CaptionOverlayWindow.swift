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

    private var window: NSWindow?

    func show(text: String, styleName: String, level: Float = 0, theme: OmniVoiceTheme) {
        let content = DraggableCaptionHostingView(
            rootView: CaptionOverlayView(text: text, styleName: styleName, level: level, theme: theme)
        )
        let targetSize = content.fittingSize
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let currentCenter = window?.frame.center ?? savedCenter
        let origin = CaptionOverlayPlacement.resolvedOrigin(
            savedCenter: currentCenter,
            savedOrigin: savedOrigin,
            screenFrame: screenFrame,
            overlaySize: targetSize
        )

        if window == nil {
            let created = NSWindow(
                contentRect: CGRect(origin: origin, size: targetSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isOpaque = false
            created.backgroundColor = .clear
            created.level = .floating
            created.ignoresMouseEvents = false
            created.isMovableByWindowBackground = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.delegate = self
            window = created
        }

        window?.contentView = content
        window?.setFrame(CGRect(origin: origin, size: targetSize), display: true)
        window?.orderFrontRegardless()
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow else { return }
        saveCenter(movedWindow.frame.center)
    }

    func hide() {
        window?.orderOut(nil)
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
