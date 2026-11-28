import AppKit
import Observation
import OmniVoiceCore
import SwiftUI

struct MeetingCopilotModalItem: Identifiable, Equatable {
    let id: String
    let kind: ConversationAssistCardKind
    let title: String
    let body: String
    let questionText: String?
    let speakerLabel: String?
    let createdAt: Date
    var isPinned: Bool = false
}

struct MeetingStartOptions: Equatable, Sendable {
    var captureTwoWayAudio: Bool
    var diarizationEnabled: Bool

    static let defaultMeeting = MeetingStartOptions(
        captureTwoWayAudio: true,
        diarizationEnabled: true
    )
}

// MARK: - Meeting Detected Prompt Banner

@MainActor
@Observable
private final class MeetingDetectedBannerState {
    var event: DetectedMeetingEvent?
    var theme: OmniVoiceTheme = .defaultTheme
    var appearanceMode: AppAppearanceMode = .system
    var captureTwoWayAudio: Bool = true
    var diarizationEnabled: Bool = true
    var diarizationEngineLabel: String = "CoreML Sortformer"
}

@MainActor
final class MeetingDetectedBannerWindow {
    private static let bannerSize = CGSize(width: 408, height: 174)

    private var panel: NSPanel?
    private let state = MeetingDetectedBannerState()
    private var autoDismissTask: Task<Void, Never>?
    var onStartMeeting: ((DetectedMeetingEvent, MeetingStartOptions) -> Void)?
    var onDismiss: (() -> Void)?

    func show(
        event: DetectedMeetingEvent,
        corner: MeetingCopilotCorner,
        stealthMode: Bool,
        theme: OmniVoiceTheme,
        appearanceMode: AppAppearanceMode,
        defaultTwoWayAudio: Bool = true,
        defaultDiarizationEnabled: Bool = true,
        diarizationEngineLabel: String = "Speaker Diarization"
    ) {
        autoDismissTask?.cancel()
        state.event = event
        state.theme = theme
        state.appearanceMode = appearanceMode
        state.captureTwoWayAudio = defaultTwoWayAudio
        state.diarizationEnabled = defaultDiarizationEnabled
        state.diarizationEngineLabel = diarizationEngineLabel

        if panel == nil {
            let created = NSPanel(
                contentRect: CGRect(origin: .zero, size: Self.bannerSize),
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
                rootView: MeetingDetectedBannerView(
                    state: state,
                    onStart: { [weak self] event, options in
                        self?.hide()
                        self?.onStartMeeting?(event, options)
                    },
                    onDismiss: { [weak self] in
                        self?.hide()
                        self?.onDismiss?()
                    }
                )
            )
            panel = created
        }

        panel?.sharingType = stealthMode ? .none : .readOnly
        let origin = Self.bannerOrigin(corner: corner)
        panel?.setFrame(CGRect(origin: origin, size: Self.bannerSize), display: true)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }

        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        panel?.orderOut(nil)
    }

    private static func bannerOrigin(corner: MeetingCopilotCorner) -> CGPoint {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let inset: CGFloat = 18
        let x: CGFloat = corner == .topRight
            ? screen.maxX - bannerSize.width - inset
            : screen.minX + inset
        let y: CGFloat = screen.maxY - bannerSize.height - inset
        return CGPoint(x: x, y: y)
    }
}

private struct MeetingDetectedBannerView: View {
    @Bindable var state: MeetingDetectedBannerState
    let onStart: (DetectedMeetingEvent, MeetingStartOptions) -> Void
    let onDismiss: () -> Void

    var body: some View {
        if let event = state.event {
            let headline: String = {
                if event.app == .upcomingMeeting {
                    return "Starting Soon"
                }
                return event.isPreJoin
                    ? "Joining \(event.app.displayName)"
                    : "\(event.app.displayName) detected"
            }()
            let detailLine: String = {
                if let title = event.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty,
                   title.caseInsensitiveCompare(event.app.displayName) != .orderedSame {
                    return title
                }
                return "Record live two-way audio with speaker diarization & Co-Pilot?"
            }()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: event.app.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline)
                            .font(.headline)
                        Text(detailLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)
                }

