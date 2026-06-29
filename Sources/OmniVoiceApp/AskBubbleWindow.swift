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
    private let model = AskBubbleViewModel()
    private var lastHeight: CGFloat = 200
    /// The answer scroll caps here so the whole bubble stays near a third of the screen.
    private let maxAnswerHeight: CGFloat = max(160, ((NSScreen.main?.visibleFrame.height ?? 900) / 3) - 120)

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
        panel.makeKeyAndOrderFront(nil)
    }

    func appendAnswer(_ chunk: String) { model.answer += chunk }
    func setStreaming(_ streaming: Bool) { model.streaming = streaming }
    func markInserted() { model.streaming = false; model.statusNote = "Inserted" }
    func showError(_ message: String) { model.streaming = false; model.error = message }
    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> AskKeyPanel {
        let panel = AskKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
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
        model.onHeightChange = { [weak self] height in self?.layout(height: height) }
        panel.contentView = FirstMouseHostingView(
            rootView: AskBubbleView(model: model, maxAnswerHeight: maxAnswerHeight)
        )
        return panel
    }

    /// Size the panel to the measured content height (clamped) and keep its TOP edge
    /// pinned ~90pt below the screen top, horizontally centered, so it grows downward.
    private func layout(height: CGFloat) {
        guard let panel else { return }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 440
        let clamped = max(120, height)
        guard abs(clamped - panel.frame.height) > 0.5 || panel.frame.width != width else { return }
        lastHeight = clamped
        let topY = visible.maxY - 90
        let frame = NSRect(x: visible.midX - width / 2, y: topY - clamped, width: width, height: clamped)
        panel.setFrame(frame, display: true, animate: false)
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

    // Button actions (wired by AskBubbleWindow to the controller). Not @Published — set once.
    var onInsert: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDismiss: (() -> Void)?
    // Reports the bubble's measured total height so the window can resize to fit.
    var onHeightChange: ((CGFloat) -> Void)?
}

private struct BubbleHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AnswerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Hosting view that accepts the first click even when the panel isn't key, so the
/// bubble's buttons fire on a single click instead of just focusing the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct AskBubbleView: View {
    @ObservedObject var model: AskBubbleViewModel
    let maxAnswerHeight: CGFloat
    @State private var answerContentHeight: CGFloat = 0

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
        .frame(width: 440, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .overlay(answerMeasuringView, alignment: .topLeading)
        .onPreferenceChange(AnswerHeightKey.self) { answerContentHeight = $0 }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: BubbleHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(BubbleHeightKey.self) { height in
            model.onHeightChange?(height)
        }
    }

    /// Scrolls only the answer. Its height is a FIXED value (not a flexible max) so the
    /// surrounding stack never compresses it — `answerContentHeight` comes from
    /// `answerMeasuringView`, not from inside the scroll view.
    private var answerArea: some View {
        ScrollView {
            answerText
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: min(max(answerContentHeight, 22), maxAnswerHeight))
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Invisible copy of the answer at the real content width (440 − 2×18 padding),
    /// laid out at its natural unconstrained height. Preferences set inside a ScrollView
    /// don't propagate out reliably, so the scroll frame is driven from this instead.
    private var answerMeasuringView: some View {
        answerText
            .frame(width: 404, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .allowsHitTesting(false)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: AnswerHeightKey.self, value: geo.size.height)
                }
            )
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
