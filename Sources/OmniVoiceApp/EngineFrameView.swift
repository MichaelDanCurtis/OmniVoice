import AppKit
import SwiftUI
import OmniVoiceCore

struct EngineFrameView: View {
    static let collapsedWidth: CGFloat = 36
    static let drawerWidth: CGFloat = 410
    private static let handleHeight: CGFloat = 86
    private static let handleWidth: CGFloat = 28
    private static let handleCoordinateSpace = "engineFrameHandleArea"

    @Bindable var model: AppModel
    let side: EngineFrameSide
    @Binding var isExpanded: Bool
    let insertTranscript: (EngineTranscriptRecord) -> Void
    @State private var draftHandlePosition: Double?

    private var theme: OmniVoiceTheme {
        model.activeTheme
    }

    var body: some View {
        ZStack(alignment: side.stackAlignment) {
            if isExpanded {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isExpanded = false
                    }

                drawerContent
                    .frame(width: Self.drawerWidth)
                    .padding(.vertical, 10)
                    .padding(side == .left ? .leading : .trailing, Self.collapsedWidth)
                    .transition(.move(edge: side.transitionEdge).combined(with: .opacity))
                    .zIndex(2)
            }

            collapseHandle
                .zIndex(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side.stackAlignment)
        .animation(.snappy(duration: 0.24), value: isExpanded)
        .task {
            await model.refreshTranscripts()
        }
    }

    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.transcripts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.transcripts) { transcript in
                            TranscriptHistoryCard(
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
        .padding(12)
        .background {
            EngineFrameGlassPanel(theme: theme)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Conversation")
                    .font(.caption.weight(.semibold))
                    .themeAccentForeground(theme)
                    .textCase(.uppercase)
                Text("Transcript History")
                    .font(.title3.weight(.bold))
                Text("\(model.transcripts.count) recent dictations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await model.refreshTranscripts()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Refresh conversation history")
        }
    }

    private var emptyState: some View {
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
    }

    private var collapseHandle: some View {
        GeometryReader { proxy in
            let usableHeight = max(1, proxy.size.height - Self.handleHeight)
            let position = draftHandlePosition ?? model.preferences.engineFrameHandlePosition
            let clampedPosition = OmniVoicePreferences.clampedHandlePosition(position)
            let y = (usableHeight * clampedPosition) + (Self.handleHeight / 2)

            movableHandle
                .position(x: side.handleCenterX(in: proxy.size.width, handleWidth: Self.handleWidth), y: y)
                .gesture(handleDragGesture(usableHeight: usableHeight))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.handleCoordinateSpace)
        .help(isExpanded ? "Close conversation history" : "Open conversation history")
    }

    private var movableHandle: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color(themeColor: theme.accentColor))
                .frame(width: 2.5, height: 34)
                .shadow(color: Color(themeColor: theme.accentColor).opacity(0.50), radius: 9)

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 13, weight: .semibold))
                .themeAccentForeground(theme)
        }
        .frame(width: Self.handleWidth, height: Self.handleHeight)
        .background {
            EngineFrameHandleGlass(theme: theme, side: side)
        }
        .contentShape(Rectangle())
    }

    private func handleDragGesture(usableHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.handleCoordinateSpace))
            .onChanged { value in
                let next = normalizedHandlePosition(forY: value.location.y, usableHeight: usableHeight)
                draftHandlePosition = next
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height)
                let next = normalizedHandlePosition(forY: value.location.y, usableHeight: usableHeight)
                draftHandlePosition = nil

                if moved < 5 {
                    isExpanded.toggle()
                } else {
                    if let targetSide = sideSwitchTarget(forHorizontalTranslation: value.translation.width) {
                        model.setEngineFrameSide(targetSide)
                    }
                    model.setEngineFrameHandlePosition(next)
                }
            }
    }

    private func normalizedHandlePosition(forY y: CGFloat, usableHeight: CGFloat) -> Double {
        guard usableHeight > 0 else { return 0.5 }
        return OmniVoicePreferences.clampedHandlePosition(Double((y - (Self.handleHeight / 2)) / usableHeight))
    }

    private func sideSwitchTarget(forHorizontalTranslation translation: CGFloat) -> EngineFrameSide? {
        let threshold: CGFloat = 140
        switch side {
        case .left where translation > threshold:
            return .right
        case .right where translation < -threshold:
            return .left
        default:
            return nil
        }
    }

    private func copyTranscript(_ transcript: EngineTranscriptRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript.displayText, forType: .string)
        model.statusText = "Transcript copied"
    }
}

