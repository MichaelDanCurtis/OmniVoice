import AppKit
import CoreGraphics
import OmniVoiceCore
import SwiftUI

/// Click-through floating "Ghost Ring" overlay that briefly flashes an animated
/// glowing highlight around any UI element clicked by hands-free Command Mode.
@MainActor
final class CommandTargetHighlightWindow {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func flash(axRect: CGRect, label: String, theme: OmniVoiceTheme) {
        hideTask?.cancel()
        hideTask = nil

        let cocoaRect = Self.axRectToAppKit(axRect)
        let padding: CGFloat = 14
        let panelRect = cocoaRect.insetBy(dx: -padding, dy: -padding)
        let accent = Color(themeColor: theme.accentColor)
        let secondary = Color(themeColor: theme.secondaryAccentColor)

        let panel = self.panel ?? makePanel(frame: panelRect)
        self.panel = panel
        panel.setFrame(panelRect, display: true)
        panel.contentView = NSHostingView(
            rootView: CommandTargetGhostRingView(
                accent: accent,
                secondary: secondary,
                label: label
            )
        )
        panel.orderFrontRegardless()

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    /// Converts macOS Accessibility top-left screen coordinates to AppKit bottom-left coordinates.
    private static func axRectToAppKit(_ axRect: CGRect) -> NSRect {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let clampedWidth = max(24, axRect.width)
        let clampedHeight = max(24, axRect.height)
        let originY = primaryHeight - (axRect.origin.y + clampedHeight)
        return NSRect(x: axRect.origin.x, y: originY, width: clampedWidth, height: clampedHeight)
    }
}

private struct CommandTargetGhostRingView: View {
    let accent: Color
    let secondary: Color
    let label: String

    @State private var expanded = false
    @State private var fadedOut = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accent, secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: expanded ? 1.5 : 3.2
                )
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(expanded ? 0.04 : 0.16))
                )
                .shadow(color: accent.opacity(0.65), radius: expanded ? 12 : 6)
                .padding(10)
                .scaleEffect(expanded ? 1.07 : 0.94)
                .opacity(fadedOut ? 0.0 : 1.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                expanded = true
            }
            withAnimation(.easeOut(duration: 0.24).delay(0.20)) {
                fadedOut = true
            }
        }
    }
}
