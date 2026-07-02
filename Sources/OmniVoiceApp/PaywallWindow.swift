import AppKit
import SwiftUI
import OmniVoiceCore

/// Shown when a locked premium feature is invoked. Offers a no-card free trial (which
/// routes through sign-in) or managing an existing subscription. Modeled on
/// `TeachCorrectionWindow`: a small titled floating panel hosting a SwiftUI view.
@MainActor
final class PaywallWindow {
    private var panel: NSPanel?
    private let model = PaywallModel()

    func show(
        feature: PremiumFeature,
        onStartTrial: @escaping () -> Void,
        onManageBilling: @escaping () -> Void
    ) {
        model.feature = feature
        model.onStartTrial = { [weak self] in
            onStartTrial()
            self?.hide()
        }
        model.onManageBilling = { [weak self] in
            onManageBilling()
            self?.hide()
        }
        model.onDismiss = { [weak self] in self?.hide() }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "OmniSpeak Premium"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: PaywallView(model: model))
        return panel
    }
}

@MainActor
final class PaywallModel: ObservableObject {
    @Published var feature: PremiumFeature = .askAI
    var onStartTrial: (() -> Void)?
    var onManageBilling: (() -> Void)?
    var onDismiss: (() -> Void)?
}

struct PaywallView: View {
    @ObservedObject var model: PaywallModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.feature.displayName) is a premium feature")
                        .font(.headline)
                    Text("Start a free 14-day trial — no card required.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Premium unlocks Ask AI, Cloud Sync, Live Translation, and Conversation Mode. Local dictation is always free.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Not now") { model.onDismiss?() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Manage Billing") { model.onManageBilling?() }
                Button("Start Free Trial") { model.onStartTrial?() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}
