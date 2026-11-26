import AppKit
import Observation
import OmniVoiceCore
import SwiftUI

@MainActor
@Observable
private final class MeetingWrapUpState {
    var summary: MeetingWrapUpSummary?
    var theme: OmniVoiceTheme = .defaultTheme
    var appearanceMode: AppAppearanceMode = .system
    var copiedLabel: String?
}

@MainActor
final class MeetingWrapUpWindow {
    private static let panelSize = CGSize(width: 472, height: 510)

    private var panel: NSPanel?
    private let state = MeetingWrapUpState()
    var onCopyText: ((String) -> Void)?
    var onExportToNotes: ((MeetingWrapUpSummary) -> String)?
    var onExportToReminders: ((MeetingWrapUpSummary) async -> String)?

    func show(
        summary: MeetingWrapUpSummary,
        corner: MeetingCopilotCorner,
        stealthMode: Bool,
        theme: OmniVoiceTheme,
        appearanceMode: AppAppearanceMode
    ) {
        state.summary = summary
        state.theme = theme
        state.appearanceMode = appearanceMode
        state.copiedLabel = nil

        if panel == nil {
            let created = NSPanel(
                contentRect: CGRect(origin: .zero, size: Self.panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isFloatingPanel = true
            created.becomesKeyOnlyIfNeeded = true
            created.hidesOnDeactivate = false
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            created.level = .floating
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.contentView = NSHostingView(
                rootView: MeetingWrapUpView(
                    state: state,
                    onCopy: { [weak self] text, label in
                        self?.onCopyText?(text)
                        self?.flashStatus(label)
                    },
                    onExportNotes: { [weak self] summary in
                        if let status = self?.onExportToNotes?(summary) {
                            self?.flashStatus(status)
                        }
                    },
                    onExportReminders: { [weak self] summary in
                        Task { @MainActor [weak self] in
                            if let status = await self?.onExportToReminders?(summary) {
                                self?.flashStatus(status)
                            }
                        }
                    },
                    onClose: { [weak self] in
                        self?.hide()
                    }
                )
            )
            panel = created
        }

        panel?.sharingType = stealthMode ? .none : .readOnly
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let inset: CGFloat = 18
        let x: CGFloat = corner == .topRight
            ? screen.maxX - Self.panelSize.width - inset
            : screen.minX + inset
        let y: CGFloat = screen.maxY - Self.panelSize.height - inset
        panel?.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: Self.panelSize), display: true)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func flashStatus(_ message: String) {
        state.copiedLabel = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            if self?.state.copiedLabel == message {
                self?.state.copiedLabel = nil
            }
        }
    }
}

private struct MeetingWrapUpView: View {
    @Bindable var state: MeetingWrapUpState
    let onCopy: (String, String) -> Void
    let onExportNotes: (MeetingWrapUpSummary) -> Void
    let onExportReminders: (MeetingWrapUpSummary) -> Void
    let onClose: () -> Void

    var body: some View {
        if let summary = state.summary {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Meeting Wrap-Up", systemImage: "sparkles.rectangle.stack")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.cyan)
                            .textCase(.uppercase)
                        Text(summary.title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let status = state.copiedLabel {
                        Text(status)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionBlock(title: "Executive Summary", icon: "text.alignleft") {
                            Text(summary.executiveSummary)
                                .font(.callout)
                                .textSelection(.enabled)
                        }

                        if !summary.myPromises.isEmpty {
                            sectionBlock(title: "My Promises", icon: "hand.raised.fill") {
                                ForEach(summary.myPromises, id: \.self) { promise in
                                    Text("★ \(promise)")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        if !summary.decisions.isEmpty {
                            sectionBlock(title: "Decisions", icon: "checkmark.seal.fill") {
                                ForEach(summary.decisions, id: \.self) { decision in
                                    Text("• \(decision)")
                                        .font(.caption)
                                }
                            }
                        }

                        if !summary.actionItems.isEmpty {
                            sectionBlock(title: "Action Items", icon: "checklist") {
                                ForEach(summary.actionItems, id: \.self) { item in
                                    Text("☐ \(item)")
                                        .font(.caption)
                                }
                            }
                        }

                        sectionBlock(title: "Follow-Up Draft", icon: "paperplane.fill") {
                            Text(summary.followUpDraft)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Button {
                            onExportNotes(summary)
                        } label: {
                            Label("Apple Notes", systemImage: "note.text.badge.plus")
                        }

                        Button {
                            onExportReminders(summary)
                        } label: {
                            Label("Reminders", systemImage: "checklist.checked")
                        }
                        .disabled(summary.actionItems.isEmpty && summary.myPromises.isEmpty)

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Button {
                            onCopy(summary.markdownRecap, "Recap copied")
                        } label: {
                            Label("Copy Recap", systemImage: "doc.on.doc")
                        }

                        Button {
                            onCopy(summary.followUpDraft, "Follow-Up copied")
                        } label: {
                            Label("Copy Follow-Up", systemImage: "paperplane")
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        Button("Done") {
                            onClose()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(16)
            .frame(width: 472, height: 510, alignment: .topLeading)
            .themeSurface(state.theme, cornerRadius: 18, strong: true, interactive: false)
            .preferredColorScheme(state.appearanceMode.colorScheme)
        }
    }

    @ViewBuilder
    private func sectionBlock<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSurface(state.theme, cornerRadius: 11, strong: false, interactive: false)
    }
}
