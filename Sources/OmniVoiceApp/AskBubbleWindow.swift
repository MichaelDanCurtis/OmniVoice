import AppKit
import SwiftUI
import OmniVoiceCore

/// A liquid-glass bubble that shows an Ask AI question + streaming answer and lets
/// the user Insert / Copy / Dismiss by single keypress (I / C / D, plus Return / Esc)
/// or by the equivalent voice commands routed through `AskController`.
///
/// It is a non-activating key panel: it can become key to receive I/C/D without
/// stealing the focused app's first-responder status (so Insert still lands in the
/// original target) and without showing a Dock icon (it is borderless / non-`.titled`,
/// which the menu-bar-only Dock policy ignores).
@MainActor
final class AskBubbleWindow {
    var onInsert: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var panel: AskKeyPanel?
    private var hostingView: NSView?
    private let model = AskBubbleViewModel()
    private var lastHeight: CGFloat = 200
    private var relayoutWorkItem: DispatchWorkItem?
    /// The answer scroll caps here so the whole bubble stays within ~two-thirds of the screen.
    private let maxAnswerHeight: CGFloat = max(220, ((NSScreen.main?.visibleFrame.height ?? 900) * 2 / 3) - 120)
    /// ~Half the screen width (clamped), centered — the bubble grows downward, not sideways.
    private let bubbleWidth: CGFloat = min(max((NSScreen.main?.visibleFrame.width ?? 1440) * 0.5, 380), 900)

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(question: String, agentName: String) {
        model.agentName = agentName
        model.question = question
        model.answer = ""
        model.streaming = true
        model.error = nil
        model.statusNote = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        layout(height: lastHeight)
        performRelayout()
        panel.makeKeyAndOrderFront(nil)
    }

    func appendAnswer(_ chunk: String) { model.answer += chunk; relayout() }
    func setStreaming(_ streaming: Bool) { model.streaming = streaming; performRelayout() }
    func markInserted() { model.streaming = false; model.statusNote = "Inserted" }
    func markInsertFailed() { model.streaming = false; model.statusNote = "Copied — ⌘V to paste" }
    func showError(_ message: String) { model.streaming = false; model.error = message; performRelayout() }
    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> AskKeyPanel {
        let panel = AskKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: bubbleWidth, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onKey = { [weak self] key in
            switch key {
            case .insert: self?.onInsert?()
            case .copy: self?.onCopy?()
            case .dismiss: self?.onDismiss?()
            }
        }
        model.onInsert = { [weak self] in self?.onInsert?() }
        model.onCopy = { [weak self] in self?.onCopy?() }
        model.onDismiss = { [weak self] in self?.onDismiss?() }
        let hosting = FirstMouseHostingView(rootView: AskBubbleView(model: model, bubbleWidth: bubbleWidth))
        hostingView = hosting
        panel.contentView = hosting
        return panel
    }

    /// Size the panel to the measured content height (clamped) and keep its TOP edge
    /// pinned ~90pt below the screen top, horizontally centered, so it grows downward.
    private func layout(height: CGFloat) {
        guard let panel else { return }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = bubbleWidth
        let clamped = max(120, height)
        guard abs(clamped - panel.frame.height) > 0.5 || panel.frame.width != width else { return }
        lastHeight = clamped
        let topY = visible.maxY - 90
        let frame = NSRect(x: visible.midX - width / 2, y: topY - clamped, width: width, height: clamped)
        panel.setFrame(frame, display: true, animate: false)
    }

    /// Coalesces the per-chunk resize during streaming: re-measuring the whole answer and
    /// resizing the window on every token is O(n²). Debounce to ~12/s; one-time events
    /// (show / final / error) call performRelayout() directly for an immediate fit.
    private func relayout() {
        relayoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performRelayout() }
        relayoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// Measure the answer height in AppKit (reliable, unlike SwiftUI preferences inside a
    /// ScrollView), cap it, push it into the view, then size the panel to the hosting
    /// view's real fitting height on the next runloop — after SwiftUI applies the change.
    private func performRelayout() {
        relayoutWorkItem?.cancel()
        relayoutWorkItem = nil
        let contentWidth = bubbleWidth - 36
        let text: String
        if let error = model.error {
            text = error
        } else if model.answer.isEmpty && model.streaming {
            text = "Thinking…"
        } else {
            text = model.answer
        }
        let natural = measuredAnswerHeight(text, width: contentWidth)
        model.answerAreaHeight = min(max(natural + 6, 22), maxAnswerHeight)
        DispatchQueue.main.async { [weak self] in
            guard let self, let hosting = self.hostingView else { return }
            self.layout(height: hosting.fittingSize.height)
        }
    }

    private func measuredAnswerHeight(_ text: String, width: CGFloat) -> CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let string = text.isEmpty ? " " : text
        let rect = (string as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(rect.height)
    }
}

/// NSPanel that can become key (to receive I/C/D) while staying non-activating.
final class AskKeyPanel: NSPanel {
    enum Key { case insert, copy, dismiss }
    var onKey: ((Key) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onKey?(.dismiss)            // esc
        case 36, 76: onKey?(.insert)         // return / enter
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "i": onKey?(.insert)
            case "c": onKey?(.copy)
            case "d": onKey?(.dismiss)
            default: super.keyDown(with: event)
            }
        }
    }
}

@MainActor
final class AskBubbleViewModel: ObservableObject {
    @Published var agentName = ""
    @Published var question = ""
    @Published var answer = ""
    @Published var streaming = false
    @Published var error: String?
    @Published var statusNote: String?
    /// Fixed height of the scrollable answer area, computed by AskBubbleWindow.
    @Published var answerAreaHeight: CGFloat = 60

    // Button actions (wired by AskBubbleWindow to the controller). Not @Published — set once.
    var onInsert: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDismiss: (() -> Void)?
}

/// Hosting view that accepts the first click even when the panel isn't key, so the
/// bubble's buttons fire on a single click instead of just focusing the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct AskBubbleView: View {
    @ObservedObject var model: AskBubbleViewModel
    let bubbleWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.agentName).font(.caption).opacity(0.6)
                Spacer()
                if let note = model.statusNote { Text(note).font(.caption).opacity(0.6) }
            }
            Text(model.question).font(.callout).opacity(0.85).lineLimit(2)

            answerArea

            HStack(spacing: 12) {
                actionButton("Insert", "I") { model.onInsert?() }
                actionButton("Copy", "C") { model.onCopy?() }
                actionButton("Dismiss", "D") { model.onDismiss?() }
                Spacer()
            }
            .font(.caption)
        }
        .padding(18)
        .frame(width: bubbleWidth, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// Scrolls only the answer. Its height is a fixed value computed by AskBubbleWindow
    /// (AppKit text measurement), so the surrounding stack never compresses or clips it.
    private var answerArea: some View {
        ScrollView {
            answerText
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: model.answerAreaHeight)
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var answerText: some View {
        if let error = model.error {
            Text(error).foregroundStyle(.red).font(.callout)
        } else if model.answer.isEmpty && model.streaming {
            Text("Thinking…").italic().opacity(0.6)
        } else {
            Text(model.answer).font(.body).textSelection(.enabled)
        }
    }

    private func actionButton(_ title: String, _ key: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(key)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                Text(title)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
