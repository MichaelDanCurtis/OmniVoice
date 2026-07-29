import AppKit
import SwiftUI
import OmniVoiceCore

/// Fallback for apps where the Accessibility auto-detect can't read the field. Invoked by a
/// hotkey (⌃⌥T) after a dictation: shows a small panel pre-filled with what OmniSpeak inserted;
/// the user types the correct form and it's learned the same way as an auto-detected correction.
@MainActor
final class TeachCorrectionWindow {
    var onLearn: ((LearnedCorrection) -> Void)?

    private var panel: NSPanel?
    private let model = TeachCorrectionModel()

    func show(originalText: String) {
        model.original = originalText
        model.corrected = originalText
        model.onSubmit = { [weak self] in self?.submit() }
        model.onCancel = { [weak self] in self?.hide() }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func submit() {
        let from = model.original.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = model.corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !from.isEmpty, !to.isEmpty, from != to {
            onLearn?(LearnedCorrection(from: from, to: to))
        }
        hide()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = "Teach a Correction"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: TeachCorrectionView(model: model))
        return panel
    }
}

@MainActor
final class TeachCorrectionModel: ObservableObject {
    @Published var original = ""
    @Published var corrected = ""
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
}

struct TeachCorrectionView: View {
    @ObservedObject var model: TeachCorrectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What should “\(model.original)” have been?")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Correct spelling", text: $model.corrected)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.onSubmit?() }

            HStack {
                Spacer()
                Button("Cancel") { model.onCancel?() }
                    .keyboardShortcut(.cancelAction)
                Button("Learn") { model.onSubmit?() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}