                // Interactive 2-Way Audio & Speaker Diarization options right in the popup
                HStack(spacing: 8) {
                    Button {
                        state.captureTwoWayAudio.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: state.captureTwoWayAudio ? "waveform.and.mic" : "mic.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(state.captureTwoWayAudio ? "2-Way (Me+Them)" : "Mic Only")
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(state.captureTwoWayAudio ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.08))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(state.captureTwoWayAudio ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.14), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        state.diarizationEnabled.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: state.diarizationEnabled ? "person.2.wave.2.fill" : "person.2.slash")
                                .font(.system(size: 11, weight: .semibold))
                            Text(state.diarizationEnabled ? "Diarize: \(state.diarizationEngineLabel)" : "Diarization Off")
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(state.diarizationEnabled ? Color.green.opacity(0.20) : Color.primary.opacity(0.08))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(state.diarizationEnabled ? Color.green.opacity(0.45) : Color.primary.opacity(0.14), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Button {
                        onStart(
                            event,
                            MeetingStartOptions(
                                captureTwoWayAudio: state.captureTwoWayAudio,
                                diarizationEnabled: state.diarizationEnabled
                            )
                        )
                    } label: {
                        Label("Start Recording", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Ignore") {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(14)
            .frame(width: 408, height: 174, alignment: .topLeading)
            .themeSurface(state.theme, cornerRadius: 16, strong: true, interactive: false)
            .preferredColorScheme(state.appearanceMode.colorScheme)
        }
    }
}

// MARK: - Live Meeting Co-Pilot Floating Modals Stack

@MainActor
@Observable
final class MeetingCopilotOverlayState {
    var meetingTitle: String = "Live Meeting"
    var calendarSubtitle: String?
    var isRecording: Bool = false
    var isAnalyzing: Bool = false
    var stealthMode: Bool = true
    var talkTime: MeetingTalkTimeStats = MeetingTalkTimeStats()
    var corner: MeetingCopilotCorner = .topRight
    var modals: [MeetingCopilotModalItem] = []
    var theme: OmniVoiceTheme = .defaultTheme
    var appearanceMode: AppAppearanceMode = .system
}

@MainActor
final class MeetingCopilotOverlayWindow {
    private static let stackWidth: CGFloat = 376
    private static let maxStackHeight: CGFloat = 680

    private var panel: NSPanel?
    let state = MeetingCopilotOverlayState()
    private var dismissTasks: [String: Task<Void, Never>] = [:]

    var onAnalyzeNow: (() -> Void)?
    var onCatchUp: (() -> Void)?
    var onScreenContext: (() -> Void)?
    var onBookmarkMoment: (() -> Void)?
    var onToggleCorner: (() -> Void)?
    var onStopMeeting: (() -> Void)?
    var onCopyText: ((String) -> Void)?

    func showSession(
        title: String,
        calendarSubtitle: String? = nil,
        corner: MeetingCopilotCorner,
        stealthMode: Bool,
        theme: OmniVoiceTheme,
        appearanceMode: AppAppearanceMode
    ) {
        state.meetingTitle = title
        state.calendarSubtitle = calendarSubtitle
        state.isRecording = true
        state.corner = corner
        state.stealthMode = stealthMode
        state.talkTime = MeetingTalkTimeStats()
        state.theme = theme
        state.appearanceMode = appearanceMode
        ensurePanel()
        panel?.sharingType = stealthMode ? .none : .readOnly
        repositionPanel()
        panel?.orderFrontRegardless()
    }

    func updateTheme(_ theme: OmniVoiceTheme, appearanceMode: AppAppearanceMode, corner: MeetingCopilotCorner, stealthMode: Bool) {
        state.theme = theme
        state.appearanceMode = appearanceMode
        state.corner = corner
        state.stealthMode = stealthMode
        panel?.sharingType = stealthMode ? .none : .readOnly
        repositionPanel()
    }

    func updateTalkTime(_ stats: MeetingTalkTimeStats) {
        state.talkTime = stats
    }

    func setAnalyzing(_ analyzing: Bool) {
        state.isAnalyzing = analyzing
    }

