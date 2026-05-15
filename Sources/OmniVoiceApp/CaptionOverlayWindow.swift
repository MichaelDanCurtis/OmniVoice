import AppKit
import SwiftUI

@MainActor
final class CaptionOverlayWindow {
    private var window: NSWindow?

    func show(text: String, styleName: String, level: Float = 0) {
        let content = NSHostingView(rootView: CaptionOverlayView(text: text, styleName: styleName, level: level))
        let targetSize = content.fittingSize
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screenFrame.midX - targetSize.width / 2,
            y: screenFrame.minY + 72
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
            created.ignoresMouseEvents = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window = created
        }

        window?.contentView = content
        window?.setFrame(CGRect(origin: origin, size: targetSize), display: true)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}
