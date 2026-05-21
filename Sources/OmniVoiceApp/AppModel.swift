import AppKit
import Foundation
import Observation
import OmniVoiceCore

enum EngineConnectionState: Equatable {
    case unknown
    case checking
    case online
    case offline(String)

    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .checking: "Checking"
        case .online: "Online"
        case .offline: "Offline"
        }
    }

    var detail: String {
        switch self {
        case .unknown: "Not checked yet"
        case .checking: "Checking local engine"
        case .online: "127.0.0.1:8765"
        case .offline(let message): message
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element: Hashable {
    func uniquePreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct ProviderRecoveryIssue: Equatable {
    let title: String
    let detail: String
}

enum StartupCheckState: Equatable {
    case checking
    case passed
    case warning
    case failed

    var label: String {
        switch self {
        case .checking: "Checking"
        case .passed: "OK"
        case .warning: "Warning"
        case .failed: "Fix needed"
        }
    }
}

enum StartupCheckAction: Equatable {
    case accessibility
    case microphone
    case engine
    case model
    case diarizationModel
    case refresh
}

struct StartupCheckItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let state: StartupCheckState
    let action: StartupCheckAction?
}

enum EditorWorkspaceMode: String, CaseIterable, Hashable, Identifiable {
    case documents
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documents:
            "Documents"
        case .notes:
            "Notes"
        }
    }

    var systemImage: String {
        switch self {
        case .documents:
            "doc.richtext"
        case .notes:
            "note.text"
        }
    }
}

