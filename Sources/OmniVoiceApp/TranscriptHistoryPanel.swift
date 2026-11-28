import AppKit
import SwiftUI
import OmniVoiceCore

/// Hosts the Transcript History drawer in a borderless, floating Liquid Glass `NSPanel`
/// attached cleanly outside the left or right edge of the main Settings window.
struct TranscriptHistoryFloatingPanelBridge: NSViewRepresentable {
    @Bindable var model: AppModel
    let side: EngineFrameSide
    @Binding var isExpanded: Bool
    let insertTranscript: (EngineTranscriptRecord) -> Void
    let copyTranscript: (EngineTranscriptRecord) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        PassthroughAnchorNSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let expanded = isExpanded
        let targetSide = side
        let appModel = model
        let closeAction: () -> Void = {
            isExpanded = false
        }

        DispatchQueue.main.async {
            guard let parentWindow = nsView.window else {
                if !expanded {
                    coordinator.hide()
                }
                return
            }

            if expanded {
                coordinator.show(
                    attachedTo: parentWindow,
                    side: targetSide,
                    model: appModel,
                    insertTranscript: insertTranscript,
                    copyTranscript: copyTranscript,
                    onClose: closeAction
                )
            } else {
                coordinator.hide()
            }
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
        private var resizeObserver: NSObjectProtocol?

        func show(
            attachedTo parentWindow: NSWindow,
            side: EngineFrameSide,
            model: AppModel,
            insertTranscript: @escaping (EngineTranscriptRecord) -> Void,
            copyTranscript: @escaping (EngineTranscriptRecord) -> Void,
            onClose: @escaping () -> Void
        ) {
            let rootView = FloatingTranscriptHistoryContent(
                model: model,
                insertTranscript: insertTranscript,
                copyTranscript: copyTranscript,
                onClose: onClose
            )
            .preferredColorScheme(model.preferences.appearanceMode.colorScheme)

            let panel: NSPanel
            if let existing = self.panel {
                panel = existing
                if let hosting = existing.contentView as? NSHostingView<AnyView> {
                    hosting.rootView = AnyView(rootView)
                } else {
                    existing.contentView = NSHostingView(rootView: AnyView(rootView))
                }
            } else {
                let created = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: EngineFrameView.drawerWidth, height: 620),
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
                created.contentView = NSHostingView(rootView: AnyView(rootView))
                self.panel = created
                panel = created
            }

            let targetFrame = Self.panelFrame(for: parentWindow, side: side)
            let wasVisible = panel.isVisible

            if attachedParent !== parentWindow {
                if let previousParent = attachedParent {
                    previousParent.removeChildWindow(panel)
                }
                if let resizeObserver {
                    NotificationCenter.default.removeObserver(resizeObserver)
                    self.resizeObserver = nil
                }
                attachedParent = parentWindow
                parentWindow.addChildWindow(panel, ordered: .above)
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: parentWindow,
                    queue: .main
                ) { [weak self, weak parentWindow] _ in
                    Task { @MainActor in
                        guard let self, let parentWindow, let panel = self.panel, panel.isVisible else { return }
                        let currentSide = model.activeTheme.engineFrameSide
                        panel.setFrame(Self.panelFrame(for: parentWindow, side: currentSide), display: true)
                    }
                }
            }

            if !wasVisible {
                var startFrame = targetFrame
                startFrame.origin.x += (side == .right ? -14 : 14)
                panel.alphaValue = 0
                panel.setFrame(startFrame, display: true)
                panel.orderFront(nil)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                    panel.animator().setFrame(targetFrame, display: true)
                }
            } else if abs(panel.frame.origin.x - targetFrame.origin.x) > 1
                        || abs(panel.frame.origin.y - targetFrame.origin.y) > 1
                        || abs(panel.frame.height - targetFrame.height) > 1 {
                panel.setFrame(targetFrame, display: true, animate: true)
            }
        }

        func hide() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            guard let panel else { return }
            if let parent = attachedParent {
                parent.removeChildWindow(panel)
            }
            attachedParent = nil
            panel.orderOut(nil)
        }

        private static func panelFrame(for parent: NSWindow, side: EngineFrameSide) -> NSRect {
            // Leave room for the exterior sticking-out pull-tab so clicking the tab to open
            // and clicking again to close never gets covered by the drawer.
            let gap: CGFloat = EngineFrameView.handleWidth - EngineFrameView.handleOverlapIntoParent + 8
            let verticalInset: CGFloat = 14
            let width = EngineFrameView.drawerWidth
            let height = max(420, parent.frame.height - (verticalInset * 2))
            let y = parent.frame.origin.y + verticalInset
            var x: CGFloat = side == .right
                ? parent.frame.maxX + gap
                : parent.frame.minX - width - gap

            if let screenFrame = (parent.screen ?? NSScreen.main)?.visibleFrame {
                if side == .right, x + width > screenFrame.maxX {
                    x = max(screenFrame.minX + 8, screenFrame.maxX - width - 8)
                } else if side == .left, x < screenFrame.minX {
                    x = screenFrame.minX + 8
                }
            }

            return NSRect(x: x, y: y, width: width, height: height)
        }
    }
}

private struct FloatingTranscriptHistoryContent: View {
    @Bindable var model: AppModel
    let insertTranscript: (EngineTranscriptRecord) -> Void
    let copyTranscript: (EngineTranscriptRecord) -> Void
    let onClose: () -> Void

    private var theme: OmniVoiceTheme {
        model.activeTheme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Conversation")
                        .font(.caption.weight(.semibold))
                        .themeAccentForeground(theme)
                        .textCase(.uppercase)
                    Text("Transcript History")
                        .font(.title3.weight(.bold))
                        .fontDesign(theme.look.headerFontDesign)
                    Text("\(model.transcripts.count) recent dictations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        Task { await model.refreshTranscripts() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Refresh conversation history")

                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Close transcript history")
                }
            }

            if model.transcripts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .themeAccentForeground(theme)
                    Text("No transcripts yet")
                        .font(.headline)
                    Text("Dictated text from the engine will appear here with copy and insert controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .themeSurface(theme, cornerRadius: 10, strong: false)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.transcripts) { transcript in
                            FloatingTranscriptCard(
                                transcript: transcript,
                                theme: theme,
                                copyTranscript: copyTranscript,
                                insertTranscript: insertTranscript,
                                askAITranscript: model.addTranscriptToAskAI
                            )
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themeSurface(theme, cornerRadius: 18, strong: true, interactive: false)
        .padding(4)
    }
}

private struct FloatingTranscriptCard: View {
    let transcript: EngineTranscriptRecord
    let theme: OmniVoiceTheme
    let copyTranscript: (EngineTranscriptRecord) -> Void
    let insertTranscript: (EngineTranscriptRecord) -> Void
    let askAITranscript: (EngineTranscriptRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(transcript.displayText)
                .font(.callout)
                .fontDesign(theme.look.bodyFontDesign)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if let style = transcript.style, !style.isEmpty {
                    Text(style)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copyTranscript(transcript)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")

                Button {
                    insertTranscript(transcript)
                } label: {
                    Image(systemName: "text.insert")
                }
                .help("Insert at cursor")

                Button {
                    askAITranscript(transcript)
                } label: {
                    Image(systemName: "sparkles")
                }
                .help("Ask AI")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSurface(theme, cornerRadius: 12, strong: false, interactive: false)
    }
}

private final class PassthroughAnchorNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
