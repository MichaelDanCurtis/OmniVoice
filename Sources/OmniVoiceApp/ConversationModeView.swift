import AppKit
import AVFoundation
import SwiftUI
import OmniVoiceCore

struct ConversationModeView: View {
    @Bindable var model: AppModel
    @State private var speechPlayer = ConversationSpeechPlayer()

    private var theme: OmniVoiceTheme {
        model.activeTheme
    }

    var body: some View {
        HSplitView {
            transcriptPane
                .frame(minWidth: 520)

            assistRail
                .frame(minWidth: 300, idealWidth: 340)
        }
        .padding(18)
        .background {
            ConversationWindowBackground(theme: theme)
        }
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            transcriptList
            recordingControls
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Conversation Mode")
                    .font(.title2.weight(.bold))
                Text(headerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    copy(transcriptText)
                } label: {
                    Label("Copy Transcript", systemImage: "doc.on.doc")
                }
                .disabled(transcriptText.isEmpty)

                Button {
                    Task {
                        await model.loadConversations()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .themeSurface(theme, cornerRadius: 10, strong: true)
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.conversationSegments.isEmpty {
                        emptyTranscriptState
                    } else {
                        transcriptParagraph
                    }
                }
                .padding(14)
            }
            .themeSurface(theme, cornerRadius: 10)
            .onChange(of: model.conversationSegments.count) { _, _ in
                guard let lastID = model.conversationSegments.last?.id else { return }
                withAnimation(.snappy(duration: 0.18)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var transcriptParagraph: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(model.conversationSegments) { segment in
                ConversationSegmentRow(segment: segment, theme: theme)
                    .id(segment.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyTranscriptState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "waveform.and.person.filled")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color(themeColor: theme.accentColor))

            Text("No live conversation yet")
                .font(.headline)

            Text("Start recording to build a timestamped transcript with speaker labels and assist suggestions.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
        .padding(24)
    }

    private var recordingControls: some View {
        HStack(spacing: 12) {
            recordingIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(model.isConversationRecording ? "Recording live conversation" : "Ready to record")
                    .font(.headline)
                Text("\(model.conversationSegments.count) segments · \(model.conversationAssistCards.count) assists")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isConversationRecording {
                Button(role: .cancel) {
                    model.cancelConversationRecording()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }

                Button {
                    Task {
                        await model.stopConversationRecording()
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
            } else {
                Button {
                    Task {
                        await model.startConversationRecording()
                    }
                } label: {
                    Label("Start", systemImage: "record.circle")
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .padding(14)
        .themeSurface(theme, cornerRadius: 10)
    }

    private var recordingIndicator: some View {
        ZStack {
            Circle()
                .fill(Color(themeColor: theme.accentColor).opacity(model.isConversationRecording ? 0.20 : 0.10))
                .frame(width: 40, height: 40)

            Circle()
                .fill(model.isConversationRecording ? .red : Color(themeColor: theme.accentColor))
                .frame(width: 12, height: 12)
                .shadow(color: (model.isConversationRecording ? Color.red : Color(themeColor: theme.accentColor)).opacity(0.70), radius: 10)
        }
        .accessibilityLabel(model.isConversationRecording ? "Recording" : "Idle")
    }

    private var assistRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            assistHeader

            if model.conversationAssistCards.isEmpty {
                assistEmptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.conversationAssistCards) { card in
                            AssistCardView(
                                card: card,
                                theme: theme,
                                copy: copy,
                                speak: speak
                            )
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .themeSurface(theme, cornerRadius: 10, strong: false)
    }

    private var assistHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Insight Rail")
                    .font(.headline)
                Text("Questions, answers, and meeting helpers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Color(themeColor: theme.accentColor))
        }
    }

    private var assistEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.title2)
                .foregroundStyle(Color(themeColor: theme.accentColor))

            Text("No assists yet")
                .font(.headline)

            Text("When the conversation contains a question, action item, or useful context, OmniVoice will place it here with copy and TTS controls.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .themeSurface(theme, cornerRadius: 10)
    }

    private var headerDetail: String {
        if let activeConversation = model.activeConversation {
            return "\(activeConversation.captureMode.displayName) · \(activeConversation.asrProvider) · \(activeConversation.diarizationProvider)"
        }

        return "\(model.conversationSessions.count) saved conversations · \(model.statusText)"
    }

    private var transcriptText: String {
        model.conversationSegments
            .map { "\($0.timestampLabel) \($0.speakerDisplayName): \($0.text)" }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copy(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        model.statusText = "Copied"
    }

    private func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        speechPlayer.speak(trimmed)
        model.statusText = "Speaking assist"
    }
}

private struct ConversationSegmentRow: View {
    let segment: ConversationSegment
    let theme: OmniVoiceTheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(segment.timestampLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    speakerPill

                    if segment.state == .live {
                        Label("Live", systemImage: "waveform")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(themeColor: theme.accentColor))
                    }

                    Spacer(minLength: 8)

                    if let confidence = segment.confidence {
                        Text(confidence, format: .percent.precision(.fractionLength(0)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(segment.text)
                    .font(.callout)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .themeSurface(theme, cornerRadius: 8)
        }
    }

    private var speakerPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(themeColor: theme.accentColor).opacity(0.78))
                .frame(width: 7, height: 7)

            Text(segment.speakerDisplayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct AssistCardView: View {
    let card: ConversationAssistCard
    let theme: OmniVoiceTheme
    let copy: (String) -> Void
    let speak: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: card.kind.systemImage)
                    .font(.headline)
                    .foregroundStyle(Color(themeColor: theme.accentColor))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(card.kind.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Spacer(minLength: 8)
            }

            Text(card.body)
                .font(.callout)
                .lineLimit(8)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Button {
                    copy(card.copyText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button {
                    speak(card.copyText)
                } label: {
                    Label("Speak", systemImage: "speaker.wave.2")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .themeSurface(theme, cornerRadius: 10)
    }
}

private struct ConversationWindowBackground: View {
    let theme: OmniVoiceTheme

    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(themeColor: theme.surfaceTint).opacity(0.18),
                Color.black.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

@MainActor
private final class ConversationSpeechPlayer {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: text))
    }
}

private extension ConversationAssistCardKind {
    var displayName: String {
        switch self {
        case .question: "Question"
        case .answer: "Answer"
        case .timeZone: "Time Zone"
        case .followUp: "Follow-Up"
        case .actionItem: "Action Item"
        case .warning: "Warning"
        }
    }

    var systemImage: String {
        switch self {
        case .question: "questionmark.bubble"
        case .answer: "checkmark.bubble"
        case .timeZone: "clock.badge"
        case .followUp: "arrow.turn.down.right"
        case .actionItem: "checklist"
        case .warning: "exclamationmark.triangle"
        }
    }
}