    func presentModal(_ item: MeetingCopilotModalItem) {
        guard !state.modals.contains(where: { $0.id == item.id || ($0.title == item.title && $0.body == item.body) }) else {
            return
        }
        ensurePanel()
        repositionPanel()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            state.modals.insert(item, at: 0)
            // Keep at most 4 stacked modals visible (prefer keeping pinned ones)
            while state.modals.count > 4 {
                if let unpinnedIdx = state.modals.lastIndex(where: { !$0.isPinned }) {
                    let removed = state.modals.remove(at: unpinnedIdx)
                    dismissTasks[removed.id]?.cancel()
                    dismissTasks[removed.id] = nil
                } else {
                    break
                }
            }
        }
        panel?.orderFrontRegardless()
        scheduleAutoDismiss(for: item.id)
    }

    func dismissModal(id: String) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            state.modals.removeAll { $0.id == id }
        }
        if !state.isRecording && state.modals.isEmpty {
            panel?.orderOut(nil)
        }
    }

    func togglePin(id: String) {
        guard let idx = state.modals.firstIndex(where: { $0.id == id }) else { return }
        state.modals[idx].isPinned.toggle()
        if state.modals[idx].isPinned {
            dismissTasks[id]?.cancel()
            dismissTasks[id] = nil
        } else {
            scheduleAutoDismiss(for: id)
        }
    }

    func endSession(keepPinnedModals: Bool = true) {
        state.isRecording = false
        state.isAnalyzing = false
        if !keepPinnedModals {
            for task in dismissTasks.values { task.cancel() }
            dismissTasks.removeAll()
            state.modals.removeAll()
            panel?.orderOut(nil)
        } else if state.modals.isEmpty {
            panel?.orderOut(nil)
        }
    }

    private func scheduleAutoDismiss(for id: String) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(34))
            guard !Task.isCancelled, let self else { return }
            if let item = self.state.modals.first(where: { $0.id == id }), !item.isPinned {
                self.dismissModal(id: id)
            }
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let created = NSPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: Self.stackWidth, height: Self.maxStackHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = true
        created.becomesKeyOnlyIfNeeded = true
        created.hidesOnDeactivate = false
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.level = .floating
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.contentView = NSHostingView(
            rootView: MeetingCopilotStackView(
                state: state,
                onAnalyzeNow: { [weak self] in self?.onAnalyzeNow?() },
                onCatchUp: { [weak self] in self?.onCatchUp?() },
                onScreenContext: { [weak self] in self?.onScreenContext?() },
                onBookmarkMoment: { [weak self] in self?.onBookmarkMoment?() },
                onToggleCorner: { [weak self] in self?.onToggleCorner?() },
                onStopMeeting: { [weak self] in self?.onStopMeeting?() },
                onCopy: { [weak self] text in self?.onCopyText?(text) },
                onPin: { [weak self] id in self?.togglePin(id: id) },
                onDismiss: { [weak self] id in self?.dismissModal(id: id) }
            )
        )
        created.sharingType = state.stealthMode ? .none : .readOnly
        panel = created
    }

    private func repositionPanel() {
        guard let panel else { return }
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let inset: CGFloat = 16
        let height = min(Self.maxStackHeight, screen.height - (inset * 2))
        let x: CGFloat = state.corner == .topRight
            ? screen.maxX - Self.stackWidth - inset
            : screen.minX + inset
        let y: CGFloat = screen.maxY - height - inset
        panel.setFrame(CGRect(x: x, y: y, width: Self.stackWidth, height: height), display: true)
    }
}

private struct MeetingCopilotStackView: View {
    @Bindable var state: MeetingCopilotOverlayState
    let onAnalyzeNow: () -> Void
    let onCatchUp: () -> Void
    let onScreenContext: () -> Void
    let onBookmarkMoment: () -> Void
    let onToggleCorner: () -> Void
    let onStopMeeting: () -> Void
    let onCopy: (String) -> Void
    let onPin: (String) -> Void
    let onDismiss: (String) -> Void

