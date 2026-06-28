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

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(question: String, agentName: String) {
        model.agentName = agentName
        model.question = question
        model.answer = ""
        model.streaming = true
        model.error = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
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
        panel.contentView = NSHostingView(rootView: AskBubbleView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.maxY - size.height - 90))
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
}

struct AskBubbleView: View {
    @ObservedObject var model: AskBubbleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.agentName).font(.caption).opacity(0.6)
                Spacer()
                if let note = model.statusNote { Text(note).font(.caption).opacity(0.6) }
            }
            Text(model.question).font(.callout).opacity(0.85).lineLimit(2)

            Group {
                if let error = model.error {
                    Text(error).foregroundStyle(.red).font(.callout)
                } else if model.answer.isEmpty && model.streaming {
                    Text("Thinking…").italic().opacity(0.6)
                } else {
                    Text(model.answer).font(.body).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                actionLabel("Insert", "I")
                actionLabel("Copy", "C")
                actionLabel("Dismiss", "D")
                Spacer()
            }
            .font(.caption)
            .opacity(0.75)
        }
        .padding(18)
        .frame(width: 440, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func actionLabel(_ title: String, _ key: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(title)
        }
    }
}
