import AppKit
import SwiftUI
import OmniVoiceCore

/// A small non-activating toast shown when a word is learned: "Learned figma → Figma" with an
/// Undo button wrapped in a 5-second countdown. It never steals focus (you're typing in your
/// app). A new `show(...)` replaces the current toast (the previous learn auto-commits).
@MainActor
final class LearnedWordToast {
    var onUndo: ((String) -> Void)?

    private var panel: NSPanel?
    private let model = LearnedWordToastModel()
    private var timer: Timer?
    private let width: CGFloat = 320
    private let duration: TimeInterval = 5

    func show(correction: LearnedCorrection, entryID: String?) {
        timer?.invalidate()
        model.from = correction.from
        model.to = correction.to
        model.entryID = entryID
        model.progress = 1
        model.onUndo = { [weak self] in self?.undo() }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        layout(panel)
        panel.orderFrontRegardless()
        startCountdown()
    }

    private func startCountdown() {
        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.model.progress = max(0, 1 - elapsed / self.duration)
                if elapsed >= self.duration { self.hide() }
            }
        }
    }

    private func undo() {
        if let id = model.entryID { onUndo?(id) }
        hide()
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = FirstMouseHostingView(rootView: LearnedWordToastView(model: model))
        return panel
    }

    private func layout(_ panel: NSPanel) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let height: CGFloat = 56
        panel.setFrame(
            NSRect(x: visible.midX - width / 2, y: visible.maxY - height - 90, width: width, height: height),
            display: true
        )
    }
}

@MainActor
final class LearnedWordToastModel: ObservableObject {
    @Published var from = ""
    @Published var to = ""
    @Published var progress: Double = 1
    var entryID: String?
    var onUndo: (() -> Void)?
}

struct LearnedWordToastView: View {
    @ObservedObject var model: LearnedWordToastModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Learned").font(.caption2).opacity(0.55)
                Text("\(model.from) → \(model.to)")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(action: { model.onUndo?() }) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(.secondary.opacity(0.3), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: model.progress)
                            .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 15, height: 15)
                    Text("Undo")
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(width: 320, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