    var body: some View {
        VStack(alignment: state.corner == .topRight ? .trailing : .leading, spacing: 10) {
            if state.isRecording {
                copilotHeaderPill
            }

            ForEach(state.modals) { modal in
                MeetingCopilotCardModal(
                    item: modal,
                    theme: state.theme,
                    onCopy: { onCopy(modal.body) },
                    onPin: { onPin(modal.id) },
                    onDismiss: { onDismiss(modal.id) }
                )
                .transition(
                    .move(edge: state.corner == .topRight ? .trailing : .leading)
                        .combined(with: .opacity)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(state.appearanceMode.colorScheme)
    }

    private var copilotHeaderPill: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(state.meetingTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if state.stealthMode {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .help("Stealth Mode: hidden from screen sharing")
                        }
                    }
                    Text(state.isAnalyzing ? "Analyzing transcript…" : (state.calendarSubtitle ?? "Co-Pilot listening · Me + Them"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if state.isAnalyzing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Button {
                        onAnalyzeNow()
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Analyze transcript now")
                }

                Button {
                    onCatchUp()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("What Did I Miss? Summarize the last 2 minutes")

                Button {
                    onScreenContext()
                } label: {
                    Image(systemName: "macwindow.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Capture screen & get a screen-aware insight or answer")

                Button {
                    onBookmarkMoment()
                } label: {
                    Image(systemName: "bookmark.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Bookmark this moment in the meeting transcript")

                Button {
                    onToggleCorner()
                } label: {
                    Image(systemName: state.corner == .topRight ? "arrow.up.left" : "arrow.up.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Move Co-Pilot modals to \(state.corner == .topRight ? "Top Left" : "Top Right")")

                Button {
                    onStopMeeting()
                } label: {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Stop meeting & generate wrap-up")
            }

            if state.talkTime.totalMs > 0 {
                HStack(spacing: 6) {
                    Text("Me \(state.talkTime.mePercent)%")
                        .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.cyan)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.indigo.opacity(0.45))
                            Capsule()
                                .fill(Color.cyan.opacity(0.9))
                                .frame(width: max(4, proxy.size.width * state.talkTime.meRatio))
                        }
                    }
                    .frame(height: 4)

                    Text("Them \(state.talkTime.themPercent)%")
                        .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.indigo)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .themeSurface(state.theme, cornerRadius: 14, strong: true, interactive: false)
    }
}

private struct MeetingCopilotCardModal: View {
    let item: MeetingCopilotModalItem
    let theme: OmniVoiceTheme
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDismiss: () -> Void

    private var isAnswerCard: Bool {
        item.kind == .answer || item.questionText != nil
    }

    private var badgeColor: Color {
        switch item.kind {
        case .answer: .cyan
        case .question: .indigo
        case .actionItem: .orange
        case .followUp: .blue
        case .timeZone: .mint
        case .warning: .red
        }
    }

    private var badgeTitle: String {
        if item.questionText != nil {
            return "Question Answered"
        }
        switch item.kind {
        case .answer: return "Suggested Answer"
        case .question: return "Question Detected"
        case .actionItem: return "Action Item"
        case .followUp: return "Follow-Up"
        case .timeZone: return "Time Zone"
        case .warning: return "Heads Up"
        }
    }

    private var badgeIcon: String {
        switch item.kind {
        case .answer: "sparkles"
        case .question: "questionmark.bubble.fill"
        case .actionItem: "checkmark.circle.fill"
        case .followUp: "arrow.uturn.right.circle.fill"
        case .timeZone: "clock.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(badgeTitle, systemImage: badgeIcon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(badgeColor)
                    .textCase(.uppercase)

                if let speaker = item.speakerLabel, !speaker.isEmpty {
                    Text("· \(speaker)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")

                Button {
                    onPin()
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(item.isPinned ? badgeColor : .secondary)
                }
                .help(item.isPinned ? "Unpin modal" : "Keep modal open")

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Dismiss")
            }
            .buttonStyle(.plain)
            .font(.caption)

            if let questionText = item.questionText, !questionText.isEmpty {
                Text("\u{201C}\(questionText)\u{201D}")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(item.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.body)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSurface(theme, cornerRadius: 15, strong: true, interactive: false)
        .overlay {
            if isAnswerCard {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(badgeColor.opacity(0.45), lineWidth: 1.2)
            }
        }
    }
}