private struct TranscriptHistoryCard: View {
    let transcript: EngineTranscriptRecord
    let theme: OmniVoiceTheme
    let copyTranscript: (EngineTranscriptRecord) -> Void
    let insertTranscript: (EngineTranscriptRecord) -> Void
    let askAITranscript: (EngineTranscriptRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(transcript.displayText)
                        .font(.callout)
                        .lineLimit(5)
                        .textSelection(.enabled)

                    metadata
                }

                Spacer(minLength: 8)
            }

            if let rawText = rawText {
                Text(rawText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button {
                    copyTranscript(transcript)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy this transcript")

                Button {
                    insertTranscript(transcript)
                } label: {
                    Label("Insert", systemImage: "text.insert")
                }
                .help("Insert this transcript at the current cursor")

                Button {
                    askAITranscript(transcript)
                } label: {
                    Label("Ask AI", systemImage: "sparkles")
                }
                .help("Attach this transcript to Ask AI")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .themeSurface(theme, cornerRadius: 9, strong: false)
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            Text(shortDate(transcript.createdAt))
            if let provider = transcript.provider {
                Text(provider)
            }
            if let style = transcript.style {
                Text(style)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var rawText: String? {
        let raw = transcript.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != transcript.displayText else {
            return nil
        }
        return "Raw: \(raw)"
    }

    private func shortDate(_ value: String) -> String {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        return value
    }
}

private struct EngineFrameGlassPanel: View {
    let theme: OmniVoiceTheme

    @ViewBuilder
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular.tint(Color(themeColor: theme.surfaceTint).opacity(0.055)),
                    in: shape
                )
                .shadow(color: Color(themeColor: theme.accentColor).opacity(0.12), radius: 22, x: 0, y: 10)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    shape.fill(Color.black.opacity(0.22))
                }
                .overlay {
                    shape.stroke(Color(themeColor: theme.accentColor).opacity(0.30), lineWidth: 1)
                }
                .shadow(color: Color(themeColor: theme.accentColor).opacity(0.20), radius: 24, x: 0, y: 8)
                .shadow(color: .black.opacity(0.28), radius: 30, x: 0, y: 14)
        }
    }
}

private struct EngineFrameHandleGlass: View {
    let theme: OmniVoiceTheme
    let side: EngineFrameSide

    @ViewBuilder
    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: side == .right ? 16 : 0,
            bottomLeadingRadius: side == .right ? 16 : 0,
            bottomTrailingRadius: side == .left ? 16 : 0,
            topTrailingRadius: side == .left ? 16 : 0,
            style: .continuous
        )

        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular
                        .tint(Color(themeColor: theme.surfaceTint).opacity(0.045))
                        .interactive(),
                    in: shape
                )
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    shape.fill(Color.black.opacity(0.14))
                }
                .overlay {
                    shape.stroke(Color(themeColor: theme.accentColor).opacity(0.22), lineWidth: 1)
                }
        }
    }
}

private extension EngineFrameSide {
    var transitionEdge: Edge {
        switch self {
        case .left:
            .leading
        case .right:
            .trailing
        }
    }

    var stackAlignment: Alignment {
        switch self {
        case .left:
            .leading
        case .right:
            .trailing
        }
    }

    func handleCenterX(in width: CGFloat, handleWidth: CGFloat) -> CGFloat {
        switch self {
        case .left:
            handleWidth / 2
        case .right:
            width - (handleWidth / 2)
        }
    }
}
