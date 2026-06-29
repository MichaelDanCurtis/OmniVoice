import AppKit
import Observation
import OmniVoiceCore
import SwiftUI

@MainActor
final class TranscriptCacheOverlayWindow {
    private static let overlaySize = CGSize(width: 430, height: 278)

    private var window: NSWindow?
    private let state = TranscriptCacheOverlayState()
    private var selectionState = TranscriptCacheSelectionState()
    private var localMonitor: Any?
    private var globalScrollMonitor: Any?
    private var globalMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var onInsert: ((EngineTranscriptRecord) -> Void)?
    private var onCancel: (() -> Void)?

    var isPresented: Bool {
        window?.isVisible == true
    }

    func show(
        anchor: CGPoint,
        transcripts: [EngineTranscriptRecord],
        theme: OmniVoiceTheme,
        appearanceMode: AppAppearanceMode,
        onInsert: @escaping (EngineTranscriptRecord) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard !transcripts.isEmpty else { return }

        self.onInsert = onInsert
        self.onCancel = onCancel
        selectionState = TranscriptCacheSelectionState()
        state.configure(
            transcripts: transcripts,
            selectedIndex: selectionState.selectedIndex,
            theme: theme,
            appearanceMode: appearanceMode
        )

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = CaptionOverlayPlacement.origin(
            forCenter: anchor,
            screenFrame: screenFrame,
            overlaySize: Self.overlaySize
        )

        if window == nil {
            let created = NSWindow(
                contentRect: CGRect(origin: origin, size: Self.overlaySize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.level = .floating
            created.ignoresMouseEvents = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.contentView = NSHostingView(rootView: TranscriptCacheOverlayView(state: state))
            window = created
        }

        window?.alphaValue = 1
        window?.setFrame(CGRect(origin: origin, size: Self.overlaySize), display: true)
        window?.orderFrontRegardless()
        installMonitors()
    }

    func cancel() {
        tearDown()
        window?.orderOut(nil)
    }

    private func insertSelected() {
        guard let transcript = selectionState.selected(from: state.transcripts) else {
            cancel()
            return
        }

        tearDown()
        window?.orderOut(nil)
        onInsert?(transcript)
    }

    private func moveSelection(delta: Int) {
        selectionState.move(delta: delta, count: state.transcripts.count)
        withAnimation(.snappy(duration: 0.16)) {
            state.selectedIndex = selectionState.selectedIndex
        }
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handle(event)
            }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handle(event)
            }
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handle(event)
            }
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalScrollMonitor {
            NSEvent.removeMonitor(globalScrollMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        localMonitor = nil
        globalScrollMonitor = nil
        globalMouseMonitor = nil
        globalKeyMonitor = nil
    }

    private func tearDown() {
        removeMonitors()
        onCancel = nil
        onInsert = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard isPresented else { return false }

        switch event.type {
        case .scrollWheel:
            guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else {
                return false
            }
            moveSelection(delta: event.scrollingDeltaY > 0 ? -1 : 1)
            return true
        case .leftMouseDown:
            insertSelected()
            return true
        case .rightMouseDown:
            let cancelHandler = onCancel
            cancel()
            cancelHandler?()
            return true
        case .keyDown where event.keyCode == 53:
            let cancelHandler = onCancel
            cancel()
            cancelHandler?()
            return true
        default:
            return false
        }
    }
}

@MainActor
@Observable
private final class TranscriptCacheOverlayState {
    var transcripts: [EngineTranscriptRecord] = []
    var selectedIndex = 0
    var theme: OmniVoiceTheme = .defaultTheme
    var appearanceMode: AppAppearanceMode = .system

    func configure(
        transcripts: [EngineTranscriptRecord],
        selectedIndex: Int,
        theme: OmniVoiceTheme,
        appearanceMode: AppAppearanceMode
    ) {
        self.transcripts = transcripts
        self.selectedIndex = selectedIndex
        self.theme = theme
        self.appearanceMode = appearanceMode
    }
}

private struct TranscriptCacheOverlayView: View {
    @Bindable var state: TranscriptCacheOverlayState
    @Environment(\.colorScheme) private var colorScheme

    private var theme: OmniVoiceTheme { state.theme }
    private var palette: ResolvedThemePalette { theme.resolvedPalette(for: colorScheme) }
    private var accent: Color { Color(themeColor: palette.accentGraphic) }
    private var secondary: Color { Color(themeColor: palette.secondaryAccentGraphic) }
    private var selectedTranscript: EngineTranscriptRecord? {
        guard state.transcripts.indices.contains(state.selectedIndex) else {
            return nil
        }
        return state.transcripts[state.selectedIndex]
    }
    private var visibleTranscripts: [(offset: Int, element: EngineTranscriptRecord)] {
        let count = state.transcripts.count
        let selectedIndex = min(max(state.selectedIndex, 0), max(count - 1, 0))
        let lowerBound = min(max(selectedIndex - 2, 0), max(count - 6, 0))
        let upperBound = min(lowerBound + 6, count)
        guard lowerBound < upperBound else { return [] }
        return Array(state.transcripts.enumerated())[lowerBound..<upperBound].map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            transcriptList
            footer
        }
        .padding(16)
        .frame(width: 430, height: 278, alignment: .topLeading)
        .themeSurface(theme, cornerRadius: 18, strong: true, interactive: false)
        .preferredColorScheme(state.appearanceMode.colorScheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("Transcript Cache")
                    .font(.headline)
                Text("Scroll to pick, left-click to insert")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let selectedTranscript {
                Text(selectedTranscript.createdAt)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var transcriptList: some View {
        VStack(spacing: 7) {
            ForEach(visibleTranscripts, id: \.element.id) { index, transcript in
                TranscriptCacheRow(
                    transcript: transcript,
                    isSelected: index == state.selectedIndex,
                    accent: accent,
                    secondary: secondary
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(state.selectedIndex + 1) of \(state.transcripts.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)

            Spacer()

            Text("Right-click or Esc cancels")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TranscriptCacheRow: View {
    let transcript: EngineTranscriptRecord
    let isSelected: Bool
    let accent: Color
    let secondary: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isSelected ? accent : secondary.opacity(0.38))
                .frame(width: 4, height: 35)

            VStack(alignment: .leading, spacing: 3) {
                Text(transcript.displayText.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(2)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text([transcript.provider, transcript.style].compactMap { $0 }.joined(separator: " / "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? accent.opacity(0.12) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? accent.opacity(0.42) : Color.clear, lineWidth: 1)
        }
    }
}