private enum OAuthFlowError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            message
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private static let noDiarizationProviderID = DiarizationProviderResolution.noDiarizationProviderID
    private static let mlxSortformerProviderIDs = DiarizationProviderResolution.mlxSortformerProviderIDs
    private static let githubDeviceCodeEndpoint = URL(string: "https://github.com/login/device/code")!
    private static let githubDeviceTokenEndpoint = URL(string: "https://github.com/login/oauth/access_token")!
    private static let githubDeviceScope = "read:user"
    private static let codexAuthHelpURL = URL(string: "https://developers.openai.com/codex/cli/")!

    private enum DeferredConversationAction {
        case stop
        case cancel
    }

    var preferences: OmniVoicePreferences
    var session: DictationSession
    var captionText: String
    var statusText: String
    var engineState: EngineConnectionState
    var providerStatuses: [EngineProviderInfo]
    var diarizationProviderStatuses: [EngineProviderInfo]
    var translationProviderStatuses: [TranslationProviderInfo]
    var translationCapabilities: TranslationCapabilities?
    var modelStatuses: [EngineModelStatus]
    var modelUpdateInfo: EngineModelUpdateInfo?
    var modelDownloadStatus: EngineModelDownloadStatus?
    var transcripts: [EngineTranscriptRecord]
    var microphoneDevices: [MicrophoneDevice]
    var lastTestResult: String
    var textLLMModelOptions: [TextLLMProviderKind: [String]]
    var textLLMModelDiscoveryStatus: [TextLLMProviderKind: String]
    var textLLMOAuthStatus: [TextLLMProviderKind: String]
    var huggingFaceTokenDraft: String
    var huggingFaceAuthStatus: HuggingFaceAuthStatus?
    var microphoneAuthorized: Bool
    var accessibilityTrusted: Bool
    var streamingDiagnostics: EngineStreamingDiagnostics
    var activeConversation: ConversationSession?
    var conversationSegments: [ConversationSegment]
    var conversationAssistCards: [ConversationAssistCard]
    var conversationSessions: [ConversationSession]
    var selectedConversationDetail: ConversationDetail?
    var isConversationRecording: Bool
    var isConversationFinalizing: Bool
    var isGeneratingConversationInsights: Bool
    var conversationAIProviderOverride: TextLLMProviderKind?
    var conversationAIModelOverride: String?
    var conversationAIWebSearchEnabled: Bool
    var conversationAIMessages: [AskAIMessage]
    var conversationAIPromptDraft: String
    var isConversationAISending: Bool
    var startupChecks: [StartupCheckItem]
    var transcriptionSubjects: [TranscriptionSubject]
    var selectedTranscriptionSubjectID: String?
    var selectedTranscriptionNoteID: String?
    var editorDocuments: [EditorDocument]
    var selectedEditorDocumentID: String?
    var editorWorkspaceMode: EditorWorkspaceMode
    var askAIThreads: [AskAIThread]
    var selectedAskAIThreadID: String?
    var askAIPromptDraft: String
    var isAskAISending: Bool

    private let preferencesStore: PreferencesStore
    private let engineClient: EngineClient
    @ObservationIgnored private let workspaceStore: OmniWorkspaceStore
    @ObservationIgnored private let huggingFaceTokenStore = HuggingFaceTokenStore()
    @ObservationIgnored private let conversationRecorder = ConversationRecorderService()
    @ObservationIgnored private var isConversationStartInFlight = false
    @ObservationIgnored private var isConversationStopInFlight = false
    @ObservationIgnored private var deferredConversationAction: DeferredConversationAction?
    @ObservationIgnored private var liveDiarizationPreviewGeneration = 0
    @ObservationIgnored private var conversationAIContextSessionID: String?
    @ObservationIgnored var onHotkeysChanged: ((OmniVoicePreferences) -> Void)?
    @ObservationIgnored var onThemeChanged: ((OmniVoiceTheme, AppAppearanceMode) -> Void)?

    init(
        preferences: OmniVoicePreferences? = nil,
        preferencesStore: PreferencesStore = PreferencesStore(),
        engineClient: EngineClient = EngineClient(),
        session: DictationSession = DictationSession(),
        captionText: String = "",
        statusText: String = "Ready",
        engineState: EngineConnectionState = .unknown,
        providerStatuses: [EngineProviderInfo] = [],
        diarizationProviderStatuses: [EngineProviderInfo] = [],
        translationProviderStatuses: [TranslationProviderInfo] = [],
        translationCapabilities: TranslationCapabilities? = nil,
        modelStatuses: [EngineModelStatus] = [],
        modelUpdateInfo: EngineModelUpdateInfo? = nil,
        modelDownloadStatus: EngineModelDownloadStatus? = nil,
        transcripts: [EngineTranscriptRecord] = [],
        microphoneDevices: [MicrophoneDevice] = MicrophoneDeviceService.inputDevices(),
        lastTestResult: String = "No test run yet",
        textLLMModelOptions: [TextLLMProviderKind: [String]] = [:],
        textLLMModelDiscoveryStatus: [TextLLMProviderKind: String] = [:],
        textLLMOAuthStatus: [TextLLMProviderKind: String] = [:],
        huggingFaceTokenDraft: String = "",
        huggingFaceAuthStatus: HuggingFaceAuthStatus? = nil,
        microphoneAuthorized: Bool = false,
        accessibilityTrusted: Bool = false,
        streamingDiagnostics: EngineStreamingDiagnostics = .idle,
        activeConversation: ConversationSession? = nil,
        conversationSegments: [ConversationSegment] = [],
        conversationAssistCards: [ConversationAssistCard] = [],
        conversationSessions: [ConversationSession] = [],
        selectedConversationDetail: ConversationDetail? = nil,
        isConversationRecording: Bool = false,
        isConversationFinalizing: Bool = false,
        isGeneratingConversationInsights: Bool = false,
        conversationAIProviderOverride: TextLLMProviderKind? = nil,
        conversationAIModelOverride: String? = nil,
        conversationAIWebSearchEnabled: Bool = false,
        conversationAIMessages: [AskAIMessage] = [],
        conversationAIPromptDraft: String = "",
        isConversationAISending: Bool = false,
        startupChecks: [StartupCheckItem] = [],
        workspaceStore: OmniWorkspaceStore = OmniWorkspaceStore(),
        transcriptionSubjects: [TranscriptionSubject] = [],
        selectedTranscriptionSubjectID: String? = nil,
        selectedTranscriptionNoteID: String? = nil,
        editorDocuments: [EditorDocument] = [],
        selectedEditorDocumentID: String? = nil,
        editorWorkspaceMode: EditorWorkspaceMode = .documents,
        askAIThreads: [AskAIThread] = [],
        selectedAskAIThreadID: String? = nil,
        askAIPromptDraft: String = "",
        isAskAISending: Bool = false
    ) {
        self.preferencesStore = preferencesStore
        self.engineClient = engineClient
        self.workspaceStore = workspaceStore
        var resolvedPreferences = preferences ?? (try? preferencesStore.load()) ?? .defaults
        resolvedPreferences.asrProvider = resolvedPreferences.asrProvider.normalizedForUserSelection
        self.preferences = resolvedPreferences
        self.session = session
        self.captionText = captionText
        self.statusText = statusText
        self.engineState = engineState
        self.providerStatuses = providerStatuses
        self.diarizationProviderStatuses = diarizationProviderStatuses
        self.translationProviderStatuses = translationProviderStatuses
        self.translationCapabilities = translationCapabilities
        self.modelStatuses = modelStatuses
        self.modelUpdateInfo = modelUpdateInfo
        self.modelDownloadStatus = modelDownloadStatus
        self.transcripts = transcripts
        self.microphoneDevices = microphoneDevices
        self.lastTestResult = lastTestResult
        self.textLLMModelOptions = textLLMModelOptions
        self.textLLMModelDiscoveryStatus = textLLMModelDiscoveryStatus
        self.textLLMOAuthStatus = textLLMOAuthStatus
        self.huggingFaceTokenDraft = huggingFaceTokenDraft
        self.huggingFaceAuthStatus = huggingFaceAuthStatus
        self.microphoneAuthorized = microphoneAuthorized
        self.accessibilityTrusted = accessibilityTrusted
        self.streamingDiagnostics = streamingDiagnostics
        self.activeConversation = activeConversation
        self.conversationSegments = conversationSegments
        self.conversationAssistCards = conversationAssistCards
        self.conversationSessions = conversationSessions
        self.selectedConversationDetail = selectedConversationDetail
        self.isConversationRecording = isConversationRecording
        self.isConversationFinalizing = isConversationFinalizing
        self.isGeneratingConversationInsights = isGeneratingConversationInsights
        self.conversationAIProviderOverride = conversationAIProviderOverride
        self.conversationAIModelOverride = conversationAIModelOverride
        self.conversationAIWebSearchEnabled = conversationAIWebSearchEnabled
        self.conversationAIMessages = conversationAIMessages
        self.conversationAIPromptDraft = conversationAIPromptDraft
        self.isConversationAISending = isConversationAISending
        self.startupChecks = startupChecks
        self.transcriptionSubjects = transcriptionSubjects
        self.selectedTranscriptionSubjectID = selectedTranscriptionSubjectID
        self.selectedTranscriptionNoteID = selectedTranscriptionNoteID
        self.editorDocuments = editorDocuments
        self.selectedEditorDocumentID = selectedEditorDocumentID
        self.editorWorkspaceMode = editorWorkspaceMode
        self.askAIThreads = askAIThreads
        self.selectedAskAIThreadID = selectedAskAIThreadID
        self.askAIPromptDraft = askAIPromptDraft
        self.isAskAISending = isAskAISending
        loadWorkspace()
    }

    var activeTheme: OmniVoiceTheme {
        let baseTheme: OmniVoiceTheme = if preferences.themeID == .custom {
            .custom(accent: preferences.customAccentColor)
        } else {
            OmniVoiceTheme.builtInTheme(id: preferences.themeID) ?? .defaultTheme
        }

        return baseTheme.withModes(
            waveformMode: preferences.waveformMode,
            commitAnimationMode: preferences.commitAnimationMode,
            engineFrameSide: preferences.engineFrameSide
        )
    }

    var selectedTranscriptionSubject: TranscriptionSubject? {
        guard let selectedTranscriptionSubjectID else { return transcriptionSubjects.first }
        return transcriptionSubjects.first { $0.id == selectedTranscriptionSubjectID } ?? transcriptionSubjects.first
    }

    var selectedTranscriptionNote: TranscriptionNote? {
        guard let subject = selectedTranscriptionSubject else { return nil }
        guard let selectedTranscriptionNoteID else { return subject.notes.first }
        return subject.notes.first { $0.id == selectedTranscriptionNoteID } ?? subject.notes.first
    }

    var selectedEditorDocument: EditorDocument? {
        guard let selectedEditorDocumentID else { return editorDocuments.first }
        return editorDocuments.first { $0.id == selectedEditorDocumentID } ?? editorDocuments.first
    }

    var selectedAskAIThread: AskAIThread? {
        guard let selectedAskAIThreadID else { return askAIThreads.first }
        return askAIThreads.first { $0.id == selectedAskAIThreadID } ?? askAIThreads.first
    }

    func loadWorkspace() {
        do {
            let snapshot = try workspaceStore.load()
            transcriptionSubjects = snapshot.subjects
            editorDocuments = snapshot.editorDocuments
            askAIThreads = snapshot.askAIThreads
            selectedTranscriptionSubjectID = selectedTranscriptionSubjectID ?? transcriptionSubjects.first?.id
            selectedTranscriptionNoteID = selectedTranscriptionNoteID ?? selectedTranscriptionSubject?.notes.first?.id
            selectedEditorDocumentID = selectedEditorDocumentID ?? editorDocuments.first?.id
            selectedAskAIThreadID = selectedAskAIThreadID ?? askAIThreads.first?.id
        } catch {
            statusText = "Workspace load failed"
        }
    }

    func createTranscriptionSubject(title: String = "New subject") {
        let subject = TranscriptionSubject(title: title)
        transcriptionSubjects.insert(subject, at: 0)
        selectedTranscriptionSubjectID = subject.id
        selectedTranscriptionNoteID = nil
        persistWorkspace()
        statusText = "Subject created"
    }

    func selectTranscriptionSubject(_ subjectID: String) {
        selectedTranscriptionSubjectID = subjectID
        selectedTranscriptionNoteID = selectedTranscriptionSubject?.notes.first?.id
        selectExistingAskAIThread(forSubjectID: subjectID)
    }

    func updateSelectedSubjectTitle(_ title: String) {
        guard let subjectID = selectedTranscriptionSubject?.id,
              let index = transcriptionSubjects.firstIndex(where: { $0.id == subjectID }) else { return }
        transcriptionSubjects[index].title = title
        transcriptionSubjects[index].updatedAt = OmniWorkspaceClock.now()
        persistWorkspace()
    }

    func createTranscriptionNote() {
        if transcriptionSubjects.isEmpty {
            createTranscriptionSubject()
        }
        guard let subjectID = selectedTranscriptionSubject?.id,
              let subjectIndex = transcriptionSubjects.firstIndex(where: { $0.id == subjectID }) else { return }
        let note = TranscriptionNote(subjectID: subjectID, title: "Quick note")
        transcriptionSubjects[subjectIndex].notes.insert(note, at: 0)
        transcriptionSubjects[subjectIndex].updatedAt = OmniWorkspaceClock.now()
        selectedTranscriptionNoteID = note.id
        persistWorkspace()
        statusText = "Note created"
    }

    func updateSelectedTranscriptionNote(title: String? = nil, body: String? = nil) {
        guard let subjectID = selectedTranscriptionSubject?.id,
              let noteID = selectedTranscriptionNote?.id,
              let subjectIndex = transcriptionSubjects.firstIndex(where: { $0.id == subjectID }),
              let noteIndex = transcriptionSubjects[subjectIndex].notes.firstIndex(where: { $0.id == noteID }) else { return }
        if let title {
            transcriptionSubjects[subjectIndex].notes[noteIndex].title = title
        }
        if let body {
            transcriptionSubjects[subjectIndex].notes[noteIndex].body = body
        }
        let now = OmniWorkspaceClock.now()
        transcriptionSubjects[subjectIndex].notes[noteIndex].updatedAt = now
        transcriptionSubjects[subjectIndex].updatedAt = now
        persistWorkspace()
    }

    func cleanupSelectedTranscriptionNote() async {
        guard let note = selectedTranscriptionNote else { return }
        do {
            let result = try await engineClient.cleanup(
                CleanupRequest(
                    rawTranscript: note.body,
                    style: .neutral,
                    dictionaryTerms: preferences.dictionaryTerms
                )
            )
            updateSelectedTranscriptionNote(body: result.text)
            statusText = "Note cleaned"
        } catch {
            statusText = "Note cleanup failed"
        }
    }

    func sendSelectedSubjectToEditor() {
        guard let subject = selectedTranscriptionSubject else { return }
        let document = EditorDocument.from(subject: subject, prompt: "Draft a document using the subject notes as context.")
        editorDocuments.insert(document, at: 0)
        selectedEditorDocumentID = document.id
        editorWorkspaceMode = .documents
        persistWorkspace()
        statusText = "Subject sent to editor"
    }

    @discardableResult
    func sendCurrentConversationToEditor() async -> Bool {
        if let detail = selectedConversationDetail {
            return sendConversationDetailToEditor(detail)
        }
        guard let session = conversationSessions.first else {
            statusText = "No conversation selected"
            return false
        }
        return await sendConversationSessionToEditor(session)
    }

    @discardableResult
    func sendConversationSessionToEditor(_ session: ConversationSession) async -> Bool {
        guard !isConversationRecording else {
            statusText = "Stop recording before editing saved conversations"
            return false
        }

        do {
            let detail: ConversationDetail
            if let currentDetail = selectedConversationDetail, currentDetail.session.id == session.id {
                detail = currentDetail
            } else {
                detail = try await engineClient.conversationDetail(sessionID: session.id)
                selectedConversationDetail = detail
            }
            return sendConversationDetailToEditor(detail)
        } catch {
            statusText = "Conversation unavailable"
            return false
        }
    }

    @discardableResult
    func sendConversationDetailToEditor(_ detail: ConversationDetail) -> Bool {
        let document = EditorDocument.from(conversation: detail)
        editorDocuments.insert(document, at: 0)
        selectedEditorDocumentID = document.id
        persistWorkspace()
        statusText = "\(detail.session.title) sent to editor"
        return true
    }

    func createEditorDocument(title: String = "Untitled") {
        let document = EditorDocument(title: title, bodyMarkdown: "# \(title)\n\n")
        editorDocuments.insert(document, at: 0)
        selectedEditorDocumentID = document.id
        persistWorkspace()
        statusText = "Document created"
    }

    func selectEditorDocument(_ documentID: String) {
        selectedEditorDocumentID = documentID
        if let document = selectedEditorDocument,
           let subjectID = document.sourceSubjectID {
            selectExistingAskAIThread(forSubjectID: subjectID)
        }
    }

    func updateSelectedEditorDocument(title: String? = nil, bodyMarkdown: String? = nil, style: EditorDocumentStyle? = nil) {
        guard let documentID = selectedEditorDocument?.id,
              let index = editorDocuments.firstIndex(where: { $0.id == documentID }) else { return }
        if let title {
            editorDocuments[index].title = title
        }
        if let bodyMarkdown {
            editorDocuments[index].bodyMarkdown = bodyMarkdown
        }
        if let style {
            editorDocuments[index].style = style
        }
        editorDocuments[index].updatedAt = OmniWorkspaceClock.now()
        persistWorkspace()
    }

    func improveSelectedEditorDocumentWithAI(instruction: String = "Improve spelling, grammar, clarity, and formatting. Preserve the author's meaning.") async {
        guard let document = selectedEditorDocument else { return }
        if document.sourceSubjectID != nil {
            prepareAskAIForSelectedEditorDocument()
        }
        guard let configuration = configuredTextLLMConfiguration(for: selectedAskAIThread) else {
            statusText = "Configure an AI provider first"
            return
        }

        statusText = "Editing with AI"
        do {
            let result = try await engineClient.aiHandoff(
                AIHandoffRequest(
                    prompt: "\(instruction)\n\nReturn the full revised Markdown document.",
                    provider: configuration.provider.rawValue,
                    baseURL: configuration.resolvedBaseURL,
                    model: configuration.trimmedModel,
                    apiKey: configuration.trimmedAPIKey,
                    transport: configuration.transport,
                    oauthAccessToken: configuration.trimmedOAuthAccessToken,
                    headers: configuration.resolvedHeaders,
                    context: document.aiContext
                )
            )
            updateSelectedEditorDocument(bodyMarkdown: result.text)
            statusText = "Document updated"
        } catch {
            statusText = "AI edit failed"
        }
    }

    func exportSelectedEditorDocumentMarkdown() {
        guard let document = selectedEditorDocument else { return }
        do {
            let url = try OmniWorkspaceArchive.writeMarkdown(document, rootURL: ConversationArchive.defaultRootURL())
            NSWorkspace.shared.activateFileViewerSelecting([url])
            statusText = "Markdown exported"
        } catch {
            statusText = "Markdown export failed"
        }
    }

    func exportSelectedEditorDocumentDocx() {
        guard let document = selectedEditorDocument else { return }
        do {
            let url = try OmniWorkspaceArchive.writeDocx(document, rootURL: ConversationArchive.defaultRootURL())
            NSWorkspace.shared.activateFileViewerSelecting([url])
            statusText = "DOCX exported"
        } catch {
            statusText = "DOCX export failed"
        }
    }

    func createAskAIThread(title: String = "Ask AI", subjectID: String? = nil) {
        let configuration = configuredTextLLMConfiguration()
        let thread = AskAIThread(
            title: title,
            subjectID: subjectID,
            providerOverride: configuration?.provider,
            modelOverride: configuration?.trimmedModel.nilIfEmpty
        )
        askAIThreads.insert(thread, at: 0)
        selectedAskAIThreadID = thread.id
        askAIPromptDraft = ""
        persistWorkspace()
        statusText = "AI thread created"
    }

    func clearAskAIThreads() {
        let count = askAIThreads.count
        guard count > 0 else {
            statusText = "AI threads already empty"
            return
        }
        askAIThreads.removeAll()
        selectedAskAIThreadID = nil
        askAIPromptDraft = ""
        isAskAISending = false
        persistWorkspace()
        statusText = count == 1 ? "AI thread cleared" : "\(count) AI threads cleared"
    }

    func selectAskAIThread(_ threadID: String) {
        selectedAskAIThreadID = threadID
        guard let thread = askAIThreads.first(where: { $0.id == threadID }),
              let subjectID = thread.subjectID,
              transcriptionSubjects.contains(where: { $0.id == subjectID }) else { return }
        selectedTranscriptionSubjectID = subjectID
        selectedTranscriptionNoteID = selectedTranscriptionSubject?.notes.first?.id
    }

    var askAIProviderChoices: [TextLLMProviderKind] {
        textLLMProviderChoices(selected: selectedAskAIThread?.providerOverride)
    }

    var conversationAIProviderChoices: [TextLLMProviderKind] {
        textLLMProviderChoices(selected: conversationAIProviderOverride)
    }

    var selectedAskAIProvider: TextLLMProviderKind {
        selectedAskAIThread?.providerOverride
            ?? configuredTextLLMConfiguration()?.provider
            ?? preferences.textLLMDefaultProvider
    }

    var selectedAskAIModel: String {
        let threadModel = selectedAskAIThread?.modelOverride?.nilIfEmpty
        if let threadModel {
            return threadModel
        }

        return preferences.textLLMConfiguration(for: selectedAskAIProvider).trimmedModel
    }

    var selectedAskAIWebSearchEnabled: Bool {
        selectedAskAIThread?.webSearchEnabled ?? false
    }

    var selectedConversationAIProvider: TextLLMProviderKind {
        conversationAIProviderOverride
            ?? configuredTextLLMConfiguration()?.provider
            ?? preferences.textLLMDefaultProvider
    }

    var selectedConversationAIModel: String {
        if let model = conversationAIModelOverride?.nilIfEmpty {
            return model
        }
        return preferences.textLLMConfiguration(for: selectedConversationAIProvider).trimmedModel
    }

    func askAIProviderLabel(_ provider: TextLLMProviderKind) -> String {
        preferences.textLLMConfiguration(for: provider).displayName
    }

    func askAIModelChoices(for provider: TextLLMProviderKind) -> [String] {
        let discovered = textLLMModelOptions[provider] ?? []
        let configured = preferences.textLLMConfiguration(for: provider).trimmedModel
        let selected = selectedAskAIProvider == provider ? selectedAskAIModel : ""
        return (discovered + [configured, selected])
            .compactMap(\.nilIfEmpty)
            .uniquePreservingOrder()
    }

    func conversationAIModelChoices(for provider: TextLLMProviderKind) -> [String] {
        let discovered = textLLMModelOptions[provider] ?? []
        let configured = preferences.textLLMConfiguration(for: provider).trimmedModel
        let selected = selectedConversationAIProvider == provider ? selectedConversationAIModel : ""
        return (discovered + [configured, selected])
            .compactMap(\.nilIfEmpty)
            .uniquePreservingOrder()
    }

    func setSelectedAskAIProvider(_ provider: TextLLMProviderKind) {
        guard let index = ensureAskAIThreadForCurrentSelection() else { return }

        let configuredModel = preferences.textLLMConfiguration(for: provider).trimmedModel.nilIfEmpty
        askAIThreads[index].providerOverride = provider
        askAIThreads[index].modelOverride = configuredModel
        askAIThreads[index].updatedAt = OmniWorkspaceClock.now()
        persistWorkspace()
        statusText = "Ask AI provider: \(askAIProviderLabel(provider))"
    }

    func setSelectedAskAIModel(_ modelName: String) {
        guard let index = ensureAskAIThreadForCurrentSelection() else { return }

        askAIThreads[index].modelOverride = modelName.nilIfEmpty
        askAIThreads[index].updatedAt = OmniWorkspaceClock.now()
        persistWorkspace()
        statusText = modelName.nilIfEmpty.map { "Ask AI model: \($0)" } ?? "Ask AI model cleared"
    }

    func setSelectedAskAIWebSearchEnabled(_ enabled: Bool) {
        guard let index = ensureAskAIThreadForCurrentSelection() else { return }

        guard askAIThreads[index].webSearchEnabled != enabled else { return }
        askAIThreads[index].webSearchEnabled = enabled
        askAIThreads[index].updatedAt = OmniWorkspaceClock.now()
        persistWorkspace()
        statusText = enabled ? "Ask AI web search on" : "Ask AI web search off"
    }

    func setSelectedConversationAIProvider(_ provider: TextLLMProviderKind) {
        conversationAIProviderOverride = provider
        conversationAIModelOverride = preferences.textLLMConfiguration(for: provider).trimmedModel.nilIfEmpty
        statusText = "Conversation AI provider: \(askAIProviderLabel(provider))"
    }

    func setSelectedConversationAIModel(_ modelName: String) {
        conversationAIModelOverride = modelName.nilIfEmpty
        statusText = modelName.nilIfEmpty.map { "Conversation AI model: \($0)" } ?? "Conversation AI model cleared"
    }

    func setSelectedConversationAIWebSearchEnabled(_ enabled: Bool) {
        guard conversationAIWebSearchEnabled != enabled else { return }
        conversationAIWebSearchEnabled = enabled
        statusText = enabled ? "Conversation AI web search on" : "Conversation AI web search off"
    }

    var conversationAIContextSummary: String {
        if let activeConversation {
            return "\(activeConversation.title) / live transcript"
        }
        if let selectedConversationDetail {
            return "\(selectedConversationDetail.session.title) / saved transcript"
        }
        return "Open or record a conversation to ask about it"
    }

    func clearConversationAIChat() {
        conversationAIMessages = []
        conversationAIPromptDraft = ""
        conversationAIContextSessionID = nil
        statusText = "Conversation AI cleared"
    }

    func sendConversationAIMessage() async {
        let prompt = conversationAIPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard !isConversationAISending else { return }
        guard let configuration = configuredConversationTextLLMConfiguration() else {
            statusText = "Configure a conversation AI provider first"
            return
        }
        guard let detail = await conversationDetailForAIChat() else {
            statusText = "No conversation selected"
            return
        }
        guard detail.segments.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            statusText = "No transcript yet"
            return
        }

        if conversationAIContextSessionID != detail.session.id {
            conversationAIMessages = []
            conversationAIContextSessionID = detail.session.id
        }

        let history = conversationAIMessages
        conversationAIPromptDraft = ""
        isConversationAISending = true
        conversationAIMessages.append(AskAIMessage(role: .user, text: prompt))
        statusText = "Asking conversation AI"
        defer { isConversationAISending = false }

        do {
            let result = try await engineClient.aiChat(
                AIChatRequest(
                    provider: configuration.provider.rawValue,
                    baseURL: configuration.resolvedBaseURL,
                    model: configuration.trimmedModel,
                    apiKey: configuration.trimmedAPIKey,
                    transport: configuration.transport,
                    oauthAccessToken: configuration.trimmedOAuthAccessToken,
                    headers: configuration.resolvedHeaders,
                    messages: ConversationAIChatContext.messages(history: history, question: prompt),
                    attachments: [ConversationAIChatContext.transcriptAttachment(for: detail)],
                    webSearchEnabled: conversationAIWebSearchEnabled
                )
            )
            conversationAIMessages.append(AskAIMessage(role: .assistant, text: result.text))
            statusText = "Conversation AI replied"
        } catch {
            conversationAIMessages.append(AskAIMessage(role: .assistant, text: "AI request failed: \(error.localizedDescription)"))
            statusText = "Conversation AI failed"
        }
    }

    func prepareAskAIForSelectedSubject() {
        guard let subject = selectedTranscriptionSubject else { return }
        let index = selectOrCreateAskAIThread(for: subject)
        upsertSubjectContext(subject, inThreadAt: index)
        persistWorkspace()
    }

    func prepareAskAIForSelectedEditorDocument() {
        guard let document = selectedEditorDocument,
              let subject = subject(forID: document.sourceSubjectID) else { return }
        let index = selectOrCreateAskAIThread(for: subject)
        upsertSubjectContext(subject, inThreadAt: index)
        persistWorkspace()
    }

    func addSelectedSubjectToAskAI() {
        guard let subject = selectedTranscriptionSubject else { return }
        let index = selectOrCreateAskAIThread(for: subject)
        upsertSubjectContext(subject, inThreadAt: index)
        persistWorkspace()
        statusText = "\(subject.title) AI session ready"
    }

    func addSelectedTranscriptionNoteToAskAI() {
        guard let note = selectedTranscriptionNote,
              let subject = selectedTranscriptionSubject else { return }
        let index = selectOrCreateAskAIThread(for: subject)
        upsertSubjectContext(subject, inThreadAt: index)
        addAttachment(
            AskAIContextAttachment(
                kind: .transcript,
                title: note.title,
                text: "# \(note.title)\n\n\(note.body.trimmingCharacters(in: .whitespacesAndNewlines))"
            ),
            toThreadAt: index,
            status: "\(note.title) added to \(subject.title)"
        )
    }

    func addSelectedEditorDocumentToAskAI() {
        guard let document = selectedEditorDocument else { return }
        if let subject = subject(forID: document.sourceSubjectID) {
            let index = selectOrCreateAskAIThread(for: subject)
            upsertSubjectContext(subject, inThreadAt: index)
            addAttachment(
                AskAIContextAttachment(document: document),
                toThreadAt: index,
                status: "\(document.title) added to \(subject.title)"
            )
            return
        }
        addAttachmentToSelectedAskAIThread(AskAIContextAttachment(document: document))
    }

    @discardableResult
    func addConversationToAskAI(_ detail: ConversationDetail) -> Bool {
        addAttachmentToSelectedAskAIThread(AskAIContextAttachment(conversation: detail))
        return true
    }

    @discardableResult
    func addCurrentConversationToAskAI() async -> Bool {
        if let detail = selectedConversationDetail {
            return addConversationToAskAI(detail)
        }
        guard let session = conversationSessions.first else {
            statusText = "No conversation selected"
            return false
        }
        return await addConversationSessionToAskAI(session)
    }

    @discardableResult
    func addConversationSessionToAskAI(_ session: ConversationSession) async -> Bool {
        guard !isConversationRecording else {
            statusText = "Stop recording before adding saved conversations to AI"
            return false
        }

        do {
            let detail: ConversationDetail
            if let currentDetail = selectedConversationDetail, currentDetail.session.id == session.id {
                detail = currentDetail
            } else {
                detail = try await engineClient.conversationDetail(sessionID: session.id)
                selectedConversationDetail = detail
            }
            addConversationToAskAI(detail)
            statusText = "\(detail.session.title) added to Ask AI"
            return true
        } catch {
            statusText = "Conversation unavailable"
            return false
        }
    }

    func addTranscriptToAskAI(_ transcript: EngineTranscriptRecord) {
        addAttachmentToSelectedAskAIThread(AskAIContextAttachment(transcript: transcript))
        statusText = "Transcript added to Ask AI"
    }

    func addLatestTranscriptToAskAI() {
        guard let transcript = transcripts.first else {
            statusText = "No transcripts available"
            return
        }
        addTranscriptToAskAI(transcript)
    }

    func addURLToAskAI(url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let attachment = AskAIAttachmentLoader.attachment(for: url)
        addAttachmentToSelectedAskAIThread(attachment)
        statusText = "\(attachment.title) added to Ask AI"
    }

    func addFileToAskAI(url: URL) {
        addURLToAskAI(url: url)
    }

    func addImageToAskAI(url: URL) {
        addURLToAskAI(url: url)
    }

    func addAudioToAskAI(url: URL) {
        addURLToAskAI(url: url)
    }

    func sendAskAIMessage() async {
        let prompt = askAIPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        if askAIThreads.isEmpty {
            createAskAIThread()
        }
        guard let threadID = selectedAskAIThread?.id,
              let index = askAIThreads.firstIndex(where: { $0.id == threadID }) else {
            statusText = "Configure an AI provider first"
            return
        }
        guard let configuration = configuredTextLLMConfiguration(for: askAIThreads[index]) else {
            statusText = "Configure an AI provider first"
            return
        }

        askAIPromptDraft = ""
        isAskAISending = true
        let userMessage = AskAIMessage(role: .user, text: prompt)
        askAIThreads[index].messages.append(userMessage)
        if askAIThreads[index].subjectID == nil, askAIThreads[index].messages.count == 1 {
            askAIThreads[index].title = String(prompt.prefix(54))
        }
        askAIThreads[index].updatedAt = OmniWorkspaceClock.now()
        persistWorkspace()

        do {
            let outboundMessages = askAIThreads[index].messages.map {
                AIChatMessage(role: $0.role, content: $0.text)
            }
            let outboundAttachments = askAIThreads[index].attachments.map(AIChatAttachment.init)
            let result = try await engineClient.aiChat(
                AIChatRequest(
                    provider: configuration.provider.rawValue,
                    baseURL: configuration.resolvedBaseURL,
                    model: configuration.trimmedModel,
                    apiKey: configuration.trimmedAPIKey,
                    transport: configuration.transport,
                    oauthAccessToken: configuration.trimmedOAuthAccessToken,
                    headers: configuration.resolvedHeaders,
                    messages: outboundMessages,
                    attachments: outboundAttachments,
                    webSearchEnabled: askAIThreads[index].webSearchEnabled
                )
            )
            if let updatedIndex = askAIThreads.firstIndex(where: { $0.id == threadID }) {
                askAIThreads[updatedIndex].messages.append(AskAIMessage(role: .assistant, text: result.text))
                askAIThreads[updatedIndex].updatedAt = OmniWorkspaceClock.now()
            }
            statusText = "AI replied"
        } catch {
            if let updatedIndex = askAIThreads.firstIndex(where: { $0.id == threadID }) {
                askAIThreads[updatedIndex].messages.append(AskAIMessage(role: .assistant, text: "AI request failed: \(error.localizedDescription)"))
                askAIThreads[updatedIndex].updatedAt = OmniWorkspaceClock.now()
            }
            statusText = "AI request failed"
        }
        isAskAISending = false
        persistWorkspace()
    }

    private func addAttachmentToSelectedAskAIThread(_ attachment: AskAIContextAttachment) {
        guard let index = ensureAskAIThreadForCurrentSelection() else { return }
        addAttachment(attachment, toThreadAt: index)
    }

    private func addAttachment(_ attachment: AskAIContextAttachment, toThreadAt index: Int, status: String = "Context added") {
        guard askAIThreads.indices.contains(index) else { return }
        askAIThreads[index].attachments.append(attachment)
        askAIThreads[index].updatedAt = OmniWorkspaceClock.now()
        persistWorkspace()
        statusText = status
    }

    var askAIProviderSummary: String {
        guard let configuration = configuredTextLLMConfiguration(for: selectedAskAIThread) else {
            return "No AI provider configured"
        }
        let model = configuration.trimmedModel.isEmpty ? "No model selected" : configuration.trimmedModel
        let subject = selectedAskAIThread.flatMap { subjectLabel(for: $0) }.map { "\($0) • " } ?? ""
        let web = selectedAskAIWebSearchEnabled ? " • Web search" : ""
        return "\(subject)\(configuration.provider.displayName) • \(model)\(web)"
    }

    var conversationAIProviderSummary: String {
        guard let configuration = configuredConversationTextLLMConfiguration() else {
            return "No conversation AI provider configured"
        }
        let model = configuration.trimmedModel.isEmpty ? "No model selected" : configuration.trimmedModel
        let web = conversationAIWebSearchEnabled ? " • Web search" : ""
        return "\(configuration.provider.displayName) • \(model)\(web)"
    }

    func askAIThreadSubtitle(_ thread: AskAIThread) -> String {
        let subject = subjectLabel(for: thread).map { "\($0) • " } ?? ""
        return "\(subject)\(thread.messages.count) messages, \(thread.attachments.count) context"
    }

    private func ensureAskAIThreadForCurrentSelection() -> Int? {
        if let threadID = selectedAskAIThread?.id,
           let index = askAIThreads.firstIndex(where: { $0.id == threadID }) {
            return index
        }

        if let subject = selectedTranscriptionSubject {
            let index = selectOrCreateAskAIThread(for: subject)
            upsertSubjectContext(subject, inThreadAt: index)
            persistWorkspace()
            return index
        }

        createAskAIThread()
        guard let threadID = selectedAskAIThread?.id else { return nil }
        return askAIThreads.firstIndex(where: { $0.id == threadID })
    }

    @discardableResult
    private func selectOrCreateAskAIThread(for subject: TranscriptionSubject) -> Int {
        if let index = askAIThreads.firstIndex(where: { $0.subjectID == subject.id }) {
            selectedAskAIThreadID = askAIThreads[index].id
            return index
        }

        let configuration = configuredTextLLMConfiguration()
        let thread = AskAIThread(
            title: subject.title,
            subjectID: subject.id,
            providerOverride: configuration?.provider,
            modelOverride: configuration?.trimmedModel.nilIfEmpty,
            attachments: [AskAIContextAttachment(subject: subject)]
        )
        askAIThreads.insert(thread, at: 0)
        selectedAskAIThreadID = thread.id
        askAIPromptDraft = ""
        return 0
    }

    private func selectExistingAskAIThread(forSubjectID subjectID: String) {
        if let thread = askAIThreads.first(where: { $0.subjectID == subjectID }) {
            selectedAskAIThreadID = thread.id
        }
    }

    private func upsertSubjectContext(_ subject: TranscriptionSubject, inThreadAt index: Int) {
        guard askAIThreads.indices.contains(index) else { return }
        askAIThreads[index].title = subject.title
        askAIThreads[index].subjectID = subject.id
        askAIThreads[index].attachments.removeAll { $0.kind == .subject }
        askAIThreads[index].attachments.insert(AskAIContextAttachment(subject: subject), at: 0)
        askAIThreads[index].updatedAt = OmniWorkspaceClock.now()
    }

    private func subject(forID subjectID: String?) -> TranscriptionSubject? {
        guard let subjectID else { return nil }
        return transcriptionSubjects.first { $0.id == subjectID }
    }

    private func subjectLabel(for thread: AskAIThread) -> String? {
        guard let subjectID = thread.subjectID else { return nil }
        return subject(forID: subjectID)?.title ?? "Subject"
    }

    private func configuredTextLLMConfiguration() -> TextLLMProviderConfiguration? {
        let preferred = preferences.textLLMConfiguration(for: preferences.textLLMDefaultProvider)
        if preferred.isConfigured {
            return preferred
        }
        return preferences.textLLMProviders.first { $0.isConfigured }
    }

    private func textLLMProviderChoices(selected: TextLLMProviderKind?) -> [TextLLMProviderKind] {
        preferences.textLLMProviders.providerSelectionChoices(
            selected: selected,
            defaultProvider: preferences.textLLMDefaultProvider
        )
    }

    private func configuredConversationTextLLMConfiguration() -> TextLLMProviderConfiguration? {
        let provider = selectedConversationAIProvider
        var configuration = preferences.textLLMConfiguration(for: provider)
        if let modelOverride = selectedConversationAIModel.nilIfEmpty {
            configuration.model = modelOverride
        }
        if configuration.isConfigured {
            return configuration.normalized()
        }
        guard conversationAIProviderOverride == nil, conversationAIModelOverride == nil else {
            return nil
        }
        return configuredTextLLMConfiguration()
    }

    private func configuredTextLLMConfiguration(for thread: AskAIThread?) -> TextLLMProviderConfiguration? {
        let provider = thread?.providerOverride ?? configuredTextLLMConfiguration()?.provider ?? preferences.textLLMDefaultProvider
        var configuration = preferences.textLLMConfiguration(for: provider)
        if let modelOverride = thread?.modelOverride?.nilIfEmpty {
            configuration.model = modelOverride
        }
        if configuration.isConfigured {
            return configuration.normalized()
        }
        return configuredTextLLMConfiguration()
    }

    private func persistWorkspace() {
        do {
            try workspaceStore.save(
                OmniWorkspaceSnapshot(
                    subjects: transcriptionSubjects,
                    editorDocuments: editorDocuments,
                    askAIThreads: askAIThreads
                )
            )
        } catch {
            statusText = "Workspace save failed"
        }
    }

    func cycleStyle() {
        setStyle(preferences.style.next())
    }

    func cycleASRProvider() {
        preferences.cycleASRProvider()
        persistPreferences()
        statusText = "ASR: \(preferences.asrProvider.rawValue)"
    }

    func setStyle(_ style: StyleProfile) {
        preferences.style = style
        persistPreferences()
        statusText = "Style: \(style.displayName)"
    }

    func setASRProvider(_ provider: ASRProviderKind) {
        let normalizedProvider = provider.normalizedForUserSelection
        preferences.asrProvider = normalizedProvider
        persistPreferences()
        modelUpdateInfo = nil
        modelDownloadStatus = nil
        statusText = "ASR: \(normalizedProvider.rawValue)"
    }

    func completeFirstRunSetup() {
        preferences.firstRunSetupCompleted = true
        persistPreferences()
        statusText = "Setup guide completed"
    }

    func setMicrophoneID(_ microphoneID: String?) {
        preferences.microphoneID = microphoneID
        persistPreferences()
        statusText = "Microphone: \(microphoneLabel(for: microphoneID))"
    }

    func setThemeID(_ themeID: OmniVoiceThemeID) {
        let presetTheme = themeID == .custom ? nil : OmniVoiceTheme.builtInTheme(id: themeID)
        let waveformMode = presetTheme?.waveformMode ?? preferences.waveformMode
        let commitAnimationMode = presetTheme?.commitAnimationMode ?? preferences.commitAnimationMode
        let engineFrameSide = presetTheme?.engineFrameSide ?? preferences.engineFrameSide

        guard preferences.themeID != themeID ||
            preferences.waveformMode != waveformMode ||
            preferences.commitAnimationMode != commitAnimationMode ||
            preferences.engineFrameSide != engineFrameSide else {
            return
        }

        preferences.themeID = themeID
        preferences.waveformMode = waveformMode
        preferences.commitAnimationMode = commitAnimationMode
        preferences.engineFrameSide = engineFrameSide
        guard persistPreferences() else {
            return
        }

        statusText = "Theme: \(activeTheme.name)"
        notifyThemeChanged()
    }

    func setCustomAccentColor(_ color: ThemeColor) {
        guard preferences.customAccentColor != color || preferences.themeID != .custom else {
            return
        }

        preferences.customAccentColor = color
        preferences.themeID = .custom
        guard persistPreferences() else {
            return
        }

        statusText = "Custom accent: \(color.hex)"
        notifyThemeChanged()
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        guard preferences.appearanceMode != mode else {
            return
        }

        preferences.appearanceMode = mode
        guard persistPreferences() else {
            return
        }

        statusText = "Appearance: \(mode.displayName)"
        notifyThemeChanged()
    }

    func setWaveformMode(_ mode: WaveformMode) {
        guard preferences.waveformMode != mode else {
            return
        }

        preferences.waveformMode = mode
        guard persistPreferences() else {
            return
        }

        statusText = "Waveform: \(mode.displayName)"
    }

    func setEngineFrameSide(_ side: EngineFrameSide) {
        guard preferences.engineFrameSide != side else {
            return
        }

        preferences.engineFrameSide = side
        guard persistPreferences() else {
            return
        }

        statusText = "Engine frame: \(side.displayName)"
    }

    func setEngineFrameHandlePosition(_ position: Double) {
        let clamped = OmniVoicePreferences.clampedHandlePosition(position)
        guard abs(preferences.engineFrameHandlePosition - clamped) > 0.005 else {
            return
        }

        preferences.engineFrameHandlePosition = clamped
        guard persistPreferences() else {
            return
        }

        statusText = "History handle moved"
    }

    func setCustomSpeechModelPath(_ path: String) {
        guard preferences.customSpeechModelPath != path else {
            return
        }

        preferences.customSpeechModelPath = path
        guard persistPreferences() else {
            return
        }

        statusText = path.isEmpty ? "Custom speech model cleared" : "Custom speech model selected"
    }

    func setCustomTranslationModelPath(_ path: String) {
        guard preferences.customTranslationModelPath != path else {
            return
        }

        preferences.customTranslationModelPath = path
        guard persistPreferences() else {
            return
        }

        translationCapabilities = nil
        statusText = path.isEmpty ? "Translation model cleared" : "Translation model selected"
        Task {
            await refreshTranslationCapabilities()
        }
    }

    func setTranslationProvider(_ provider: TranslationProviderKind) {
        guard preferences.translationProvider != provider else {
            return
        }

        preferences.translationProvider = provider
        guard persistPreferences() else {
            return
        }

        translationCapabilities = nil
        statusText = "Translation: \(provider.displayName)"
        Task {
            await refreshTranslationCapabilities()
        }
    }

    func setTranslationModelProviderID(_ providerID: String) {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? TranslationModelRecommendation.defaultProviderID : trimmed
        let shouldUseMLXTranslator = preferences.translationProvider != .translateGemmaMLX
        guard preferences.translationModelProviderID != resolved || shouldUseMLXTranslator else {
            return
        }

        preferences.translationModelProviderID = resolved
        preferences.translationProvider = .translateGemmaMLX
        guard persistPreferences() else {
            return
        }

        modelUpdateInfo = nil
        modelDownloadStatus = nil
        translationCapabilities = nil
        statusText = "Translation model: \(translationModelLabel(for: resolved))"
        Task {
            await refreshTranslationCapabilities()
        }
    }

    func translationModelLabel(for providerID: String) -> String {
        modelStatus(forProviderID: providerID)?.label
            ?? TranslationModelRecommendation(providerID: providerID).displayName
    }

    func selectedTranslationModelProviderID() -> String {
        let trimmed = preferences.translationModelProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? TranslationModelRecommendation.defaultProviderID : trimmed
    }

    func effectiveTranslationModelPath() -> String {
        let customPath = preferences.customTranslationModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customPath.isEmpty {
            return customPath
        }

        return modelStatus(forProviderID: selectedTranslationModelProviderID())?.localPath ?? ""
    }

    var translationSourceLanguageOptions: [TranslationLanguageOption] {
        translationCapabilities?.sourceLanguages ?? [TranslationLanguageOption(code: "en", name: "English", isDefault: true)]
    }

    var translationTargetLanguageOptions: [TranslationLanguageOption] {
        if let options = translationCapabilities?.targetLanguages, !options.isEmpty {
            return options
        }

        return [
            TranslationLanguageOption(code: "en", name: "English"),
            TranslationLanguageOption(code: "es", name: "Spanish", isDefault: true),
            TranslationLanguageOption(code: "zh", name: "Chinese"),
            TranslationLanguageOption(code: "fr", name: "French"),
            TranslationLanguageOption(code: "de", name: "German"),
        ]
    }

    func translationLanguageLabel(for code: String, in options: [TranslationLanguageOption]) -> String {
        if let option = options.first(where: { $0.code == code }) {
            return "\(option.name) (\(option.code))"
        }
        return code
    }

    func setConversationDiarizationProvider(_ providerID: String) {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? Self.noDiarizationProviderID : trimmed
        let resolvedPrecision = Self.mlxSortformerProviderIDs.contains(resolved)
            ? DiarizationPrecision(providerID: resolved)
            : preferences.conversationDiarizationPrecision
        guard preferences.conversationDiarizationProvider != resolved
                || preferences.conversationDiarizationPrecision != resolvedPrecision else {
            return
        }

        preferences.conversationDiarizationProvider = resolved
        preferences.conversationDiarizationPrecision = resolvedPrecision
        guard persistPreferences() else {
            return
        }

        modelUpdateInfo = nil
        modelDownloadStatus = nil
        statusText = "Diarization: \(diarizationLabel(for: resolved))"
    }

    func setConversationDiarizationEnabled(_ enabled: Bool) {
        let providerID = enabled ? preferences.conversationDiarizationPrecision.providerID : Self.noDiarizationProviderID
        setConversationDiarizationProvider(providerID)
    }

    func disableConversationDiarizationWhenIdle(preserveStatus: Bool = true) {
        guard !isConversationRecording, !isConversationFinalizing else {
            return
        }

        // Idle resource management must not rewrite the user's selected provider.
        // The engine loads Sortformer lazily for conversation finalization; changing
        // the saved provider here causes the next recording to start with diarization off.
        if !preserveStatus {
            statusText = conversationDiarizationEnabled
                ? "Diarization ready: \(diarizationLabel(for: preferences.conversationDiarizationProvider))"
                : "Diarization off"
        }
    }

    func setConversationDiarizationPrecision(_ precision: DiarizationPrecision) {
        if conversationDiarizationEnabled {
            setConversationDiarizationProvider(precision.providerID)
            return
        }

        guard preferences.conversationDiarizationPrecision != precision else {
            return
        }

        preferences.conversationDiarizationPrecision = precision
        guard persistPreferences() else {
            return
        }

        modelUpdateInfo = nil
        modelDownloadStatus = nil
        statusText = "Diarization precision: \(precision.displayName)"
    }

    func setLiveTranslationEnabled(_ enabled: Bool) {
        guard preferences.liveTranslationEnabled != enabled else {
            return
        }

        preferences.liveTranslationEnabled = enabled
        guard persistPreferences() else {
            return
        }

        statusText = enabled ? "Live translation enabled" : "Live translation disabled"
    }

    func setLiveDraftInsertionEnabled(_ enabled: Bool) {
        guard preferences.liveDraftInsertionEnabled != enabled else {
            return
        }

        preferences.liveDraftInsertionEnabled = enabled
        guard persistPreferences() else {
            return
        }

        statusText = enabled ? "Live draft typing enabled" : "Live draft typing disabled"
    }

    func setConversationArchiveFolderPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? ConversationArchive.defaultRootURL().path : trimmed
        guard preferences.conversationArchiveFolderPath != resolved else {
            return
        }

        preferences.conversationArchiveFolderPath = resolved
        guard persistPreferences() else {
            return
        }

        statusText = "Conversation archive folder updated"
    }

    func setAutomaticallyArchiveConversations(_ enabled: Bool) {
        guard preferences.automaticallyArchiveConversations != enabled else {
            return
        }

        preferences.automaticallyArchiveConversations = enabled
        guard persistPreferences() else {
            return
        }

        statusText = enabled ? "Conversation archiving enabled" : "Conversation archiving disabled"
    }

    func setTranslationSourceLanguage(_ language: String) {
        let normalized = normalizedLanguageCode(language, fallback: "en")
        guard preferences.translationSourceLanguage != normalized else {
            return
        }

        preferences.translationSourceLanguage = normalized
        guard persistPreferences() else {
            return
        }

        statusText = "Translation source: \(normalized)"
    }

    func setTranslationTargetLanguage(_ language: String) {
        let normalized = normalizedLanguageCode(language, fallback: "es")
        guard preferences.translationTargetLanguage != normalized else {
            return
        }

        preferences.translationTargetLanguage = normalized
        guard persistPreferences() else {
            return
        }

        statusText = "Translation target: \(normalized)"
    }

    func setTranslationQuickTargetLanguage(_ language: String, slot: Int) {
        guard slot >= 0, slot < OmniVoicePreferences.translationQuickTargetLanguageSlotCount else { return }

        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "" : normalizedLanguageCode(trimmed, fallback: OmniVoicePreferences.defaultTranslationQuickTargetLanguages[0])
        var languages = preferences.translationQuickTargetLanguages
        while languages.count < OmniVoicePreferences.translationQuickTargetLanguageSlotCount {
            languages.append("")
        }
        languages[slot] = normalized

        let updated = OmniVoicePreferences.normalizedTranslationQuickTargetLanguages(languages)
        guard preferences.translationQuickTargetLanguages != updated else {
            return
        }

        preferences.translationQuickTargetLanguages = updated
        guard persistPreferences() else {
            return
        }

        statusText = normalized.isEmpty
            ? "Hot language \(slot + 1): Not used"
            : "Hot language \(slot + 1): \(translationLanguageLabel(for: normalized, in: translationTargetLanguageOptions))"
    }

    func cycleQuickTranslationTargetLanguage() {
        let quickTargets = quickTranslationTargetLanguagesForCurrentModel()
        guard !quickTargets.isEmpty else {
            statusText = "No translation languages available"
            return
        }

        let current = normalizedLanguageCode(preferences.translationTargetLanguage, fallback: quickTargets[0])
        let next: String
        if let currentIndex = quickTargets.firstIndex(of: current) {
            next = quickTargets[(currentIndex + 1) % quickTargets.count]
        } else {
            next = quickTargets[0]
        }

        guard preferences.translationTargetLanguage != next else {
            statusText = "Translation target: \(translationLanguageLabel(for: next, in: translationTargetLanguageOptions))"
            return
        }

        preferences.translationTargetLanguage = next
        guard persistPreferences() else {
            return
        }

        statusText = "Translation target: \(translationLanguageLabel(for: next, in: translationTargetLanguageOptions))"
    }

    func selectQuickTranslationTargetLanguage(slot: Int) {
        let quickTargets = preferences.normalizedTranslationQuickTargetLanguages()
        guard quickTargets.indices.contains(slot) else {
            statusText = "Hot language \(slot + 1) is not configured"
            return
        }

        let target = quickTargets[slot]
        let supportedCodes = Set(translationTargetLanguageOptions.map(\.code))
        guard supportedCodes.isEmpty || supportedCodes.contains(target) else {
            statusText = "\(translationLanguageLabel(for: target, in: translationTargetLanguageOptions)) is not supported by this model"
            return
        }

        guard preferences.translationTargetLanguage != target else {
            statusText = "Translation target: \(translationLanguageLabel(for: target, in: translationTargetLanguageOptions))"
            return
        }

        preferences.translationTargetLanguage = target
        guard persistPreferences() else {
            return
        }

        statusText = "Translation target: \(translationLanguageLabel(for: target, in: translationTargetLanguageOptions))"
    }

    func hotMenuActionLabel(_ action: HotMenuAction) -> String {
        preferences.hotMenuStatusLabel(for: action, targetLanguageOptions: translationTargetLanguageOptions)
    }

    func setOpenAICompatibleBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.openAICompatibleBaseURL != trimmed else {
            return
        }

        var configuration = preferences.textLLMConfiguration(for: TextLLMProviderKind.custom)
        configuration.baseURL = trimmed
        preferences.setTextLLMConfiguration(configuration)
        guard persistPreferences() else {
            return
        }

        statusText = trimmed.isEmpty ? "AI endpoint cleared" : "AI endpoint updated"
    }

    func setOpenAICompatibleModel(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.openAICompatibleModel != trimmed else {
            return
        }

        var configuration = preferences.textLLMConfiguration(for: TextLLMProviderKind.custom)
        configuration.model = trimmed
        preferences.setTextLLMConfiguration(configuration)
        guard persistPreferences() else {
            return
        }

        statusText = trimmed.isEmpty ? "AI model cleared" : "AI model updated"
    }

    func setOpenAICompatibleAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.openAICompatibleAPIKey != trimmed else {
            return
        }

        var configuration = preferences.textLLMConfiguration(for: TextLLMProviderKind.custom)
        configuration.apiKey = trimmed
        preferences.setTextLLMConfiguration(configuration)
        guard persistPreferences() else {
            return
        }

        statusText = trimmed.isEmpty ? "AI API key cleared" : "AI API key updated"
    }

    func loadHuggingFaceTokenFromKeychain() {
        huggingFaceTokenDraft = huggingFaceTokenStore.load() ?? ""
        statusText = huggingFaceTokenDraft.isEmpty ? "No Hugging Face token in Keychain" : "Hugging Face token loaded"
    }

    func saveHuggingFaceTokenToKeychain() {
        do {
            try huggingFaceTokenStore.save(huggingFaceTokenDraft)
            statusText = huggingFaceTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Hugging Face token cleared"
                : "Hugging Face token saved"
        } catch {
            statusText = "Hugging Face token save failed"
        }
    }

    func clearHuggingFaceToken() {
        do {
            try huggingFaceTokenStore.delete()
            huggingFaceTokenDraft = ""
            huggingFaceAuthStatus = nil
            statusText = "Hugging Face token cleared"
        } catch {
            statusText = "Hugging Face token clear failed"
        }
    }

    func validateHuggingFaceAccess() async {
        statusText = "Validating Hugging Face access..."
        do {
            let result = try await engineClient.validateHuggingFaceAccess(
                HuggingFaceTokenValidationRequest(
                    token: huggingFaceTokenForRequest(),
                    providerID: selectedTranslationModelProviderID()
                )
            )
            huggingFaceAuthStatus = result
            statusText = result.message
        } catch {
            huggingFaceAuthStatus = HuggingFaceAuthStatus(
                connected: false,
                source: "app-keychain",
                providerID: selectedTranslationModelProviderID(),
                accessGranted: false,
                message: error.localizedDescription
            )
            statusText = "Hugging Face validation failed"
        }
    }

    func openSelectedTranslationModelAgreement() {
        let providerID = selectedTranslationModelProviderID()
        let urlString = modelStatus(forProviderID: providerID)?.agreementURL
            ?? TranslationModelRecommendation(providerID: providerID).agreementURL
        guard let urlString, let url = URL(string: urlString) else {
            statusText = "No agreement URL for selected model"
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openHuggingFaceTokenSettings() {
        guard let url = URL(string: "https://huggingface.co/settings/tokens") else { return }
        NSWorkspace.shared.open(url)
    }

    func huggingFaceTokenForRequest() -> String {
        let draft = huggingFaceTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty {
            return draft
        }
        return huggingFaceTokenStore.load() ?? ""
    }

    func setTextLLMDefaultProvider(_ provider: TextLLMProviderKind) {
        guard preferences.textLLMDefaultProvider != provider else {
            return
        }

        preferences.setTextLLMDefaultProvider(provider)
        guard persistPreferences() else {
            return
        }

        statusText = "Default AI: \(provider.displayName)"
    }

    func setTextLLMConfiguration(_ configuration: TextLLMProviderConfiguration) {
        let normalized = configuration.normalized()
        guard preferences.textLLMConfiguration(for: normalized.provider) != normalized else {
            return
        }

        preferences.setTextLLMConfiguration(normalized)
        guard persistPreferences() else {
            return
        }

        statusText = "\(normalized.provider.displayName) settings updated"
    }

    func addTextLLMProvider(_ provider: TextLLMProviderKind) {
        var configuration = preferences.textLLMConfiguration(for: provider)
        configuration.enabled = true
        configuration.manuallyAdded = true
        if provider == .custom, configuration.customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configuration.customName = "Custom"
        }

        preferences.setTextLLMConfiguration(configuration)
        preferences.setTextLLMDefaultProvider(provider)
        guard persistPreferences() else {
            return
        }

        statusText = "\(provider.displayName) provider added"
    }

    func removeTextLLMProvider(_ provider: TextLLMProviderKind) {
        preferences.setTextLLMConfiguration(TextLLMProviderConfiguration(provider: provider, enabled: false))
        if preferences.textLLMDefaultProvider == provider {
            let replacement = preferences.textLLMProviders
                .first { $0.provider != provider && $0.isVisibleInSettings }?
                .provider
            preferences.setTextLLMDefaultProvider(replacement ?? .custom)
        }

        guard persistPreferences() else {
            return
        }

        textLLMModelOptions[provider] = nil
        textLLMModelDiscoveryStatus[provider] = nil
        textLLMOAuthStatus[provider] = nil
        statusText = "\(provider.displayName) provider removed"
    }

    func refreshTextLLMModels(_ provider: TextLLMProviderKind) async {
        let configuration = preferences.textLLMConfiguration(for: provider)
        let baseURL = configuration.resolvedBaseURL
        guard provider.requiresOAuth || !baseURL.isEmpty else {
            textLLMModelDiscoveryStatus[provider] = "\(provider.displayName) needs a base URL before model refresh."
            statusText = "\(provider.displayName) model refresh needs endpoint"
            return
        }

        if provider.requiresOAuth, configuration.trimmedOAuthAccessToken.isEmpty {
            textLLMModelDiscoveryStatus[provider] = "\(provider.displayName) needs auth before model refresh."
            statusText = "\(provider.displayName) model refresh needs auth"
            return
        }

        textLLMModelDiscoveryStatus[provider] = "Refreshing models..."
        statusText = "Refreshing \(provider.displayName) models"

        do {
            let response = try await engineClient.textLLMModels(
                TextLLMModelListRequest(
                    provider: provider.rawValue,
                    baseURL: baseURL,
                    apiKey: configuration.trimmedAPIKey,
                    transport: configuration.transport,
                    oauthAccessToken: configuration.trimmedOAuthAccessToken,
                    headers: configuration.resolvedHeaders
                )
            )
            textLLMModelOptions[provider] = response.models
            textLLMModelDiscoveryStatus[provider] = response.models.isEmpty
                ? "Provider returned no models."
                : "\(response.models.count) models loaded from provider."
            statusText = "\(provider.displayName) models refreshed"

            if configuration.trimmedModel.isEmpty, response.models.count == 1 {
                var updated = configuration
                updated.model = response.models[0]
                setTextLLMConfiguration(updated)
            }
        } catch {
            textLLMModelDiscoveryStatus[provider] = "Model refresh failed: \(error.localizedDescription)"
            statusText = "\(provider.displayName) model refresh failed"
        }
    }

    func authorizeTextLLMProvider(_ provider: TextLLMProviderKind) async {
        switch provider {
        case .githubCopilot:
            await startGitHubDeviceAuth()
        case .codex:
            authorizeCodexFromCLI()
        case .claude, .openRouter, .openAI, .custom:
            textLLMOAuthStatus[provider] = "\(provider.displayName) uses API key auth."
        }
    }

    private func startGitHubDeviceAuth() async {
        let provider = TextLLMProviderKind.githubCopilot
        let configuration = preferences.textLLMConfiguration(for: provider)
        let clientID = configuration.resolvedOAuthClientID
        guard !clientID.isEmpty else {
            textLLMOAuthStatus[provider] = "GitHub device auth is unavailable because no OAuth client is configured."
            statusText = "GitHub auth unavailable"
            return
        }

        do {
            textLLMOAuthStatus[provider] = "Requesting GitHub device code..."
            statusText = "Starting GitHub device auth"
            let deviceCode = try await requestGitHubDeviceCode(clientID: clientID)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(deviceCode.userCode, forType: .string)

            if let url = URL(string: deviceCode.verificationUriComplete ?? deviceCode.verificationUri) {
                NSWorkspace.shared.open(url)
            }

            textLLMOAuthStatus[provider] = "Code \(deviceCode.userCode) copied. GitHub device page opened; waiting for approval."
            statusText = "GitHub code: \(deviceCode.userCode)"
            try await pollGitHubDeviceAuth(clientID: clientID, deviceCode: deviceCode)
        } catch {
            textLLMOAuthStatus[provider] = "GitHub auth failed: \(error.localizedDescription)"
            statusText = "GitHub auth failed"
        }
    }

    private func requestGitHubDeviceCode(clientID: String) async throws -> GitHubDeviceCodeResponse {
        var request = URLRequest(url: Self.githubDeviceCodeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedBody([
            "client_id": clientID,
            "scope": Self.githubDeviceScope,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateOAuthResponse(response, data: data)
        return try EngineCoding.decoder.decode(GitHubDeviceCodeResponse.self, from: data)
    }

    private func pollGitHubDeviceAuth(clientID: String, deviceCode: GitHubDeviceCodeResponse) async throws {
        let provider = TextLLMProviderKind.githubCopilot
        let expiresAt = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        var interval = max(deviceCode.interval ?? 5, 5)

        while Date() < expiresAt {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            let tokenResponse = try await requestGitHubDeviceToken(clientID: clientID, deviceCode: deviceCode.deviceCode)

            if let accessToken = tokenResponse.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
               !accessToken.isEmpty {
                var configuration = preferences.textLLMConfiguration(for: provider)
                configuration.enabled = true
                configuration.oauthAccessToken = accessToken
                configuration.oauthRefreshToken = tokenResponse.refreshToken ?? ""
                setTextLLMConfiguration(configuration)
                textLLMOAuthStatus[provider] = "GitHub device auth connected."
                statusText = "GitHub auth connected"
                await refreshTextLLMModels(provider)
                return
            }

            switch tokenResponse.error {
            case "authorization_pending":
                textLLMOAuthStatus[provider] = "Waiting for GitHub approval with code \(deviceCode.userCode)."
            case "slow_down":
                interval += 5
                textLLMOAuthStatus[provider] = "GitHub asked us to slow down; still waiting."
            case "expired_token":
                throw OAuthFlowError.message("GitHub code expired. Start device sync again.")
            case "access_denied":
                throw OAuthFlowError.message("GitHub authorization was denied.")
            case let error?:
                throw OAuthFlowError.message(tokenResponse.errorDescription ?? error)
            case nil:
                textLLMOAuthStatus[provider] = "Waiting for GitHub approval with code \(deviceCode.userCode)."
            }
        }

        throw OAuthFlowError.message("GitHub code expired. Start device sync again.")
    }

    private func requestGitHubDeviceToken(clientID: String, deviceCode: String) async throws -> GitHubDeviceTokenResponse {
        var request = URLRequest(url: Self.githubDeviceTokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateOAuthResponse(response, data: data)
        return try EngineCoding.decoder.decode(GitHubDeviceTokenResponse.self, from: data)
    }

    private func authorizeCodexFromCLI() {
        let provider = TextLLMProviderKind.codex
        do {
            let authFile = try loadCodexCLIAuthFile()
            guard let tokens = authFile.usableTokens else {
                throw OAuthFlowError.message("No Codex CLI access token found.")
            }

            var configuration = preferences.textLLMConfiguration(for: provider)
            configuration.enabled = true
            configuration.oauthAccessToken = tokens.trimmedAccessToken
            configuration.oauthRefreshToken = tokens.trimmedRefreshToken
            setTextLLMConfiguration(configuration)

            let accountSuffix = tokens.accountId?.suffix(6).map(String.init).joined() ?? ""
            textLLMOAuthStatus[provider] = accountSuffix.isEmpty
                ? "Codex auth imported from ~/.codex/auth.json."
                : "Codex auth imported for account ending \(accountSuffix)."
            statusText = "Codex auth imported"
        } catch {
            textLLMOAuthStatus[provider] = "No Codex CLI token found. Sign in with Codex, then click Authorize again."
            statusText = "Codex auth needs sign-in"
            NSWorkspace.shared.open(Self.codexAuthHelpURL)
        }
    }

    private func loadCodexCLIAuthFile() throws -> CodexCLIAuthFile {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex")
            .appending(path: "auth.json")
        let data = try Data(contentsOf: url)
        return try EngineCoding.decoder.decode(CodexCLIAuthFile.self, from: data)
    }

    private func formURLEncodedBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { key, value in
            URLQueryItem(name: key, value: value)
        }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func validateOAuthResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw OAuthFlowError.message(detail?.isEmpty == false ? detail! : "OAuth request failed with HTTP \(http.statusCode).")
        }
    }

    func addMCPServer() {
        preferences.setMCPServer(MCPServerConfiguration())
        guard persistPreferences() else {
            return
        }
        statusText = "MCP server added"
    }

    func setMCPServer(_ server: MCPServerConfiguration) {
        preferences.setMCPServer(server)
        guard persistPreferences() else {
            return
        }
        statusText = "\(server.displayName) MCP settings updated"
    }

    func removeMCPServer(id: UUID) {
        preferences.removeMCPServer(id: id)
        guard persistPreferences() else {
            return
        }
        statusText = "MCP server removed"
    }

    func testTextLLMProvider(_ provider: TextLLMProviderKind) async {
        let configuration = preferences.textLLMConfiguration(for: provider)
        guard configuration.isConfigured else {
            lastTestResult = "\(provider.displayName) needs a base URL and model."
            statusText = "\(provider.displayName) not configured"
            return
        }

        do {
            let result = try await engineClient.aiHandoff(
                AIHandoffRequest(
                    prompt: "Reply with exactly: OmniVoice AI OK.",
                    provider: provider.rawValue,
                    baseURL: configuration.resolvedBaseURL,
                    model: configuration.trimmedModel,
                    apiKey: configuration.trimmedAPIKey,
                    transport: configuration.transport,
                    oauthAccessToken: configuration.trimmedOAuthAccessToken,
                    headers: configuration.resolvedHeaders
                )
            )
            lastTestResult = "\(provider.displayName): \(result.text)"
            statusText = "\(provider.displayName) test passed"
        } catch {
            lastTestResult = "\(provider.displayName) test failed: \(error.localizedDescription)"
            statusText = "\(provider.displayName) test failed"
        }
    }

    func setDictationHotkey(_ binding: HotkeyBinding) {
        guard binding != preferences.styleHotkey, binding != preferences.hotMenuHotkey else {
            statusText = "Hotkeys must be different"
            return
        }
        preferences.dictationHotkey = binding
        persistPreferences()
        onHotkeysChanged?(preferences)
        statusText = "Dictation hotkey: \(binding.displayName)"
    }

    func setStyleHotkey(_ binding: HotkeyBinding) {
        guard binding != preferences.dictationHotkey, binding != preferences.hotMenuHotkey else {
            statusText = "Hotkeys must be different"
            return
        }
        preferences.styleHotkey = binding
        persistPreferences()
        onHotkeysChanged?(preferences)
        statusText = "Style hotkey: \(binding.displayName)"
    }

    func setHotMenuHotkey(_ binding: HotkeyBinding) {
        guard binding != preferences.dictationHotkey, binding != preferences.styleHotkey else {
            statusText = "Hotkeys must be different"
            return
        }
        preferences.hotMenuHotkey = binding
        persistPreferences()
        onHotkeysChanged?(preferences)
        statusText = "Hot menu: \(binding.displayName)"
    }

    func setHotMenuAction(_ action: HotMenuAction, for direction: HotMenuDirection) {
        preferences.setHotMenuActions([action], for: direction)

        persistPreferences()
        statusText = "\(direction.displayName): \(action.displayName)"
    }

    func setHotMenuAction(_ action: HotMenuAction, for direction: HotMenuDirection, slot: Int) {
        guard slot >= 0, slot < HotMenuAction.visibleSlotCount else { return }

        var actions = preferences.hotMenuActions(for: direction)
        while actions.count < HotMenuAction.visibleSlotCount {
            actions.append(.none)
        }
        actions[slot] = action
        preferences.setHotMenuActions(actions, for: direction)

        persistPreferences()
        statusText = "\(direction.displayName) \(slot + 1): \(action.displayName)"
    }

    func setDictionaryTermsText(_ text: String) {
        preferences.dictionaryTerms = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        persistPreferences()
        statusText = "Dictionary updated"
    }

    func refreshEngineStatus() async {
        engineState = .checking
        await loadEngineStatus(startEngineIfOffline: true)
        await refreshStartupChecks()
    }

    func restartEngine() async {
        engineState = .checking
        statusText = "Restarting engine"

        let startResult = await EngineSupervisor.shared.restart()
        switch startResult {
        case .alreadyOnline, .started:
            await loadEngineStatus(startEngineIfOffline: false)
        case .stillStarting, .unavailable, .failed:
            providerStatuses = []
            modelStatuses = []
            diarizationProviderStatuses = []
            translationProviderStatuses = []
            transcripts = []
            engineState = .offline(startResult.detail)
            statusText = startResult.detail
        }
        await refreshStartupChecks()
    }

    func refreshStartupChecks() async {
        startupChecks = [
            StartupCheckItem(
                id: "preflight",
                title: "Startup preflight",
                detail: "Checking app, permissions, engine, and model state.",
                state: .checking,
                action: nil
            )
        ]

        async let launchServicesCount = Self.omniVoiceLaunchServicesRegistrationCount()
        async let localSigningIdentityCount = Self.omniVoiceSigningIdentityCount()

        let currentAppPath = Bundle.main.bundleURL.path
        let expectedAppPath = "\(NSHomeDirectory())/Applications/OmniVoice.app"
        let appPathState: StartupCheckState = currentAppPath == expectedAppPath ? .passed : .failed

        let registrationCount = await launchServicesCount
        let registrationState: StartupCheckState = registrationCount == 1 ? .passed : .failed

        let signingIdentityCount = await localSigningIdentityCount
        let signingState: StartupCheckState = signingIdentityCount == 1 ? .passed : .warning
        let signingDetail: String
        if signingIdentityCount == 1 {
            signingDetail = "One OmniVoice signing identity is visible."
        } else if signingIdentityCount == 0 {
            signingDetail = "No OmniVoice signing identity is visible to the user keychain search list."
        } else {
            signingDetail = "\(signingIdentityCount) OmniVoice signing identities are visible. The launcher will probe signing and fall back if Apple blocks one."
        }

        let selectedModel = modelStatus(for: preferences.asrProvider)
        let selectedProvider = providerInfo(for: preferences.asrProvider)
        let selectedDiarizationProvider = diarizationProviderInfo(for: preferences.conversationDiarizationProvider)
        let modelState: StartupCheckState
        let modelDetail: String
        if preferences.asrProvider == .fake {
            modelState = .warning
            modelDetail = "Fake ASR is selected for testing."
        } else if let selectedProvider, !selectedProvider.available {
            modelState = .failed
            modelDetail = selectedProvider.reason ?? "\(selectedProvider.label) is unavailable."
        } else if let selectedModel, selectedModel.installed {
            modelState = .passed
            modelDetail = "\(selectedModel.label) is installed."
        } else if let selectedModel {
            modelState = .failed
            modelDetail = "\(selectedModel.label) is missing: \(selectedModel.missingFiles.joined(separator: ", "))"
        } else {
            modelState = .warning
            modelDetail = "Model status has not loaded yet."
        }

        let diarizationState: StartupCheckState
        let diarizationDetail: String
        if !conversationDiarizationEnabled {
            diarizationState = .passed
            diarizationDetail = "Speaker diarization is off. Conversation transcription still uses Parakeet."
        } else if let selectedDiarizationProvider, selectedDiarizationProvider.available {
            diarizationState = .passed
            diarizationDetail = "\(selectedDiarizationProvider.label) is ready."
        } else if let selectedDiarizationProvider {
            diarizationState = .failed
            diarizationDetail = selectedDiarizationProvider.reason ?? "\(selectedDiarizationProvider.label) is unavailable."
        } else {
            diarizationState = .warning
            diarizationDetail = "Diarization provider status has not loaded yet."
        }

        startupChecks = [
            StartupCheckItem(
                id: "app-path",
                title: "Stable app path",
                detail: appPathState == .passed ? currentAppPath : "Running from \(currentAppPath); expected \(expectedAppPath).",
                state: appPathState,
                action: .refresh
            ),
            StartupCheckItem(
                id: "launch-services",
                title: "Apple app registry",
                detail: registrationCount == 1
                    ? "One OmniVoice registration is active."
                    : "\(registrationCount) OmniVoice registrations are active. Relaunch through the OmniVoice launcher to repair this.",
                state: registrationState,
                action: .refresh
            ),
            StartupCheckItem(
                id: "signing",
                title: "Signing identity",
                detail: signingDetail,
                state: signingState,
                action: .refresh
            ),
            StartupCheckItem(
                id: "accessibility",
                title: "Accessibility",
                detail: accessibilityTrusted
                    ? "Allowed for cursor detection and text insertion."
                    : "Required for cursor detection and final text insertion. If it still shows required after allowing it, reset the OmniVoice Accessibility record.",
                state: accessibilityTrusted ? .passed : .failed,
                action: accessibilityTrusted ? nil : .accessibility
            ),
            StartupCheckItem(
                id: "microphone",
                title: "Microphone",
                detail: microphoneAuthorized ? "Allowed for recording." : "Required for dictation.",
                state: microphoneAuthorized ? .passed : .failed,
                action: microphoneAuthorized ? nil : .microphone
            ),
            StartupCheckItem(
                id: "engine",
                title: "Engine",
                detail: engineState.detail,
                state: engineState == .online ? .passed : .failed,
                action: engineState == .online ? nil : .engine
            ),
            StartupCheckItem(
                id: "model",
                title: "Selected model",
                detail: modelDetail,
                state: modelState,
                action: modelState == .failed ? .model : nil
            ),
            StartupCheckItem(
                id: "diarization",
                title: "Speaker diarization",
                detail: diarizationDetail,
                state: diarizationState,
                action: diarizationState == .failed ? .diarizationModel : nil
            )
        ]
    }

    private func loadEngineStatus(startEngineIfOffline: Bool) async {
        do {
            _ = try await engineClient.health()
            providerStatuses = try await engineClient.providers()
            diarizationProviderStatuses = try await engineClient.diarizationProviders()
            translationProviderStatuses = try await engineClient.translationProviders()
            modelStatuses = try await engineClient.models()
            await refreshTranslationCapabilities()
            transcripts = (try? await engineClient.transcripts(limit: 100)) ?? transcripts
            engineState = .online
            statusText = "Engine online"
        } catch {
            if startEngineIfOffline {
                let startResult = await EngineSupervisor.shared.startIfNeeded()
                switch startResult {
                case .alreadyOnline, .started:
                    await loadEngineStatus(startEngineIfOffline: false)
                    return
                case .stillStarting, .unavailable, .failed:
                    providerStatuses = []
                    diarizationProviderStatuses = []
                    translationProviderStatuses = []
                    modelStatuses = []
                    transcripts = []
                    engineState = .offline(startResult.detail)
                    statusText = startResult.detail
                    return
                }
            }
            providerStatuses = []
            diarizationProviderStatuses = []
            translationProviderStatuses = []
            modelStatuses = []
            transcripts = []
            engineState = .offline(error.localizedDescription)
            statusText = "Engine offline"
        }
    }

    func refreshTranscripts() async {
        do {
            transcripts = try await engineClient.transcripts(limit: 100)
            statusText = "Conversation history refreshed"
        } catch {
            statusText = "Conversation history unavailable"
        }
    }

    func loadConversations() async {
        do {
            conversationSessions = try await engineClient.conversations(limit: 100)
        } catch {
            statusText = "Conversation history unavailable"
        }
    }

    func loadConversationDetail(_ session: ConversationSession) async {
        guard !isConversationRecording else {
            statusText = "Stop recording before opening saved conversations"
            return
        }

        do {
            selectedConversationDetail = try await engineClient.conversationDetail(sessionID: session.id)
            statusText = "Conversation loaded"
        } catch {
            statusText = "Conversation unavailable"
        }
    }

    func updateConversation(sessionID: String, request: ConversationDetailUpdateRequest) async {
        do {
            let detail = try await engineClient.updateConversation(sessionID: sessionID, request: request)
            selectedConversationDetail = detail
            if let index = conversationSessions.firstIndex(where: { $0.id == sessionID }) {
                conversationSessions[index] = detail.session
            }
            if preferences.automaticallyArchiveConversations {
                archiveConversation(detail)
            } else {
                statusText = "Conversation updated"
            }
        } catch {
            statusText = "Conversation update failed"
        }
    }

    func deleteConversation(_ session: ConversationSession) async {
        guard activeConversation?.id != session.id else {
            statusText = "Stop recording before deleting"
            return
        }

        do {
            try await engineClient.deleteConversation(sessionID: session.id)
            conversationSessions.removeAll { $0.id == session.id }
            if selectedConversationDetail?.session.id == session.id {
                selectedConversationDetail = nil
            }
            statusText = "Conversation deleted"
        } catch {
            statusText = "Conversation delete failed"
        }
    }

    func deleteConversations(sessionIDs: Set<String>) async {
        let requestedIDs = sessionIDs.filter { activeConversation?.id != $0 }
        guard !requestedIDs.isEmpty else {
            statusText = "No deletable conversations selected"
            return
        }

        var deletedIDs = Set<String>()
        var failedCount = 0
        for sessionID in requestedIDs {
            do {
                try await engineClient.deleteConversation(sessionID: sessionID)
                deletedIDs.insert(sessionID)
            } catch {
                failedCount += 1
            }
        }

        if !deletedIDs.isEmpty {
            conversationSessions.removeAll { deletedIDs.contains($0.id) }
            if let selectedConversationDetail, deletedIDs.contains(selectedConversationDetail.session.id) {
                self.selectedConversationDetail = nil
                if !isConversationRecording {
                    conversationSegments = []
                    conversationAssistCards = []
                }
            }
        }

        if failedCount == 0 {
            statusText = deletedIDs.count == 1 ? "Conversation deleted" : "\(deletedIDs.count) conversations deleted"
        } else if deletedIDs.isEmpty {
            statusText = "Conversation delete failed"
        } else {
            statusText = "\(deletedIDs.count) deleted, \(failedCount) failed"
        }
    }

    func clearConversationDatabase() async {
        guard !isConversationRecording, activeConversation == nil else {
            statusText = "Stop recording before clearing conversations"
            return
        }

        do {
            let sessions = try await engineClient.conversations(limit: 1000)
            guard !sessions.isEmpty else {
                conversationSessions = []
                selectedConversationDetail = nil
                conversationSegments = []
                conversationAssistCards = []
                statusText = "Conversation database already empty"
                return
            }

            var deletedCount = 0
            var failedCount = 0
            for session in sessions {
                do {
                    try await engineClient.deleteConversation(sessionID: session.id)
                    deletedCount += 1
                } catch {
                    failedCount += 1
                }
            }

            await loadConversations()
            if conversationSessions.isEmpty {
                selectedConversationDetail = nil
                conversationSegments = []
                conversationAssistCards = []
            }

            if failedCount == 0 {
                statusText = deletedCount == 1 ? "Conversation database cleared" : "\(deletedCount) conversations cleared"
            } else {
                statusText = "\(deletedCount) cleared, \(failedCount) failed"
            }
        } catch {
            statusText = "Conversation clear failed"
        }
    }

    func syncConversationArchiveToDatabase() async {
        guard !isConversationRecording else {
            statusText = "Stop recording before syncing conversations"
            return
        }

        let conversationsURL = conversationArchiveRootURL.appending(path: "Conversations", directoryHint: .isDirectory)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: conversationsURL.path(percentEncoded: false)) else {
            statusText = "No archived conversations found"
            return
        }

        do {
            let folderURLs = try fileManager.contentsOfDirectory(
                at: conversationsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var details: [ConversationDetail] = []
            var failedCount = 0
            for folderURL in folderURLs {
                guard (try? folderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                let transcriptURL = folderURL.appending(path: "transcript.json")
                guard fileManager.fileExists(atPath: transcriptURL.path(percentEncoded: false)) else {
                    continue
                }
                do {
                    let data = try Data(contentsOf: transcriptURL)
                    let detail = try EngineCoding.decoder.decode(ConversationDetail.self, from: data)
                    details.append(detail)
                } catch {
                    failedCount += 1
                }
            }

            guard !details.isEmpty else {
                statusText = failedCount == 0 ? "No archived conversations found" : "\(failedCount) archives could not be read"
                return
            }

            var createdCount = 0
            var updatedCount = 0
            for detail in details.sorted(by: { $0.session.startedAt < $1.session.startedAt }) {
                do {
                    let result = try await engineClient.importConversation(detail)
                    if result.status == "created" {
                        createdCount += 1
                    } else {
                        updatedCount += 1
                    }
                } catch {
                    failedCount += 1
                }
            }

            await loadConversations()
            var parts: [String] = []
            if createdCount > 0 {
                parts.append("\(createdCount) imported")
            }
            if updatedCount > 0 {
                parts.append("\(updatedCount) updated")
            }
            if failedCount > 0 {
                parts.append("\(failedCount) failed")
            }
            statusText = parts.isEmpty ? "Conversation archive already synced" : "Archive sync: \(parts.joined(separator: ", "))"
        } catch {
            statusText = "Archive sync failed"
        }
    }

    func createConversationSession(captureMode: ConversationCaptureMode = .microphoneOnly) async -> ConversationSession? {
        do {
            let session = try await engineClient.createConversation(
                ConversationSessionCreateRequest(
                    title: "Conversation",
                    captureMode: captureMode,
                    asrProvider: preferences.asrProvider.rawValue,
                    diarizationProvider: effectiveConversationDiarizationProviderID(),
                    externalProcessingEnabled: false
                )
            )
            activeConversation = session
            conversationSegments = []
            conversationAssistCards = []
            selectedConversationDetail = nil
            isConversationRecording = true
            isConversationFinalizing = false
            statusText = "Conversation recording"
            return session
        } catch {
            isConversationFinalizing = false
            statusText = "Conversation start failed"
            return nil
        }
    }

    func appendConversationSegment(_ request: ConversationSegmentCreateRequest) async {
        guard isConversationRecording, let activeConversation, activeConversation.isActive else { return }
        let sessionID = activeConversation.id

        if request.state == .live {
            updateLiveConversationSegment(request, sessionID: sessionID)
            requestLiveConversationDiarizationPreviewIfNeeded(request, sessionID: sessionID)
            return
        }

        do {
            let segment = try await engineClient.addConversationSegment(sessionID: sessionID, request: request)
            guard isConversationRecording, self.activeConversation?.id == sessionID else { return }
            removeLiveConversationSegment(sessionID: sessionID)
            conversationSegments.append(segment)
        } catch {
            statusText = "Conversation segment failed"
        }
    }

    func appendConversationAssistCard(_ request: ConversationAssistCardCreateRequest) async {
        guard isConversationRecording, let activeConversation, activeConversation.isActive else { return }
        let sessionID = activeConversation.id

        do {
            let card = try await engineClient.addConversationAssistCard(sessionID: sessionID, request: request)
            guard isConversationRecording, self.activeConversation?.id == sessionID else { return }
            conversationAssistCards.append(card)
        } catch {
            statusText = "Assist card failed"
        }
    }

    func generateConversationInsights() async {
        guard !isGeneratingConversationInsights else { return }
        guard let configuration = configuredConversationTextLLMConfiguration() else {
            statusText = "Configure a conversation AI provider first"
            return
        }
        guard let detail = await conversationDetailForInsightGeneration() else {
            statusText = "No conversation selected"
            return
        }
        guard detail.segments.contains(where: { $0.state != .live && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            statusText = "No transcript yet"
            return
        }

        isGeneratingConversationInsights = true
        statusText = "Generating insights"
        defer { isGeneratingConversationInsights = false }

        do {
            let result = try await engineClient.aiChat(
                AIChatRequest(
                    provider: configuration.provider.rawValue,
                    baseURL: configuration.resolvedBaseURL,
                    model: configuration.trimmedModel,
                    apiKey: configuration.trimmedAPIKey,
                    transport: configuration.transport,
                    oauthAccessToken: configuration.trimmedOAuthAccessToken,
                    headers: configuration.resolvedHeaders,
                    messages: [
                        AIChatMessage(role: .system, content: ConversationInsightSynthesis.systemPrompt),
                        AIChatMessage(role: .user, content: ConversationInsightSynthesis.userPrompt(for: detail)),
                    ],
                    attachments: [],
                    webSearchEnabled: conversationAIWebSearchEnabled
                )
            )

            let requests = nonDuplicateInsightRequests(
                ConversationInsightSynthesis.cardRequests(from: result.text),
                existingCards: detail.assistCards
            )
            guard !requests.isEmpty else {
                statusText = "No new insights"
                return
            }

            var cards: [ConversationAssistCard] = []
            for request in requests {
                let card = try await engineClient.addConversationAssistCard(sessionID: detail.session.id, request: request)
                cards.append(card)
            }
            mergeGeneratedConversationAssistCards(cards, sessionID: detail.session.id)
            statusText = cards.count == 1 ? "Generated 1 insight" : "Generated \(cards.count) insights"
        } catch {
            statusText = "Insight AI failed"
        }
    }

    func stopConversationSession() async {
        guard let activeConversation else {
            isConversationRecording = false
            isConversationFinalizing = false
            return
        }
        let sessionID = activeConversation.id

        do {
            let stopped = try await engineClient.stopConversation(sessionID: sessionID)
            guard self.activeConversation?.id == sessionID else { return }
            conversationSessions.insert(stopped, at: 0)
            self.activeConversation = nil
            isConversationRecording = false
            isConversationFinalizing = false
            await loadConversations()
            await loadAndArchiveStoppedConversation(sessionID: sessionID)
            disableConversationDiarizationWhenIdle()
        } catch {
            isConversationFinalizing = false
            statusText = "Conversation stop failed"
        }
    }

    func startConversationRecording() async {
        guard !isConversationStartInFlight, !isConversationRecording, !isConversationFinalizing, !conversationRecorder.recordingActive else {
            statusText = isConversationFinalizing ? "Conversation finalizing" : "Conversation already recording"
            return
        }
        isConversationStartInFlight = true
        deferredConversationAction = nil
        liveDiarizationPreviewGeneration = 0
        defer { isConversationStartInFlight = false }

        guard let session = await createConversationSession(captureMode: .microphoneOnly) else {
            return
        }

        if let deferredConversationAction {
            await completeDeferredConversationAction(deferredConversationAction, sessionID: session.id, recorderStarted: false)
            return
        }

        do {
            try await conversationRecorder.start(
                sessionID: session.id,
                provider: preferences.asrProvider,
                microphoneID: preferences.microphoneID,
                liveDiarizationEnabled: usesLiveConversationDiarizationStream,
                onSegment: { [weak self] request in
                    await self?.appendConversationSegment(request)
                },
                onAssistCard: { [weak self] request in
                    await self?.appendConversationAssistCard(request)
                }
            )
            if let deferredConversationAction {
                await completeDeferredConversationAction(deferredConversationAction, sessionID: session.id, recorderStarted: true)
                return
            }
            statusText = "Conversation recording"
        } catch {
            deferredConversationAction = nil
            _ = try? await engineClient.stopConversation(sessionID: session.id)
            activeConversation = nil
            isConversationRecording = false
            isConversationFinalizing = false
            selectedConversationDetail = nil
            conversationSegments = []
            conversationAssistCards = []
            statusText = error.localizedDescription
        }
    }

    func stopConversationRecording() async {
        guard !isConversationStartInFlight else {
            deferredConversationAction = .stop
            isConversationFinalizing = true
            statusText = "Stopping conversation"
            return
        }

        guard !isConversationStopInFlight else { return }
        isConversationStopInFlight = true
        isConversationFinalizing = true
        liveDiarizationPreviewGeneration += 1
        statusText = "Finalizing conversation"
        defer { isConversationStopInFlight = false }

        var recorderError: Error?
        do {
            try await conversationRecorder.stop()
        } catch {
            recorderError = error
        }

        await stopConversationSession()
        if let recorderError {
            statusText = "Conversation saved; recorder warning: \(recorderError.localizedDescription)"
        }
    }

    func cancelConversationRecording() {
        if isConversationStartInFlight {
            deferredConversationAction = .cancel
            isConversationFinalizing = false
            statusText = "Conversation cancelled"
            return
        }

        let sessionID = activeConversation?.id
        liveDiarizationPreviewGeneration += 1
        conversationRecorder.cancel()
        activeConversation = nil
        isConversationRecording = false
        isConversationFinalizing = false
        selectedConversationDetail = nil
        conversationSegments = []
        conversationAssistCards = []
        statusText = "Conversation cancelled"
        disableConversationDiarizationWhenIdle()

        if let sessionID {
            Task { [engineClient] in
                _ = try? await engineClient.stopConversation(sessionID: sessionID)
            }
        }
    }

    private func completeDeferredConversationAction(
        _ action: DeferredConversationAction,
        sessionID: String,
        recorderStarted: Bool
    ) async {
        deferredConversationAction = nil

        switch action {
        case .stop:
            isConversationFinalizing = true
            statusText = "Finalizing conversation"
            var recorderError: Error?
            if recorderStarted {
                do {
                    try await conversationRecorder.stop()
                } catch {
                    recorderError = error
                }
            }
            await stopConversationSession()
            if let recorderError {
                statusText = "Conversation saved; recorder warning: \(recorderError.localizedDescription)"
            }
        case .cancel:
            if recorderStarted {
                conversationRecorder.cancel()
            }
            _ = try? await engineClient.stopConversation(sessionID: sessionID)
            activeConversation = nil
            isConversationRecording = false
            isConversationFinalizing = false
            selectedConversationDetail = nil
            conversationSegments = []
            conversationAssistCards = []
            statusText = "Conversation cancelled"
            disableConversationDiarizationWhenIdle()
        }
    }

    private func updateLiveConversationSegment(_ request: ConversationSegmentCreateRequest, sessionID: String) {
        let liveID = liveConversationSegmentID(sessionID: sessionID)
        let existing = conversationSegments.first { $0.id == liveID }
        let speakerTurns = existing?.speakerTurns ?? []
        let liveWindow = ConversationLiveSegmentWindow.merge(
            existingStartMs: existing?.startMs,
            existingEndMs: existing?.endMs,
            incomingStartMs: request.startMs,
            incomingEndMs: request.endMs,
            speakerTurns: speakerTurns
        )
        let segment = ConversationSegment(
            id: liveID,
            sessionID: sessionID,
            speakerID: request.speakerID ?? existing?.speakerID ?? "pending-speaker",
            speakerDisplayName: request.speakerDisplayName ?? existing?.speakerDisplayName ?? "Identifying speaker",
            startMs: liveWindow.startMs,
            endMs: liveWindow.endMs,
            text: request.text,
            state: .live,
            confidence: request.confidence ?? existing?.confidence,
            speakerTurns: speakerTurns,
            speakerLines: existing?.speakerLines ?? []
        )

        if let index = conversationSegments.firstIndex(where: { $0.id == liveID }) {
            conversationSegments[index] = segment
        } else {
            conversationSegments.append(segment)
        }
    }

    private func requestLiveConversationDiarizationPreviewIfNeeded(
        _ request: ConversationSegmentCreateRequest,
        sessionID: String
    ) {
        guard usesLiveConversationDiarizationStream,
              request.audioPCMFloat32Base64 != nil,
              request.audioSampleRate != nil else {
            return
        }

        liveDiarizationPreviewGeneration += 1
        let generation = liveDiarizationPreviewGeneration
        Task { [weak self] in
            await self?.updateLiveConversationDiarizationPreview(
                request,
                sessionID: sessionID,
                generation: generation
            )
        }
    }

    private func updateLiveConversationDiarizationPreview(
        _ request: ConversationSegmentCreateRequest,
        sessionID: String,
        generation: Int
    ) async {
        do {
            let segment = try await engineClient.previewConversationSegment(sessionID: sessionID, request: request)
            guard liveDiarizationPreviewGeneration == generation,
                  isConversationRecording,
                  activeConversation?.id == sessionID else {
                return
            }

            let liveID = liveConversationSegmentID(sessionID: sessionID)
            if let index = conversationSegments.firstIndex(where: { $0.id == liveID }) {
                let current = conversationSegments[index]
                let speakerTurns = ConversationSpeakerTurnMerge.merge(
                    existing: current.speakerTurns,
                    preview: segment.speakerTurns,
                    replacingStartMs: request.audioStartMs,
                    replacingEndMs: request.endMs
                )
                let speakerLines = ConversationSpeakerLineMerge.merge(
                    existing: current.speakerLines,
                    preview: segment.speakerLines,
                    replacingStartMs: request.audioStartMs,
                    replacingEndMs: request.endMs
                )
                let liveWindow = ConversationLiveSegmentWindow.merge(
                    existingStartMs: current.startMs,
                    existingEndMs: current.endMs,
                    incomingStartMs: request.startMs,
                    incomingEndMs: request.endMs,
                    speakerTurns: speakerTurns
                )
                conversationSegments[index] = ConversationSegment(
                    id: liveID,
                    sessionID: sessionID,
                    speakerID: segment.speakerID,
                    speakerDisplayName: segment.speakerDisplayName,
                    startMs: liveWindow.startMs,
                    endMs: liveWindow.endMs,
                    text: current.text,
                    state: .live,
                    confidence: segment.confidence ?? current.confidence,
                    speakerTurns: speakerTurns,
                    speakerLines: speakerLines
                )
            }
        } catch {
            guard liveDiarizationPreviewGeneration == generation else {
                return
            }
            statusText = "Live diarization skipped"
        }
    }

    private func removeLiveConversationSegment(sessionID: String) {
        let liveID = liveConversationSegmentID(sessionID: sessionID)
        conversationSegments.removeAll { $0.id == liveID }
    }

    private func conversationDetailForInsightGeneration() async -> ConversationDetail? {
        if let activeConversation {
            return ConversationDetail(
                session: activeConversation,
                segments: conversationSegments.filter { $0.state != .live },
                assistCards: conversationAssistCards
            )
        }

        if let selectedConversationDetail {
            return selectedConversationDetail
        }

        guard let session = conversationSessions.first else {
            return nil
        }

        do {
            let detail = try await engineClient.conversationDetail(sessionID: session.id)
            selectedConversationDetail = detail
            return detail
        } catch {
            statusText = "Conversation unavailable"
            return nil
        }
    }

    private func conversationDetailForAIChat() async -> ConversationDetail? {
        if let activeConversation {
            return ConversationDetail(
                session: activeConversation,
                segments: conversationSegments,
                assistCards: conversationAssistCards
            )
        }

        if let selectedConversationDetail {
            return selectedConversationDetail
        }

        guard let session = conversationSessions.first else {
            return nil
        }

        do {
            let detail = try await engineClient.conversationDetail(sessionID: session.id)
            selectedConversationDetail = detail
            return detail
        } catch {
            statusText = "Conversation unavailable"
            return nil
        }
    }

    private func nonDuplicateInsightRequests(
        _ requests: [ConversationAssistCardCreateRequest],
        existingCards: [ConversationAssistCard]
    ) -> [ConversationAssistCardCreateRequest] {
        var seen = Set(existingCards.map { insightKey(kind: $0.kind, title: $0.title, body: $0.body) })
        var unique: [ConversationAssistCardCreateRequest] = []

        for request in requests {
            let key = insightKey(kind: request.kind, title: request.title, body: request.body)
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            unique.append(request)
        }

        return unique
    }

    private func insightKey(kind: ConversationAssistCardKind, title: String, body: String) -> String {
        [
            kind.rawValue,
            title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        ].joined(separator: "|")
    }

    private func mergeGeneratedConversationAssistCards(_ cards: [ConversationAssistCard], sessionID: String) {
        guard !cards.isEmpty else { return }

        if activeConversation?.id == sessionID {
            conversationAssistCards.append(contentsOf: cards)
        }

        if let detail = selectedConversationDetail, detail.session.id == sessionID {
            selectedConversationDetail = ConversationDetail(
                session: detail.session,
                segments: detail.segments,
                assistCards: detail.assistCards + cards
            )
        }
    }

    func archiveConversation(_ detail: ConversationDetail, revealInFinder: Bool = false) {
        do {
            let folder = try ConversationArchive.write(detail, rootURL: conversationArchiveRootURL)
            if revealInFinder {
                revealArchiveFolder(folder)
                statusText = "Conversation exported and revealed: \(folder.lastPathComponent)"
            } else {
                statusText = "Conversation archived: \(folder.lastPathComponent)"
            }
        } catch {
            statusText = "Conversation archive failed: \(error.localizedDescription)"
        }
    }

    private func revealArchiveFolder(_ folder: URL) {
        let didSelect = NSWorkspace.shared.selectFile(
            folder.path(percentEncoded: false),
            inFileViewerRootedAtPath: conversationArchiveRootURL.path(percentEncoded: false)
        )

        if !didSelect {
            NSWorkspace.shared.open(folder)
        }
    }

    var conversationArchiveRootURL: URL {
        let path = preferences.conversationArchiveFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            return ConversationArchive.defaultRootURL()
        }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    private func loadAndArchiveStoppedConversation(sessionID: String) async {
        do {
            let detail = try await engineClient.conversationDetail(sessionID: sessionID)
            selectedConversationDetail = detail
            if preferences.automaticallyArchiveConversations {
                archiveConversation(detail)
            } else {
                statusText = "Conversation saved"
            }
        } catch {
            statusText = "Conversation saved; archive unavailable"
        }
    }

    private func liveConversationSegmentID(sessionID: String) -> String {
        "live-\(sessionID)"
    }

    func refreshModelStatus() async {
        do {
            modelStatuses = try await engineClient.models()
        } catch {
            statusText = "Model status refresh failed"
        }
    }

    func refreshProviderAndModelStatus() async {
        do {
            providerStatuses = try await engineClient.providers()
            diarizationProviderStatuses = try await engineClient.diarizationProviders()
            translationProviderStatuses = try await engineClient.translationProviders()
            modelStatuses = try await engineClient.models()
            await refreshTranslationCapabilities()
        } catch {
            statusText = "Provider status refresh failed"
        }
    }

    func refreshTranslationCapabilities() async {
        do {
            let capabilities = try await engineClient.translationCapabilities(
                providerID: preferences.translationProvider.rawValue,
                modelProviderID: selectedTranslationModelProviderID(),
                modelPath: effectiveTranslationModelPath()
            )
            translationCapabilities = capabilities
            reconcileTranslationLanguages(with: capabilities)
        } catch {
            translationCapabilities = nil
            statusText = "Translation languages unavailable"
        }
    }

    func refreshMicrophones() {
        microphoneDevices = MicrophoneDeviceService.inputDevices()
        if let microphoneID = preferences.microphoneID,
           !microphoneDevices.contains(where: { $0.id == microphoneID }) {
            statusText = "Selected microphone is not connected"
        } else {
            statusText = "Microphones refreshed"
        }
    }

    func checkSelectedModelUpdate() async {
        guard preferences.asrProvider != .fake else {
            statusText = "Fake ASR has no model download"
            return
        }

        do {
            let update = try await engineClient.checkModelUpdate(provider: preferences.asrProvider)
            modelUpdateInfo = update
            statusText = update.updateAvailable ? "Model update available" : "Model is current"
        } catch {
            statusText = "Model update check failed"
        }
    }

    func checkSelectedDiarizationModelUpdate() async {
        let providerID = preferences.conversationDiarizationProvider
        guard conversationDiarizationEnabled else {
            statusText = "Turn on speaker diarization first"
            return
        }

        do {
            let update = try await engineClient.checkModelUpdate(providerID: providerID)
            modelUpdateInfo = update
            statusText = update.updateAvailable ? "Diarization model update available" : "Diarization model is current"
        } catch {
            statusText = "Diarization update check failed"
        }
    }

    func checkSelectedTranslationModelUpdate() async {
        let providerID = selectedTranslationModelProviderID()

        do {
            let update = try await engineClient.checkModelUpdate(providerID: providerID, huggingFaceToken: huggingFaceTokenForRequest())
            modelUpdateInfo = update
            statusText = update.updateAvailable ? "Translation model update available" : "Translation model is current"
        } catch {
            statusText = "Translation update check failed"
        }
    }

    func downloadSelectedModel() async {
        guard preferences.asrProvider != .fake else {
            statusText = "Fake ASR has no model download"
            return
        }

        do {
            let download = try await engineClient.downloadModel(provider: preferences.asrProvider)
            modelDownloadStatus = download
            statusText = download.message ?? "Model download queued"
            await pollModelDownload(provider: preferences.asrProvider)
        } catch {
            statusText = "Model download failed"
        }
    }

    func downloadSelectedDiarizationModel() async {
        let providerID = preferences.conversationDiarizationProvider
        guard conversationDiarizationEnabled else {
            statusText = "Turn on speaker diarization first"
            return
        }

        do {
            let download = try await engineClient.downloadModel(providerID: providerID)
            modelDownloadStatus = download
            statusText = download.message ?? "Diarization model download queued"
            await pollModelDownload(providerID: providerID)
            await refreshProviderAndModelStatus()
        } catch {
            statusText = "Diarization model download failed"
        }
    }

    func downloadSelectedTranslationModel() async {
        let providerID = selectedTranslationModelProviderID()
        if preferences.translationProvider != .translateGemmaMLX {
            preferences.translationProvider = .translateGemmaMLX
            _ = persistPreferences()
        }

        do {
            let download = try await engineClient.downloadModel(providerID: providerID, huggingFaceToken: huggingFaceTokenForRequest())
            modelDownloadStatus = download
            statusText = download.message ?? "Translation model download queued"
            await pollModelDownload(providerID: providerID)
            await refreshProviderAndModelStatus()
        } catch {
            statusText = "Translation model download failed"
        }
    }

    func runCleanupTest() async {
        lastTestResult = "Running..."
        do {
            let result = try await engineClient.cleanup(
                CleanupRequest(
                    rawTranscript: "I am going to the store. No wait, I am going to the house.",
                    style: preferences.style,
                    dictionaryTerms: preferences.dictionaryTerms
                )
            )
            lastTestResult = result.text
            statusText = "Cleanup test passed"
        } catch {
            lastTestResult = error.localizedDescription
            statusText = "Cleanup test failed"
        }
    }

    func runTranslationTest() async {
        lastTestResult = "Translating..."
        if preferences.translationProvider != .fake,
           let status = modelStatus(forProviderID: selectedTranslationModelProviderID()),
           !status.installed,
           preferences.customTranslationModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let message = "Download \(translationModelLabel(for: selectedTranslationModelProviderID())) before testing translation, or choose a local model folder."
            lastTestResult = message
            statusText = message
            return
        }

        do {
            let result = try await engineClient.translate(
                TranslationRequest(
                    text: "Hello, thank you for coming.",
                    provider: preferences.translationProvider,
                    sourceLanguage: preferences.translationSourceLanguage,
                    targetLanguage: preferences.translationTargetLanguage,
                    modelPath: effectiveTranslationModelPath()
                )
            )
            lastTestResult = result.text
            statusText = "Translation test passed"
        } catch {
            lastTestResult = error.localizedDescription
            statusText = "Translation test failed"
        }
    }

    func runTranslationLanguageValidation() async {
        lastTestResult = "Validating translation languages..."
        if preferences.translationProvider != .fake,
           let status = modelStatus(forProviderID: selectedTranslationModelProviderID()),
           !status.installed,
           preferences.customTranslationModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let message = "Download \(translationModelLabel(for: selectedTranslationModelProviderID())) before validating languages, or choose a local model folder."
            lastTestResult = message
            statusText = message
            return
        }

        do {
            let report = try await engineClient.validateTranslations(
                TranslationValidationRequest(
                    text: "Hello, thank you for coming.",
                    provider: preferences.translationProvider,
                    sourceLanguage: preferences.translationSourceLanguage == "auto" ? "en" : preferences.translationSourceLanguage,
                    modelPath: effectiveTranslationModelPath()
                )
            )
            lastTestResult = translationValidationSummary(report)
            statusText = report.failed == 0 ? "Language validation passed" : "Language validation found issues"
        } catch {
            lastTestResult = error.localizedDescription
            statusText = "Language validation failed"
        }
    }

    func providerInfo(for provider: ASRProviderKind) -> EngineProviderInfo? {
        providerStatuses.first { $0.id == provider.rawValue }
    }

    func diarizationProviderInfo(for providerID: String) -> EngineProviderInfo? {
        diarizationProviderStatuses.first { $0.id == providerID }
    }

    func translationProviderInfo(for provider: TranslationProviderKind) -> TranslationProviderInfo? {
        translationProviderStatuses.first { $0.id == provider.rawValue }
    }

    func modelStatus(for provider: ASRProviderKind) -> EngineModelStatus? {
        modelStatuses.first { $0.providerID == provider.rawValue }
    }

    func modelStatus(forProviderID providerID: String) -> EngineModelStatus? {
        modelStatuses.first { $0.providerID == providerID }
    }

    func diarizationLabel(for providerID: String) -> String {
        diarizationProviderInfo(for: providerID)?.label
            ?? modelStatus(forProviderID: providerID)?.label
            ?? providerID
    }

    var conversationDiarizationEnabled: Bool {
        DiarizationProviderResolution.isEnabledProviderID(preferences.conversationDiarizationProvider)
    }

    var usesLiveConversationDiarizationStream: Bool {
        DiarizationProviderResolution.usesLiveConversationStream(
            preferred: preferences.conversationDiarizationProvider,
            knownProvider: diarizationProviderInfo(for: preferences.conversationDiarizationProvider)
        )
    }

    var conversationDiarizationPrecision: DiarizationPrecision {
        preferences.conversationDiarizationPrecision
    }

    func effectiveConversationDiarizationProviderID() -> String {
        DiarizationProviderResolution.effectiveProviderID(
            preferred: preferences.conversationDiarizationProvider,
            knownProvider: diarizationProviderInfo(for: preferences.conversationDiarizationProvider)
        )
    }

    var selectedDiarizationProviderIssue: ProviderRecoveryIssue? {
        let providerID = preferences.conversationDiarizationProvider
        guard conversationDiarizationEnabled else {
            return nil
        }

        if let info = diarizationProviderInfo(for: providerID), !info.available {
            return ProviderRecoveryIssue(
                title: "\(info.label) unavailable",
                detail: info.reason ?? "The selected diarization provider is unavailable."
            )
        }

        if let status = modelStatus(forProviderID: providerID), !status.installed, !status.missingFiles.isEmpty {
            return ProviderRecoveryIssue(
                title: "\(status.label) model missing",
                detail: "Missing files: \(status.missingFiles.joined(separator: ", "))"
            )
        }

        return nil
    }

    var selectedProviderIssue: ProviderRecoveryIssue? {
        providerIssue(for: preferences.asrProvider)
    }

    func providerIssue(for provider: ASRProviderKind) -> ProviderRecoveryIssue? {
        if let info = providerInfo(for: provider), !info.available {
            return ProviderRecoveryIssue(
                title: "\(info.label) unavailable",
                detail: info.reason ?? "The selected speech model is not available."
            )
        }

        if let status = modelStatus(for: provider), !status.installed, !status.missingFiles.isEmpty {
            return ProviderRecoveryIssue(
                title: "\(status.label) model missing",
                detail: "Missing files: \(status.missingFiles.joined(separator: ", "))"
            )
        }

        return nil
    }

    func transcriptionFailureMessage(for error: Error) -> String {
        if let issue = selectedProviderIssue {
            return "\(issue.title): \(issue.detail)"
        }

        if case let EngineClient.EngineError.badStatus(statusCode, detail) = error {
            let reason = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !reason.isEmpty {
                return "Engine returned \(statusCode): \(reason)"
            }
            return "Engine returned \(statusCode)"
        }

        return error.localizedDescription
    }

    func label(for provider: ASRProviderKind) -> String {
        providerInfo(for: provider)?.label ?? provider.rawValue
    }

    func microphoneLabel(for microphoneID: String?) -> String {
        guard let microphoneID else {
            return "System Default"
        }

        return microphoneDevices.first { $0.id == microphoneID }?.displayName ?? "Missing: \(microphoneID)"
    }

    private func pollModelDownload(provider: ASRProviderKind) async {
        await pollModelDownload(providerID: provider.rawValue)
    }

    private func pollModelDownload(providerID: String) async {
        for _ in 0..<300 {
            do {
                let current = try await engineClient.modelDownloadStatus(providerID: providerID)
                modelDownloadStatus = current
                statusText = current.message ?? "Model \(current.state)"
                if current.state == "completed" || current.state == "failed" {
                    modelStatuses = try await engineClient.models()
                    if providerID == selectedTranslationModelProviderID() {
                        await refreshTranslationCapabilities()
                    }
                    return
                }
            } catch {
                statusText = "Model download status failed"
                return
            }

            try? await Task.sleep(for: .seconds(2))
        }
    }

    @discardableResult
    private func persistPreferences() -> Bool {
        do {
            try preferencesStore.save(preferences)
            return true
        } catch {
            statusText = "Preferences save failed"
            return false
        }
    }

    private func notifyThemeChanged() {
        onThemeChanged?(activeTheme, preferences.appearanceMode)
    }

    private func normalizedLanguageCode(_ language: String, fallback: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func quickTranslationTargetLanguagesForCurrentModel() -> [String] {
        let supportedCodes = Set(translationTargetLanguageOptions.map(\.code))
        let supportedQuickTargets = preferences.normalizedTranslationQuickTargetLanguages()
            .filter { supportedCodes.contains($0) }

        if !supportedQuickTargets.isEmpty {
            return supportedQuickTargets
        }

        return Array(translationTargetLanguageOptions.map(\.code).prefix(OmniVoicePreferences.translationQuickTargetLanguageSlotCount))
    }

    private func reconcileTranslationLanguages(with capabilities: TranslationCapabilities) {
        var changed = false

        if capabilities.sourceLanguageLocked,
           let source = capabilities.sourceLanguages.first(where: \.isDefault) ?? capabilities.sourceLanguages.first,
           preferences.translationSourceLanguage != source.code {
            preferences.translationSourceLanguage = source.code
            changed = true
        }

        let targetCodes = Set(capabilities.targetLanguages.map(\.code))
        if !targetCodes.contains(preferences.translationTargetLanguage),
           let target = capabilities.targetLanguages.first(where: { $0.code == "es" })
            ?? capabilities.targetLanguages.first(where: \.isDefault)
            ?? capabilities.targetLanguages.first {
            preferences.translationTargetLanguage = target.code
            changed = true
        }

        let reconciledQuickTargets = reconciledQuickTranslationTargets(
            preferences.translationQuickTargetLanguages,
            supportedTargets: capabilities.targetLanguages
        )
        if preferences.translationQuickTargetLanguages != reconciledQuickTargets {
            preferences.translationQuickTargetLanguages = reconciledQuickTargets
            changed = true
        }

        if changed {
            _ = persistPreferences()
        }
    }

    private func reconciledQuickTranslationTargets(
        _ languages: [String],
        supportedTargets: [TranslationLanguageOption]
    ) -> [String] {
        let supportedCodes = Set(supportedTargets.map(\.code))
        guard !supportedCodes.isEmpty else {
            return OmniVoicePreferences.normalizedTranslationQuickTargetLanguages(languages)
        }

        var reconciled = OmniVoicePreferences.normalizedTranslationQuickTargetLanguages(languages)
            .filter { supportedCodes.contains($0) }

        for language in OmniVoicePreferences.defaultTranslationQuickTargetLanguages where supportedCodes.contains(language) && !reconciled.contains(language) {
            reconciled.append(language)
            if reconciled.count == OmniVoicePreferences.translationQuickTargetLanguageSlotCount {
                return reconciled
            }
        }

        for language in supportedTargets.map(\.code) where !reconciled.contains(language) {
            reconciled.append(language)
            if reconciled.count == OmniVoicePreferences.translationQuickTargetLanguageSlotCount {
                return reconciled
            }
        }

        return reconciled.isEmpty ? OmniVoicePreferences.defaultTranslationQuickTargetLanguages : reconciled
    }

    private func translationValidationSummary(_ report: TranslationValidationResponse) -> String {
        let header = "Validated \(report.tested) languages: \(report.passed) pass, \(report.review) review, \(report.failed) fail."
        let context = "Provider: \(report.provider.displayName) • Source: \(report.sourceLanguage) • Capabilities: \(report.capabilitySource)"
        let failures = report.items.filter { $0.status == "fail" }
        let reviews = report.items.filter { $0.status == "review" }
        let categoryLines = translationValidationCategoryLines(report.items)
        let failureLines = failures
            .prefix(30)
            .map(translationValidationIssueLine)
        let reviewLines = reviews
            .prefix(20)
            .map(translationValidationIssueLine)

        var lines = [header, context]
        if !categoryLines.isEmpty {
            lines.append("Buckets: \(categoryLines.joined(separator: ", "))")
        }

        if !failureLines.isEmpty {
            lines.append("")
            lines.append("Failures")
            lines.append(contentsOf: failureLines)
            if failures.count > failureLines.count {
                lines.append("... \(failures.count - failureLines.count) more failures")
            }
        }

        if !reviewLines.isEmpty {
            lines.append("")
            lines.append("Needs review")
            lines.append(contentsOf: reviewLines)
            if reviews.count > reviewLines.count {
                lines.append("... \(reviews.count - reviewLines.count) more review items")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func translationValidationCategoryLines(_ items: [TranslationValidationItem]) -> [String] {
        let grouped = Dictionary(grouping: items.filter { $0.status != "pass" }) { item in
            item.failureCategory?.nilIfEmpty ?? item.status
        }
        return grouped
            .map { key, value in "\(key): \(value.count)" }
            .sorted()
    }

    private func translationValidationIssueLine(_ item: TranslationValidationItem) -> String {
        let note = item.notes.first ?? "Review output manually."
        let expected = item.expectedScripts.isEmpty ? "any script" : item.expectedScripts.joined(separator: "/")
        let dominant = item.dominantScript?.nilIfEmpty ?? "none"
        let ratio = item.expectedScriptRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a"
        let preview = translationValidationPreview(for: item)
        return "\(item.status.uppercased()) \(item.code) \(item.name) [expected \(expected), got \(dominant), match \(ratio)]: \(note) Output: \"\(preview)\""
    }

    private func translationValidationPreview(for item: TranslationValidationItem) -> String {
        let preview = item.outputPreview?.nilIfEmpty ?? item.text.nilIfEmpty ?? "<empty>"
        if preview.count <= 96 {
            return preview
        }
        return "\(preview.prefix(95))…"
    }

    private static func omniVoiceLaunchServicesRegistrationCount() async -> Int {
        guard let output = await commandOutput(
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            arguments: ["-dump"]
        ) else {
            return 0
        }

        return output.components(separatedBy: "identifier:                 com.omnivoice.OmniVoiceApp").count - 1
    }

    private static func omniVoiceSigningIdentityCount() async -> Int {
        guard let output = await commandOutput("/usr/bin/security", arguments: ["find-identity", "-v", "-p", "codesigning"]) else {
            return 0
        }

        return output
            .split(separator: "\n")
            .filter { $0.contains("\"OmniVoice Local Development\"") }
            .count
    }

    private static func commandOutput(_ executable: String, arguments: [String]) async -> String? {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        }.value
    }
}
