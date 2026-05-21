import AppKit
import AVFoundation
import SwiftUI
import OmniVoiceCore

struct ConversationModeView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var speechPlayer = ConversationSpeechPlayer()
    @State private var conversationSearchText = ""
    @State private var editingConversationDraft: ConversationEditDraft?
    @State private var deletingConversation: ConversationSession?
    @State private var selectedConversationIDs = Set<String>()
    @State private var confirmingBulkDelete = false
    private let transcriptBottomAnchorID = "conversation-transcript-bottom-anchor"

    private var theme: OmniVoiceTheme {
        model.activeTheme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topToolbar

            HSplitView {
                conversationLibraryPane
                    .frame(minWidth: 210, idealWidth: 250, maxWidth: 320, maxHeight: .infinity)

                transcriptPane
                    .frame(minWidth: 430, idealWidth: 540, maxWidth: .infinity, maxHeight: .infinity)

                assistRail
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 680)
        .background {
            ConversationWindowBackground(theme: theme)
        }
        .task {
            await model.loadConversations()
            model.disableConversationDiarizationWhenIdle()
        }
        .onDisappear {
            model.disableConversationDiarizationWhenIdle()
        }
        .onChange(of: model.conversationSessions.map(\.id)) { _, _ in
            pruneSelectedConversationIDs()
        }
        .sheet(item: $editingConversationDraft) { draft in
            ConversationEditorSheet(
                draft: draft,
                theme: theme,
                save: { updatedDraft in
                    Task {
                        await model.updateConversation(
                            sessionID: updatedDraft.id,
                            request: updatedDraft.updateRequest
                        )
                        editingConversationDraft = nil
                    }
                },
                cancel: {
                    editingConversationDraft = nil
                }
            )
        }
        .confirmationDialog(
            "Delete conversation?",
            isPresented: deleteConfirmationPresented,
            presenting: deletingConversation
        ) { session in
            Button("Delete", role: .destructive) {
                Task {
                    await model.deleteConversation(session)
                    deletingConversation = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deletingConversation = nil
            }
        } message: { session in
            Text("This removes \(session.title) from the local conversation history.")
        }
        .confirmationDialog(
            "Delete selected conversations?",
            isPresented: $confirmingBulkDelete
        ) {
            Button("Delete \(selectedConversationIDs.count)", role: .destructive) {
                let ids = selectedConversationIDs
                Task {
                    await model.deleteConversations(sessionIDs: ids)
                    selectedConversationIDs.subtract(ids)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(selectedConversationIDs.count) saved conversations from the local library.")
        }
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            transcriptHeader
            transcriptList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            recordingControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topToolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Conversation")
                    .font(.title2.weight(.bold))
                Text(headerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ConversationMetricPill(
                title: "\(model.conversationSessions.count)",
                subtitle: "saved",
                systemImage: "clock.arrow.circlepath",
                theme: theme
            )

            historyMenu

            HStack(spacing: 8) {
                Button {
                    copy(transcriptText)
                } label: {
                    Label("Copy Transcript", systemImage: "doc.on.doc")
                }
                .disabled(!hasTranscriptText)
                .help("Copy the visible conversation transcript")

                if let detail = model.selectedConversationDetail, !model.isConversationRecording {
                    Button {
                        model.archiveConversation(detail, revealInFinder: true)
                    } label: {
                        Label("Export Archive", systemImage: "archivebox")
                    }
                    .help("Export this conversation transcript and metadata, then reveal the archive folder in Finder")
                }

                if model.selectedConversationDetail != nil, !model.isConversationRecording {
                    Button {
                        Task {
                            let opened = await model.sendCurrentConversationToEditor()
                            if opened {
                                await MainActor.run {
                                    openWindow(id: "editor")
                                }
                            }
                        }
                    } label: {
                        Label("Editor", systemImage: "square.and.pencil")
                    }
                    .help("Open this conversation in the Editor")

                    Button {
                        Task {
                            let opened = await model.addCurrentConversationToAskAI()
                            if opened {
                                await MainActor.run {
                                    openWindow(id: "ask-ai")
                                }
                            }
                        }
                    } label: {
                        Label("Ask AI", systemImage: "sparkles")
                    }
                    .help("Attach this conversation to Ask AI")
                }

                Button {
                    Task {
                        await model.loadConversations()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload saved conversations")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .themeSurface(theme, cornerRadius: 10, strong: true, interactive: false)
    }

    private var conversationLibraryPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Library", systemImage: "tray.full")
                    .font(.headline)

                Spacer()

                if !selectedConversationIDs.isEmpty {
                    Text("\(selectedConversationIDs.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .themeAccentForeground(theme)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .themePillSurface(theme)

                    Button {
                        confirmingBulkDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Delete selected conversations")

                    Button {
                        selectedConversationIDs.removeAll()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Clear selected conversations")
                }

                Button {
                    Task {
                        await model.loadConversations()
                        pruneSelectedConversationIDs()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh conversations")
            }

            TextField("Search conversations", text: $conversationSearchText)
                .textFieldStyle(.roundedBorder)
                .disabled(model.conversationSessions.isEmpty)

            if filteredConversationSessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .themeAccentForeground(theme)
                    Text(model.conversationSessions.isEmpty ? "No saved conversations" : "No matches")
                        .font(.callout.weight(.semibold))
                    Text("Saved recordings will appear here after you stop a conversation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 18)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredConversationSessions) { session in
                            ConversationLibraryCard(
                                session: session,
                                isSelected: model.selectedConversationDetail?.session.id == session.id,
                                isMarkedForDelete: selectedConversationIDs.contains(session.id),
                                isDisabled: model.isConversationRecording,
                                theme: theme,
                                toggleSelection: {
                                    toggleConversationSelection(session)
                                },
                                open: {
                                    Task {
                                        await model.loadConversationDetail(session)
                                    }
                                },
                                edit: {
                                    Task {
                                        let opened = await model.sendConversationSessionToEditor(session)
                                        if opened {
                                            await MainActor.run {
                                                openWindow(id: "editor")
                                            }
                                        }
                                    }
                                },
                                delete: {
                                    deletingConversation = session
                                },
                                askAI: {
                                    Task {
                                        let opened = await model.addConversationSessionToAskAI(session)
                                        if opened {
                                            await MainActor.run {
                                                openWindow(id: "ask-ai")
                                            }
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.visible)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themeSurface(theme, cornerRadius: 10, strong: false, interactive: false)
    }

    private var historyMenu: some View {
        Menu {
            Button {
                Task {
                    await model.loadConversations()
                }
            } label: {
                Label("Refresh History", systemImage: "arrow.clockwise")
            }

            Divider()

            if model.conversationSessions.isEmpty {
                Text("No saved conversations")
            } else {
                ForEach(model.conversationSessions.prefix(8)) { session in
                    Button {
                        Task {
                            await model.loadConversationDetail(session)
                        }
                    } label: {
                        Label(sessionMenuTitle(for: session), systemImage: session.isActive ? "record.circle" : "text.bubble")
                    }
                    .disabled(model.isConversationRecording)
                }
            }
        } label: {
            Label("History", systemImage: "tray.full")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .help("Open saved conversation history")
    }

    private var transcriptHeader: some View {
        let speakerCount = visibleSpeakerCount

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.headline)
                    .themeAccentForeground(theme)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Transcript")
                        .font(.headline)
                    Text("Timestamped speaker captions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                ConversationMetricPill(
                    title: "\(speakerCount)",
                    subtitle: speakerCount == 1 ? "speaker" : "speakers",
                    systemImage: "person.2",
                    theme: theme
                )

                ConversationStatusPill(
                    text: recordingStatusTitle,
                    isActive: model.isConversationRecording,
                    isFinalizing: model.isConversationFinalizing,
                    theme: theme
                )
            }

            HStack(alignment: .center, spacing: 8) {
                Text(diarizationDetail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .themePillSurface(theme)

                HStack(spacing: 8) {
                    Text("Diarization")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Toggle("", isOn: conversationDiarizationEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .frame(width: 42)
                        .help("Turn local speaker diarization on or off for conversation recording")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .themePillSurface(theme)
                .disabled(model.isConversationRecording || model.isConversationFinalizing)

                Menu {
                    Picker("Precision", selection: conversationDiarizationPrecisionBinding) {
                        ForEach(DiarizationPrecision.allCases, id: \.self) { precision in
                            Text("\(precision.displayName) - \(precision.detail)").tag(precision)
                        }
                    }
                } label: {
                    Label(model.conversationDiarizationPrecision.displayName, systemImage: "person.wave.2")
                }
                .menuStyle(.button)
                .controlSize(.small)
                .disabled(!model.conversationDiarizationEnabled || model.isConversationRecording || model.isConversationFinalizing)
                .help("Choose the local diarization precision model")

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .themeSurface(theme, cornerRadius: 10, interactive: false)
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if showsLiveDiarizedStream {
                        liveDiarizedStreamTranscript
                    } else if displayedSegments.isEmpty {
                        emptyTranscriptState
                    } else {
                        transcriptParagraph
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(transcriptBottomAnchorID)
                }
                .padding(14)
            }
            .themeSurface(theme, cornerRadius: 10, interactive: false)
            .scrollIndicators(.visible)
            .onChange(of: displayedSegments.count) { _, _ in
                scrollTranscript(to: transcriptScrollTargetID, proxy: proxy)
            }
            .onChange(of: transcriptScrollSignature) { _, _ in
                scrollTranscript(to: transcriptScrollTargetID, proxy: proxy)
            }
        }
    }

    private var liveDiarizedStreamTranscript: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            if displayedSegments.isEmpty {
                liveDiarizedStreamWaitingState
            } else {
                ForEach(displayedSegments) { segment in
                    ConversationSegmentRow(
                        segment: segment,
                        theme: theme,
                        liveDiarizedStreamMode: true
                    )
                    .id(segment.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transcriptParagraph: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(displayedSegments) { segment in
                ConversationSegmentRow(
                    segment: segment,
                    theme: theme,
                    liveDiarizedStreamMode: false
                )
                    .id(segment.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var liveDiarizedStreamWaitingState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "person.wave.2")
                .font(.system(size: 30, weight: .semibold))
                .themeAccentForeground(theme)

            Text("Listening for speaker turns")
                .font(.headline)

            Text("Diarized speaker blocks will stream here as the conversation is recorded.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
        .padding(24)
    }

    private var emptyTranscriptState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "waveform.and.person.filled")
                .font(.system(size: 30, weight: .semibold))
                .themeAccentForeground(theme)

            Text(model.selectedConversationDetail == nil ? "No live conversation yet" : "No transcript lines")
                .font(.headline)

            Text(model.selectedConversationDetail == nil ? "Start recording to build a timestamped transcript with speaker labels and assist suggestions." : "This saved conversation does not have transcript segments.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
        .padding(24)
    }

    private var recordingControls: some View {
        HStack(spacing: 12) {
            recordingIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(recordingStatusTitle)
                    .font(.headline)
                Text(recordingStatusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isConversationRecording || model.isConversationFinalizing {
                Button(role: .cancel) {
                    model.cancelConversationRecording()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .disabled(model.isConversationFinalizing)
                .help("Cancel the current conversation recording")

                Button {
                    guard !model.isConversationFinalizing else { return }
                    Task {
                        await model.stopConversationRecording()
                    }
                } label: {
                    Label(model.isConversationFinalizing ? "Finalizing" : "Stop", systemImage: model.isConversationFinalizing ? "hourglass" : "stop.fill")
                }
                .disabled(model.isConversationFinalizing)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Stop and save the current conversation recording")
            } else {
                Button {
                    Task {
                        await model.startConversationRecording()
                    }
                } label: {
                    Label("Start", systemImage: "record.circle")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Start a live conversation recording")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .padding(14)
        .themeSurface(theme, cornerRadius: 10, interactive: false)
    }

    private var recordingIndicator: some View {
        ZStack {
            Circle()
                .fill(Color(themeColor: theme.accentColor).opacity(model.isConversationRecording || model.isConversationFinalizing ? 0.20 : 0.10))
                .frame(width: 40, height: 40)

            if model.isConversationFinalizing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(model.isConversationRecording ? .red : Color(themeColor: theme.accentColor))
                    .frame(width: 12, height: 12)
                    .shadow(color: (model.isConversationRecording ? Color.red : Color(themeColor: theme.accentColor)).opacity(0.70), radius: 10)
            }
        }
        .accessibilityLabel(model.isConversationFinalizing ? "Finalizing" : (model.isConversationRecording ? "Recording" : "Idle"))
    }

    private var assistRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            assistHeader
            ConversationAIProviderControls(model: model, theme: theme)

            conversationAIChat
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themeSurface(theme, cornerRadius: 10, strong: false, interactive: false)
    }

    private var assistHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Ask Conversation")
                    .font(.headline)
                Text("Runs only when you ask")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.clearConversationAIChat()
            } label: {
                Image(systemName: "eraser")
                    .font(.title3)
                    .themeAccentForeground(theme)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(model.conversationAIMessages.isEmpty && model.conversationAIPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Clear this conversation AI chat")
        }
    }

    private var conversationAIChat: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.conversationAIContextSummary)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if model.conversationAIMessages.isEmpty {
                            conversationAIEmptyState
                        } else {
                            ForEach(model.conversationAIMessages) { message in
                                ConversationAIMessageBubble(message: message, theme: theme)
                                    .id(message.id)
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("conversation-ai-bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .onChange(of: model.conversationAIMessages.count) { _, _ in
                    withAnimation(.snappy(duration: 0.18)) {
                        proxy.scrollTo("conversation-ai-bottom", anchor: .bottom)
                    }
                }
            }

            TextEditor(text: $model.conversationAIPromptDraft)
                .frame(minHeight: 76, maxHeight: 118)
                .scrollContentBackground(.hidden)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(themeColor: theme.accentColor).opacity(0.18), lineWidth: 1)
                }
                .help("Ask a question about the current conversation transcript")

            HStack(spacing: 8) {
                Button {
                    model.conversationAIPromptDraft = "Summarize the key points and action items."
                } label: {
                    Image(systemName: "list.bullet.clipboard")
                }
                .help("Insert a summary prompt")

                Button {
                    model.conversationAIPromptDraft = "What questions came up, and what answers are supported by the transcript?"
                } label: {
                    Image(systemName: "questionmark.bubble")
                }
                .help("Insert a questions prompt")

                Spacer()

                Button {
                    Task {
                        await model.sendConversationAIMessage()
                    }
                } label: {
                    Label(model.isConversationAISending ? "Sending" : "Send", systemImage: "paperplane.fill")
                }
                .disabled(
                    model.isConversationAISending
                    || displayedSegments.isEmpty
                    || model.conversationAIPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .help("Send this question with the current transcript attached as context")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var conversationAIEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2)
                .themeAccentForeground(theme)

            Text(displayedSegments.isEmpty ? "No transcript context yet" : "Ask about this transcript")
                .font(.headline)

            Text(displayedSegments.isEmpty ? "Start or open a conversation before asking AI about it." : "The current transcript is attached to each question only when you press Send.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .themeSurface(theme, cornerRadius: 10, interactive: false)
    }

    private var headerDetail: String {
        if let activeConversation = model.activeConversation {
            return "\(activeConversation.captureMode.displayName) · \(activeConversation.asrProvider) · \(activeConversation.diarizationProvider)"
        }
        if let selected = model.selectedConversationDetail?.session {
            return "\(selected.captureMode.displayName) · \(selected.asrProvider) · \(selected.diarizationProvider)"
        }

        return "\(model.conversationSessions.count) saved conversations · \(model.statusText)"
    }

    private var recordingStatusTitle: String {
        if model.isConversationFinalizing {
            return "Finalizing conversation"
        }
        if model.isConversationRecording {
            return "Recording live conversation"
        }
        return "Ready to record"
    }

    private var recordingStatusDetail: String {
        let liveCount = displayedSegments.filter { $0.state == .live }.count
        let settledCount = displayedSegments.count - liveCount
        if model.isConversationFinalizing {
            return "Closing the audio stream and saving the transcript"
        }
        return "\(settledCount) saved segments · \(liveCount) live · \(displayedAssistCards.count) assists"
    }

    private var diarizationDetail: String {
        guard let activeConversation = model.activeConversation else {
            if let issue = model.selectedDiarizationProviderIssue {
                return issue.detail
            }
            let providerID = model.preferences.conversationDiarizationProvider
            if let info = model.diarizationProviderInfo(for: providerID) {
                return info.available ? "\(info.label) ready" : info.reason ?? "\(info.label) unavailable"
            }
            return "Speaker diarization status not loaded"
        }
        if let info = model.diarizationProviderInfo(for: activeConversation.diarizationProvider) {
            return info.available ? "\(info.label) active" : info.reason ?? "\(info.label) unavailable"
        }
        switch activeConversation.diarizationProvider {
        case "none":
            return "Speaker diarization off"
        case "local-heuristic":
            return "Heuristic labels only; this does not separate speakers from audio"
        case "mlx-sortformer-streaming-fp16":
            return "MLX Sortformer diarization (FP16)"
        case "mlx-sortformer-streaming-fp32":
            return "MLX Sortformer diarization (FP32)"
        case "pyannote":
            return "pyannote diarization"
        default:
            return activeConversation.diarizationProvider
        }
    }

    private var transcriptText: String {
        displayedSegments
            .flatMap(\.diarizedTranscriptLines)
            .map { "\($0.speakerDisplayName) [\($0.timestampLabel)]: \($0.text)" }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasTranscriptText: Bool {
        displayedSegments.contains { segment in
            !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || segment.speakerLines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    private var displayedSegments: [ConversationSegment] {
        if model.isConversationRecording {
            return model.conversationSegments
        }
        return model.selectedConversationDetail?.segments ?? model.conversationSegments
    }

    private var showsLiveDiarizedStream: Bool {
        model.isConversationRecording
            && model.usesLiveConversationDiarizationStream
    }

    private var transcriptScrollTargetID: String {
        return transcriptBottomAnchorID
    }

    private var transcriptScrollSignature: String {
        if showsLiveDiarizedStream {
            guard let segment = displayedSegments.last else {
                return "empty"
            }
            if let line = segment.diarizedTranscriptLines.last {
                return "\(displayedSegments.count)|\(segment.id)|\(line.id)|\(line.speakerID)|\(line.startMs)|\(line.endMs ?? -1)|\(line.text)"
            }
            return "\(displayedSegments.count)|\(segment.id)|\(segment.state.rawValue)|\(segment.text)"
        }
        guard let segment = displayedSegments.last else {
            return "empty"
        }
        return "\(displayedSegments.count)|\(segment.id)|\(segment.state.rawValue)|\(segment.text)"
    }

    private func scrollTranscript(to targetID: String, proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.18)) {
            proxy.scrollTo(targetID, anchor: .bottom)
        }
    }

    private var visibleSpeakerCount: Int {
        var speakerIDs = Set<String>()
        for segment in displayedSegments {
            if !segment.speakerLines.isEmpty {
                for line in segment.speakerLines where !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    speakerIDs.insert(line.speakerID)
                }
                continue
            }

            if !segment.speakerTurns.isEmpty {
                speakerIDs.formUnion(segment.speakerTurns.map(\.speakerID))
                continue
            }

            if !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                speakerIDs.insert(segment.speakerID)
            }
        }
        speakerIDs.remove("pending-speaker")
        return speakerIDs.count
    }

    private var displayedAssistCards: [ConversationAssistCard] {
        if model.isConversationRecording {
            return model.conversationAssistCards
        }
        return model.selectedConversationDetail?.assistCards ?? model.conversationAssistCards
    }

    private var filteredConversationSessions: [ConversationSession] {
        let query = conversationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return model.conversationSessions
        }
        return model.conversationSessions.filter { session in
            [
                session.title,
                session.startedAt,
                session.captureMode.displayName,
                session.asrProvider,
                session.diarizationProvider,
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private func toggleConversationSelection(_ session: ConversationSession) {
        guard !model.isConversationRecording, !session.isActive else { return }
        if selectedConversationIDs.contains(session.id) {
            selectedConversationIDs.remove(session.id)
        } else {
            selectedConversationIDs.insert(session.id)
        }
    }

    private func pruneSelectedConversationIDs() {
        let existingIDs = Set(model.conversationSessions.map(\.id))
        selectedConversationIDs.formIntersection(existingIDs)
    }

    private var conversationDiarizationEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.conversationDiarizationEnabled },
            set: { model.setConversationDiarizationEnabled($0) }
        )
    }

    private var conversationDiarizationPrecisionBinding: Binding<DiarizationPrecision> {
        Binding(
            get: { model.conversationDiarizationPrecision },
            set: { model.setConversationDiarizationPrecision($0) }
        )
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { deletingConversation != nil },
            set: { isPresented in
                if !isPresented {
                    deletingConversation = nil
                }
            }
        )
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

    private func copySources(_ sources: [String]) {
        let sourceText = sources
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !sourceText.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sourceText, forType: .string)
        model.statusText = "Sources copied"
    }

    private func sessionMenuTitle(for session: ConversationSession) -> String {
        let prefix = session.isActive ? "Live" : session.captureMode.displayName
        return "\(prefix) / \(compactConversationDate(session.startedAt))"
    }

    private func beginEditing(_ session: ConversationSession) {
        guard !model.isConversationRecording else {
            model.statusText = "Stop recording before editing"
            return
        }

        Task {
            await model.loadConversationDetail(session)
            guard let detail = model.selectedConversationDetail, detail.session.id == session.id else {
                return
            }
            editingConversationDraft = ConversationEditDraft(detail: detail)
        }
    }
}

private struct ConversationEditDraft: Identifiable {
    let id: String
    var title: String
    var speakers: [ConversationSpeakerEditDraft]
    var segments: [ConversationSegmentEditDraft]

    init(detail: ConversationDetail) {
        id = detail.session.id
        title = detail.session.title

        var seenSpeakers = Set<String>()
        speakers = detail.segments.compactMap { segment in
            guard !seenSpeakers.contains(segment.speakerID) else { return nil }
            seenSpeakers.insert(segment.speakerID)
            return ConversationSpeakerEditDraft(
                id: segment.speakerID,
                displayName: segment.speakerDisplayName
            )
        }

        segments = detail.segments.map { segment in
            ConversationSegmentEditDraft(
                id: segment.id,
                speakerID: segment.speakerID,
                timestampLabel: segment.timestampLabel,
                text: segment.text
            )
        }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && speakers.allSatisfy { !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && segments.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var updateRequest: ConversationDetailUpdateRequest {
        let speakerNames = Dictionary(
            uniqueKeysWithValues: speakers.compactMap { speaker in
                let name = speaker.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : (speaker.id, name)
            }
        )
        let segmentUpdates = segments.map { segment in
            ConversationSegmentUpdateRequest(id: segment.id, text: segment.text)
        }
        return ConversationDetailUpdateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            speakerNames: speakerNames,
            segments: segmentUpdates
        )
    }
}

private struct ConversationSpeakerEditDraft: Identifiable {
    let id: String
    var displayName: String
}

private struct ConversationSegmentEditDraft: Identifiable {
    let id: String
    let speakerID: String
    let timestampLabel: String
    var text: String
}

private struct ConversationEditorSheet: View {
    @State private var draft: ConversationEditDraft
    let theme: OmniVoiceTheme
    let save: (ConversationEditDraft) -> Void
    let cancel: () -> Void

    init(
        draft: ConversationEditDraft,
        theme: OmniVoiceTheme,
        save: @escaping (ConversationEditDraft) -> Void,
        cancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.theme = theme
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit Conversation")
                        .font(.title3.weight(.bold))
                    Text("Rename speakers once and OmniVoice applies it across the saved transcript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            TextField("Conversation title", text: $draft.title)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speakers")
                            .font(.headline)

                        ForEach(draft.speakers.indices, id: \.self) { index in
                            HStack(spacing: 10) {
                                Image(systemName: "person.wave.2")
                                    .themeAccentForeground(theme)
                                    .frame(width: 22)

                                TextField("Speaker name", text: $draft.speakers[index].displayName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        if draft.speakers.isEmpty {
                            Text("This transcript has no speaker labels yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .themeSurface(theme, cornerRadius: 10, interactive: false)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcript")
                            .font(.headline)

                        ForEach(draft.segments.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 8) {
                                    Text(draft.segments[index].timestampLabel)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)

                                    Text(speakerDisplayName(for: draft.segments[index]))
                                        .font(.caption.weight(.semibold))
                                        .themeAccentForeground(theme)

                                    Spacer()
                                }

                                TextEditor(text: $draft.segments[index].text)
                                    .font(.body)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 78)
                                    .padding(8)
                                    .background(Color(themeColor: theme.surfaceTint).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .padding(12)
                            .themeSurface(theme, cornerRadius: 10, interactive: false)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Save") {
                    save(draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSave)
            }
        }
        .padding(18)
        .frame(width: 720, height: 640)
        .background {
            ConversationWindowBackground(theme: theme)
        }
    }

    private func speakerDisplayName(for segment: ConversationSegmentEditDraft) -> String {
        draft.speakers.first { $0.id == segment.speakerID }?.displayName ?? segment.speakerID
    }
}

private struct ConversationMetricPill: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let theme: OmniVoiceTheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .themeAccentForeground(theme)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption.weight(.bold).monospacedDigit())
                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .themePillSurface(theme)
    }
}

private struct ConversationLibraryCard: View {
    let session: ConversationSession
    let isSelected: Bool
    let isMarkedForDelete: Bool
    let isDisabled: Bool
    let theme: OmniVoiceTheme
    let toggleSelection: () -> Void
    let open: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let askAI: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var startedAtLabel: String {
        compactConversationDate(session.startedAt)
    }

    private var accentText: Color {
        Color(themeColor: theme.resolvedPalette(for: colorScheme).accentText)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button(action: toggleSelection) {
                        Image(systemName: isMarkedForDelete ? "checkmark.circle.fill" : "circle")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(isMarkedForDelete ? accentText : .secondary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled || session.isActive)
                    .help(isMarkedForDelete ? "Remove from delete selection" : "Select for bulk delete")

                    Image(systemName: session.isActive ? "record.circle" : "text.bubble")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(session.isActive ? .red : accentText)

                    Text(session.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 44)
                }

                Text(startedAtLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(session.captureMode.displayName) · \(session.asrProvider)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture {
                guard !isDisabled else { return }
                open()
            }

            HStack(spacing: 4) {
                Button(action: edit) {
                    Image(systemName: "square.and.pencil")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Open this conversation in the Editor")
                .disabled(isDisabled || session.isActive)

                Button(action: delete) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Delete conversation")
                .disabled(isDisabled || session.isActive)

                Button(action: askAI) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Open this conversation in Ask AI")
                .disabled(isDisabled || session.isActive)
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            shape.fill(isSelected || isMarkedForDelete ? Color(themeColor: theme.accentColor).opacity(isMarkedForDelete ? 0.20 : 0.16) : Color.white.opacity(0.04))
            shape.stroke(Color(themeColor: theme.accentColor).opacity(isSelected || isMarkedForDelete ? 0.46 : 0.10), lineWidth: 1)
        }
    }
}

private func compactConversationDate(_ value: String) -> String {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: value) {
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) {
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    return value
        .replacingOccurrences(of: "T", with: " ")
        .replacingOccurrences(of: "Z", with: "")
}

private struct ConversationStatusPill: View {
    let text: String
    let isActive: Bool
    let isFinalizing: Bool
    let theme: OmniVoiceTheme

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)
                .shadow(color: indicatorColor.opacity(isActive || isFinalizing ? 0.7 : 0), radius: 6)

            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .themePillSurface(theme)
    }

    private var indicatorColor: Color {
        if isFinalizing {
            return Color(themeColor: theme.accentColor)
        }
        return isActive ? .red : Color(themeColor: theme.accentColor)
    }
}

private struct ConversationAssistHint: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ConversationAIMessageBubble: View {
    let message: AskAIMessage
    let theme: OmniVoiceTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role.displayName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(message.text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    bubbleFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var bubbleFill: Color {
        message.role == .user
            ? Color(themeColor: theme.accentColor).opacity(0.18)
            : Color(themeColor: theme.surfaceTint).opacity(0.12)
    }
}

private struct ConversationAIProviderControls: View {
    @Bindable var model: AppModel
    let theme: OmniVoiceTheme

    var body: some View {
        let provider = model.selectedConversationAIProvider
        let modelChoices = model.conversationAIModelChoices(for: provider)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .themeAccentForeground(theme)
                    .frame(width: 18)
                Text("Conversation AI")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }

            Picker("Provider", selection: providerBinding) {
                ForEach(model.conversationAIProviderChoices) { provider in
                    Text(model.askAIProviderLabel(provider)).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .help("Choose the AI provider used by conversation chat")

            if modelChoices.isEmpty {
                TextField("Model", text: modelBinding)
                    .textFieldStyle(.roundedBorder)
                    .help("Enter the model used by conversation chat")
            } else {
                Picker("Model", selection: modelBinding) {
                    ForEach(modelChoices, id: \.self) { modelName in
                        Text(modelName).tag(modelName)
                    }
                }
                .pickerStyle(.menu)
                .help("Choose the model used by conversation chat")
            }

            Toggle(isOn: webSearchBinding) {
                Label("Web search", systemImage: "network")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .help("Allow conversation chat to use web search when the selected provider supports it")

            Text(model.conversationAIProviderSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .controlSize(.small)
        .padding(10)
        .themeSurface(theme, cornerRadius: 10, interactive: false)
    }

    private var providerBinding: Binding<TextLLMProviderKind> {
        Binding(
            get: { model.selectedConversationAIProvider },
            set: { model.setSelectedConversationAIProvider($0) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { model.selectedConversationAIModel },
            set: { model.setSelectedConversationAIModel($0) }
        )
    }

    private var webSearchBinding: Binding<Bool> {
        Binding(
            get: { model.conversationAIWebSearchEnabled },
            set: { model.setSelectedConversationAIWebSearchEnabled($0) }
        )
    }
}

private struct ConversationSegmentRow: View {
    let segment: ConversationSegment
    let theme: OmniVoiceTheme
    let liveDiarizedStreamMode: Bool

    var body: some View {
        let transcriptLines = segment.diarizedTranscriptLines

        if liveDiarizedStreamMode {
            liveDiarizedStreamRow(transcriptLines)
        } else {
            transcriptRow(transcriptLines)
        }
    }

    private func liveDiarizedStreamRow(_ transcriptLines: [ConversationDiarizedTranscriptLine]) -> some View {
        rowChrome(title: segment.state == .live ? "Live speaker stream" : "Speaker stream") {
            liveDiarizedStreamLines(transcriptLines)
        }
    }

    private func transcriptRow(_ transcriptLines: [ConversationDiarizedTranscriptLine]) -> some View {
        rowChrome(title: segment.state == .live ? "Now speaking" : "Transcript") {
            if shouldRenderSpeakerLineBubbles(transcriptLines) {
                diarizedTranscriptLines(transcriptLines)
            } else {
                plainTranscriptText(transcriptLines)
            }

            if shouldShowSpeakerTurns && transcriptLines.count <= 1 {
                speakerTurnsTimeline
            }
        }
    }

    private func rowChrome<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(segment.timestampLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if segment.state == .live {
                    Label("Live", systemImage: "waveform")
                        .font(.caption2.weight(.semibold))
                        .themeAccentForeground(theme)
                }
            }
            .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer(minLength: 8)

                    if let confidence = segment.confidence {
                        Text(confidence, format: .percent.precision(.fractionLength(0)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .themeSurface(theme, cornerRadius: 9, strong: segment.state == .live, interactive: false)
    }

    private var shouldShowSpeakerTurns: Bool {
        let speakerIDs = Set(segment.speakerTurns.map(\.speakerID))
        return speakerIDs.count > 1 || (segment.speakerTurns.first?.speakerID != nil && segment.speakerTurns.first?.speakerID != segment.speakerID)
    }

    private func shouldRenderSpeakerLineBubbles(_ transcriptLines: [ConversationDiarizedTranscriptLine]) -> Bool {
        !segment.speakerLines.isEmpty || Set(transcriptLines.map(\.speakerID)).count > 1
    }

    private func plainTranscriptText(_ transcriptLines: [ConversationDiarizedTranscriptLine]) -> some View {
        Text(transcriptLines.first?.text ?? segment.text)
            .font(.body)
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func liveDiarizedStreamLines(_ transcriptLines: [ConversationDiarizedTranscriptLine]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(liveDiarizedTranscriptLines(transcriptLines)) { line in
                speakerLineBubble(line)
            }
        }
    }

    private func liveDiarizedTranscriptLines(_ transcriptLines: [ConversationDiarizedTranscriptLine]) -> [ConversationDiarizedTranscriptLine] {
        let nonEmpty = transcriptLines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return nonEmpty.isEmpty ? transcriptLines : nonEmpty
    }

    private func diarizedTranscriptLines(_ transcriptLines: [ConversationDiarizedTranscriptLine]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(transcriptLines) { line in
                speakerLineBubble(line)
            }
        }
    }

    private func speakerLineBubble(_ line: ConversationDiarizedTranscriptLine) -> some View {
        let color = speakerColor(for: line.speakerID)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.55), radius: 5)

                Text(line.speakerDisplayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(line.timestampLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                if segment.state == .live {
                    Text("Live")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12), in: Capsule(style: .continuous))
                }
            }

            Text(line.text)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: shape)
        .background(color.opacity(segment.state == .live ? 0.13 : 0.075), in: shape)
        .overlay {
            shape.stroke(color.opacity(0.30), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4)
                .padding(.vertical, 8)
                .padding(.leading, 5)
        }
        .shadow(color: color.opacity(0.10), radius: 10, x: 0, y: 5)
    }

    private func speakerColor(for speakerID: String) -> Color {
        let knownIndex = speakerIndex(for: speakerID)
        let palette = [
            Color(red: 0.18, green: 0.83, blue: 0.75),
            Color(red: 0.98, green: 0.45, blue: 0.09),
            Color(red: 0.65, green: 0.55, blue: 0.98),
            Color(red: 0.13, green: 0.77, blue: 0.37),
            Color(red: 0.93, green: 0.28, blue: 0.60),
            Color(red: 0.96, green: 0.80, blue: 0.18),
        ]
        return palette[knownIndex % palette.count]
    }

    private func speakerIndex(for speakerID: String) -> Int {
        let suffix = speakerID.replacingOccurrences(of: "speaker-", with: "")
        if let numeric = Int(suffix), numeric > 0 {
            return numeric - 1
        }
        return abs(speakerID.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
    }

    private var speakerTurnsTimeline: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Diarization turns", systemImage: "person.wave.2")
                .font(.caption2.weight(.semibold))
                .themeAccentForeground(theme)

            ForEach(Array(segment.speakerTurns.prefix(6))) { turn in
                HStack(spacing: 8) {
                    Text(displayName(for: turn))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: 78, alignment: .leading)

                    Text(timeRangeLabel(for: turn))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 6)

                    if let confidence = turn.confidence {
                        Text(confidence, format: .percent.precision(.fractionLength(0)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if segment.speakerTurns.count > 6 {
                Text("+ \(segment.speakerTurns.count - 6) more turns")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(themeColor: theme.surfaceTint).opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(themeColor: theme.accentColor).opacity(0.22), lineWidth: 1)
                )
        }
    }

    private func displayName(for turn: SpeakerTurn) -> String {
        if turn.speakerID == segment.speakerID {
            return segment.speakerDisplayName
        }
        let suffix = turn.speakerID.replacingOccurrences(of: "speaker-", with: "")
        if Int(suffix) != nil {
            return "Speaker \(suffix)"
        }
        return turn.speakerID.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func timeRangeLabel(for turn: SpeakerTurn) -> String {
        if let endMs = turn.endMs {
            return "\(timestampLabel(turn.startMs))-\(timestampLabel(endMs))"
        }
        return timestampLabel(turn.startMs)
    }

    private func timestampLabel(_ milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct AssistCardView: View {
    let card: ConversationAssistCard
    let theme: OmniVoiceTheme
    let copy: (String) -> Void
    let speak: (String) -> Void
    let copySources: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: card.kind.systemImage)
                    .font(.headline)
                    .themeAccentForeground(theme)
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

            if !card.sourceReferences.isEmpty {
                Text(sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

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

                Button {
                    copySources(card.sourceReferences)
                } label: {
                    Label("Sources", systemImage: "link")
                }
                .disabled(card.sourceReferences.isEmpty)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .themeSurface(theme, cornerRadius: 10, interactive: false)
    }

    private var sourceSummary: String {
        "Sources: \(card.sourceReferences.joined(separator: ", "))"
    }
}

private struct ConversationWindowBackground: View {
    let theme: OmniVoiceTheme

    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(themeColor: theme.surfaceTint).opacity(0.10),
                Color(themeColor: theme.secondaryAccentColor).opacity(0.045)
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

private extension AskAIMessageRole {
    var displayName: String {
        switch self {
        case .user:
            "You"
        case .assistant:
            "AI"
        case .system:
            "System"
        }
    }
}
