import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OmniVoiceCore

struct EditorWindowView: View {
    @Bindable var model: AppModel

    private static let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        NavigationSplitView {
            editorSidebar
        } detail: {
            editorDetailContent
        }
        .navigationTitle(model.editorWorkspaceMode == .documents ? "Editor" : "Editor Notes")
        .toolbar {
            if model.editorWorkspaceMode == .documents {
                documentToolbarItems
            } else {
                notesToolbarItems
            }
        }
        .themeWindowBackground(model.activeTheme)
        .frame(minWidth: 980, minHeight: 680)
    }

    private var editorSidebar: some View {
        VStack(spacing: 0) {
            Picker("Editor Area", selection: $model.editorWorkspaceMode) {
                ForEach(EditorWorkspaceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            .help("Switch between full documents and subject-based notes")

            Divider()

            switch model.editorWorkspaceMode {
            case .documents:
                documentsSidebar
            case .notes:
                notesSidebar
            }
        }
        .frame(minWidth: 260)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .themeWindowBackground(model.activeTheme)
    }

    private var documentsSidebar: some View {
        List(selection: selectedDocumentBinding) {
            ForEach(model.editorDocuments) { document in
                VStack(alignment: .leading, spacing: 3) {
                    Text(document.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(document.updatedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(document.id)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button {
                model.createEditorDocument()
            } label: {
                Label("New Document", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .help("Create a new Markdown/DOCX editor document")
        }
    }

    private var notesSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Subjects", systemImage: "folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.createTranscriptionSubject()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Create a new subject group")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: selectedSubjectBinding) {
                ForEach(model.transcriptionSubjects) { subject in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(subject.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(subject.notes.count) notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(subject.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 180)

            Divider()

            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.createTranscriptionNote()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("Create a quick note in the selected subject")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: selectedNoteBinding) {
                ForEach(model.selectedTranscriptionSubject?.notes ?? []) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(note.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .tag(note.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var editorDetailContent: some View {
        switch model.editorWorkspaceMode {
        case .documents:
            if let document = model.selectedEditorDocument {
                editorDetail(document)
            } else {
                ContentUnavailableView("No Document", systemImage: "doc.text", description: Text("Create a document or draft one from Notes."))
                    .themeWindowBackground(model.activeTheme)
            }
        case .notes:
            notesDetail
        }
    }

    @ToolbarContentBuilder
    private var documentToolbarItems: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.createEditorDocument()
            } label: {
                Label("New", systemImage: "plus")
            }
            .help("Create a new editor document")

            Button {
                Task {
                    await model.improveSelectedEditorDocumentWithAI()
                }
            } label: {
                Label("AI Edit", systemImage: "sparkles")
            }
            .help("Use the configured AI provider to improve the current document")

            Button {
                model.addSelectedEditorDocumentToAskAI()
            } label: {
                Label("Ask AI", systemImage: "bubble.left.and.sparkles")
            }
            .help("Attach the current document to Ask AI")

            Button {
                model.exportSelectedEditorDocumentMarkdown()
            } label: {
                Label("Markdown", systemImage: "doc.plaintext")
            }
            .help("Export the current document as Markdown")

            Button {
                model.exportSelectedEditorDocumentDocx()
            } label: {
                Label("DOCX", systemImage: "doc.richtext")
            }
            .help("Export the current document as a Word DOCX file")
        }
    }

    @ToolbarContentBuilder
    private var notesToolbarItems: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.createTranscriptionNote()
            } label: {
                Label("Note", systemImage: "plus")
            }
            .help("Create a new note in the selected subject")

            Button {
                Task {
                    await model.cleanupSelectedTranscriptionNote()
                }
            } label: {
                Label("Grammar", systemImage: "checkmark.seal")
            }
            .help("Clean spelling and grammar in the selected note")

            Button {
                appendLatestDictationToSelectedNote()
            } label: {
                Label("Last Dictation", systemImage: "text.badge.plus")
            }
            .help("Append the most recent dictation transcript to this note")

            Button {
                model.addSelectedSubjectToAskAI()
            } label: {
                Label("Ask AI", systemImage: "bubble.left.and.sparkles")
            }
            .help("Attach the selected subject to Ask AI")

            Button {
                model.sendSelectedSubjectToEditor()
            } label: {
                Label("Draft Document", systemImage: "arrow.up.doc")
            }
            .help("Create an editor document using this subject and its notes as context")
        }
    }

    private func editorDetail(_ document: EditorDocument) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(
                        "Title",
                        text: Binding(
                            get: { document.title },
                            set: { model.updateSelectedEditorDocument(title: $0) }
                        )
                    )
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .help("Document title")

                    HStack {
                        Picker("Font", selection: Binding(
                            get: { document.style.fontName },
                            set: { model.updateSelectedEditorDocument(style: EditorDocumentStyle(fontName: $0, fontSize: document.style.fontSize)) }
                        )) {
                            ForEach(Self.fontFamilies, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .frame(maxWidth: 280)
                        .help("Choose the editor font")

                        Stepper(
                            "Size \(Int(document.style.fontSize))",
                            value: Binding(
                                get: { document.style.fontSize },
                                set: { model.updateSelectedEditorDocument(style: EditorDocumentStyle(fontName: document.style.fontName, fontSize: $0)) }
                            ),
                            in: 9...36,
                            step: 1
                        )
                        .help("Adjust the editor font size")

                        Spacer()

                        Text(document.sourceSubjectID == nil ? "Standalone" : "Subject context attached")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Shows whether this document was created from subject note context")
                    }
                }
                .padding()

                Divider()

                TextEditor(
                    text: Binding(
                        get: { document.bodyMarkdown },
                        set: { model.updateSelectedEditorDocument(bodyMarkdown: $0) }
                    )
                )
                .font(.custom(document.style.fontName, size: document.style.fontSize))
                .scrollContentBackground(.hidden)
                .padding()
                .help("Edit the Markdown body of the document")
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            .themeSurface(model.activeTheme, cornerRadius: 12, strong: false, interactive: false)

            InlineAskAIPanel(
                model: model,
                title: "Editor AI",
                subtitle: "Ask AI about this document or use it as writing context."
            ) {
                Button {
                    model.addSelectedEditorDocumentToAskAI()
                } label: {
                    Label("Attach Document", systemImage: "doc.text")
                }
                .help("Add the current document and its source context to Ask AI")

                Button {
                    Task {
                        await model.improveSelectedEditorDocumentWithAI()
                    }
                } label: {
                    Label("Improve Document", systemImage: "sparkles")
                }
                .help("Rewrite the current document for spelling, grammar, clarity, and formatting")
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420, maxHeight: .infinity)
            .onAppear {
                model.prepareAskAIForSelectedEditorDocument()
            }
            .onChange(of: document.id) { _, _ in
                model.prepareAskAIForSelectedEditorDocument()
            }
        }
        .padding(12)
        .themeWindowBackground(model.activeTheme)
    }

    @ViewBuilder
    private var notesDetail: some View {
        if let subject = model.selectedTranscriptionSubject {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(
                            "Subject",
                            text: Binding(
                                get: { subject.title },
                                set: { model.updateSelectedSubjectTitle($0) }
                            )
                        )
                        .font(.title2.bold())
                        .textFieldStyle(.plain)
                        .help("Subject name for this group of transcription notes")

                        Text("Notes are saved inside OmniSpeak as Markdown-ready context for documents and AI.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()

                    Divider()

                    if let note = model.selectedTranscriptionNote {
                        VStack(spacing: 10) {
                            TextField(
                                "Note title",
                                text: Binding(
                                    get: { note.title },
                                    set: { model.updateSelectedTranscriptionNote(title: $0) }
                                )
                            )
                            .font(.headline)
                            .textFieldStyle(.plain)
                            .help("Title for the selected transcription note")

                            TextEditor(
                                text: Binding(
                                    get: { note.body },
                                    set: { model.updateSelectedTranscriptionNote(body: $0) }
                                )
                            )
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .help("Edit the selected transcription note")
                        }
                        .padding()
                    } else {
                        ContentUnavailableView("No Note", systemImage: "note.text", description: Text("Create a note to start capturing thoughts."))
                    }
                }
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .themeSurface(model.activeTheme, cornerRadius: 12, strong: false, interactive: false)

                InlineAskAIPanel(
                    model: model,
                    title: "Notes AI",
                    subtitle: "Attach notes or recent transcripts and ask for summaries, next steps, or drafts."
                ) {
                    Button {
                        model.addSelectedSubjectToAskAI()
                    } label: {
                        Label("Attach Subject", systemImage: "folder")
                    }
                    .help("Attach all notes in the selected subject to Ask AI")

                    Button {
                        model.addSelectedTranscriptionNoteToAskAI()
                    } label: {
                        Label("Attach Note", systemImage: "note.text")
                    }
                    .disabled(model.selectedTranscriptionNote == nil)
                    .help("Attach the selected note to Ask AI")

                    RecentTranscriptsMenu(model: model)
                }
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420, maxHeight: .infinity)
                .onAppear {
                    model.prepareAskAIForSelectedSubject()
                }
                .onChange(of: subject.id) { _, _ in
                    model.prepareAskAIForSelectedSubject()
                }
            }
            .padding(12)
            .themeWindowBackground(model.activeTheme)
        } else {
            ContentUnavailableView("No Subject", systemImage: "folder", description: Text("Create a subject group for quick transcription notes."))
                .themeWindowBackground(model.activeTheme)
        }
    }

    private func appendLatestDictationToSelectedNote() {
        guard let last = model.transcripts.first?.displayText, !last.isEmpty else {
            model.statusText = "No recent dictation transcript"
            return
        }
        let existing = model.selectedTranscriptionNote?.body ?? ""
        model.updateSelectedTranscriptionNote(body: [existing, last].filter { !$0.isEmpty }.joined(separator: "\n\n"))
    }

    private var selectedDocumentBinding: Binding<String?> {
        Binding(
            get: { model.selectedEditorDocument?.id },
            set: { value in
                if let value {
                    model.selectEditorDocument(value)
                }
            }
        )
    }

    private var selectedSubjectBinding: Binding<String?> {
        Binding(
            get: { model.selectedTranscriptionSubject?.id },
            set: { value in
                if let value {
                    model.selectTranscriptionSubject(value)
                }
            }
        )
    }

    private var selectedNoteBinding: Binding<String?> {
        Binding(
            get: { model.selectedTranscriptionNote?.id },
            set: { value in
                model.selectedTranscriptionNoteID = value
            }
        )
    }
}

private enum AskAIImportKind {
    case files
    case images
    case audio

    var panelTitle: String {
        switch self {
        case .files:
            "Attach files to Ask AI"
        case .images:
            "Attach images to Ask AI"
        case .audio:
            "Attach audio clips to Ask AI"
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .files:
            [.item]
        case .images:
            [.image]
        case .audio:
            [.audio]
        }
    }
}

struct AskAIWindowView: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(selection: selectedThreadBinding) {
                ForEach(model.askAIThreads) { thread in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(thread.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(model.askAIThreadSubtitle(thread))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(thread.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.createAskAIThread()
                } label: {
                    Label("New Chat", systemImage: "plus.message")
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
        } detail: {
            askAIDetail
        }
        .navigationTitle("Ask AI")
        .task {
            await model.refreshTranscripts()
            await model.loadConversations()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.addSelectedSubjectToAskAI()
                } label: {
                    Label("Add Subject", systemImage: "folder.badge.plus")
                }
                .help("Attach the currently selected subject notes to this AI chat")

                ConversationAttachmentMenu(model: model)

                RecentTranscriptsMenu(model: model)

                Button {
                    importAskAIContext(.files)
                } label: {
                    Label("Add Files", systemImage: "paperclip")
                }
                .help("Attach files, PDFs, Markdown, DOCX, or text documents")

                Button {
                    importAskAIContext(.images)
                } label: {
                    Label("Add Images", systemImage: "photo")
                }
                .help("Attach images for vision-capable AI models")

                Button {
                    importAskAIContext(.audio)
                } label: {
                    Label("Add Audio", systemImage: "waveform")
                }
                .help("Attach audio clips so they are visible and playable inside this AI chat")
            }
        }
        .themeWindowBackground(model.activeTheme)
        .frame(minWidth: 980, minHeight: 680)
    }

    @ViewBuilder
    private var askAIDetail: some View {
        if let thread = model.selectedAskAIThread {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !thread.attachments.isEmpty {
                            attachmentsStrip(thread.attachments)
                        }

                        ForEach(thread.messages) { message in
                            AskAIMessageBubble(message: message, theme: model.activeTheme)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                VStack(spacing: 10) {
                    AskAIProviderSessionControls(model: model)

                        TextEditor(text: $model.askAIPromptDraft)
                        .frame(height: 104)
                        .scrollContentBackground(.hidden)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.separator.opacity(0.45), lineWidth: 1)
                        }

                    HStack {
                        Text(model.askAIProviderSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("\(thread.attachments.count) context")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            importAskAIContext(.files)
                        } label: {
                            Image(systemName: "paperclip")
                        }
                        .help("Add files, PDFs, or documents")

                        Button {
                            importAskAIContext(.images)
                        } label: {
                            Image(systemName: "photo")
                        }
                        .help("Add images")

                        Button {
                            importAskAIContext(.audio)
                        } label: {
                            Image(systemName: "waveform")
                        }
                        .help("Add audio clips")

                        Button {
                            Task {
                                await model.sendAskAIMessage()
                            }
                        } label: {
                            Label(model.isAskAISending ? "Sending" : "Send", systemImage: "paperplane.fill")
                        }
                        .disabled(model.isAskAISending || model.askAIPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Send this message to the configured AI provider")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.regularMaterial)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .font(.system(size: 34, weight: .semibold))
                                Text("Drop files, images, or audio into Ask AI")
                                    .font(.headline)
                            }
                            .foregroundStyle(.primary)
                        }
                        .padding(28)
                }
            }
            .onDrop(
                of: [UTType.fileURL.identifier, UTType.image.identifier, UTType.audio.identifier, UTType.pdf.identifier],
                isTargeted: $isDropTargeted,
                perform: handleDroppedItems
            )
        } else {
            ContentUnavailableView("No Chat", systemImage: "sparkles", description: Text("Start a chat, then add files, images, subject groups, or conversations as context."))
        }
    }

    private func importAskAIContext(_ kind: AskAIImportKind) {
        let panel = NSOpenPanel()
        panel.title = kind.panelTitle
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = kind.allowedContentTypes

        guard panel.runModal() == .OK else {
            return
        }

        for url in panel.urls {
            addImportedAskAIURL(url, kind: kind)
        }
    }

    private func addImportedAskAIURL(_ url: URL, kind: AskAIImportKind) {
        switch kind {
        case .files:
            model.addFileToAskAI(url: url)
        case .images:
            model.addImageToAskAI(url: url)
        case .audio:
            model.addAudioToAskAI(url: url)
        }
    }

    private func attachmentsStrip(_ attachments: [AskAIContextAttachment]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top) {
                ForEach(attachments) { attachment in
                    AskAIAttachmentPreviewCard(attachment: attachment)
                }
            }
        }
    }

    private func attachmentPreview(_ attachment: AskAIContextAttachment) -> String {
        if attachment.kind == .image {
            return attachment.mimeType ?? "image"
        }
        let trimmed = attachment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (attachment.mimeType ?? "file") : trimmed
    }

    private func handleDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if loadDroppedFileURL(from: provider) {
                handled = true
                continue
            }
            if loadDroppedImage(from: provider) {
                handled = true
                continue
            }
            if loadDroppedAudio(from: provider) {
                handled = true
            }
        }
        return handled
    }

    private func loadDroppedFileURL(from provider: NSItemProvider) -> Bool {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let itemURL = item as? URL {
                url = itemURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let string = item as? String {
                url = URL(string: string)
            } else {
                url = nil
            }

            if let url {
                Task { @MainActor in
                    model.addURLToAskAI(url: url)
                }
            }
        }
        return true
    }

    private func loadDroppedImage(from provider: NSItemProvider) -> Bool {
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data, !data.isEmpty else {
                return
            }
            let fileType = UTType(typeIdentifier)
            let fileExtension = fileType?.preferredFilenameExtension ?? "png"
            let url = FileManager.default.temporaryDirectory
                .appending(path: "OmniSpeak-Dropped-\(UUID().uuidString).\(fileExtension)")
            do {
                try data.write(to: url)
            } catch {
                return
            }
            Task { @MainActor in
                model.addURLToAskAI(url: url)
            }
        }
        return true
    }

    private func loadDroppedAudio(from provider: NSItemProvider) -> Bool {
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            UTType(identifier)?.conforms(to: .audio) == true
        }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data, !data.isEmpty else {
                return
            }
            let fileType = UTType(typeIdentifier)
            let fileExtension = fileType?.preferredFilenameExtension ?? "wav"
            let url = FileManager.default.temporaryDirectory
                .appending(path: "OmniSpeak-Dropped-\(UUID().uuidString).\(fileExtension)")
            do {
                try data.write(to: url)
            } catch {
                return
            }
            Task { @MainActor in
                model.addAudioToAskAI(url: url)
            }
        }
        return true
    }

    private var selectedThreadBinding: Binding<String?> {
        Binding(
            get: { model.selectedAskAIThread?.id },
            set: { value in
                if let value {
                    model.selectAskAIThread(value)
                }
            }
        )
    }
}

private struct ConversationAttachmentMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            Button {
                Task {
                    await model.loadConversations()
                }
            } label: {
                Label("Refresh Conversations", systemImage: "arrow.clockwise")
            }
            .help("Reload saved conversations from the local engine")

            if let detail = model.selectedConversationDetail {
                Button {
                    model.addConversationToAskAI(detail)
                } label: {
                    Label("Current Conversation", systemImage: "bubble.left.and.text.bubble.right")
                }
                .help("Attach the currently open conversation to Ask AI")
            }

            Divider()

            if model.conversationSessions.isEmpty {
                Text("No saved conversations")
            } else {
                ForEach(model.conversationSessions.prefix(12)) { session in
                    Button {
                        Task {
                            await model.addConversationSessionToAskAI(session)
                        }
                    } label: {
                        Label(session.title, systemImage: session.isActive ? "record.circle" : "text.bubble")
                    }
                    .disabled(model.isConversationRecording)
                    .help("Load and attach \(session.title) to Ask AI")
                }
            }
        } label: {
            Label("Add Conversation", systemImage: "bubble.left.and.text.bubble.right")
        }
        .help("Attach saved conversation transcripts to Ask AI")
    }
}

private struct RecentTranscriptsMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            Button {
                Task {
                    await model.refreshTranscripts()
                }
            } label: {
                Label("Refresh Transcripts", systemImage: "arrow.clockwise")
            }
            .help("Reload recent dictation transcripts from the local engine")

            if let latest = model.transcripts.first {
                Button {
                    model.addTranscriptToAskAI(latest)
                } label: {
                    Label("Latest Transcript", systemImage: "text.quote")
                }
                .help("Attach the most recent dictation transcript to Ask AI")
            }

            Divider()

            if model.transcripts.isEmpty {
                Text("No recent transcripts")
            } else {
                ForEach(model.transcripts.prefix(12)) { transcript in
                    Button {
                        model.addTranscriptToAskAI(transcript)
                    } label: {
                        Label(transcriptMenuTitle(transcript), systemImage: "text.quote")
                    }
                    .help("Attach this transcript to Ask AI")
                }
            }
        } label: {
            Label("Add Transcript", systemImage: "text.quote")
        }
        .help("Attach recent dictation transcripts to Ask AI")
    }

    private func transcriptMenuTitle(_ transcript: EngineTranscriptRecord) -> String {
        let text = transcript.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return transcript.createdAt
        }
        return String(text.prefix(42))
    }
}

private struct InlineAskAIPanel<Actions: View>: View {
    @Bindable var model: AppModel
    let title: String
    let subtitle: String
    let actions: Actions

    init(
        model: AppModel,
        title: String,
        subtitle: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.model = model
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: "sparkles")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.askAIProviderSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            AskAIProviderSessionControls(model: model, compact: true)

            VStack(alignment: .leading, spacing: 8) {
                actions
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()

            if let thread = model.selectedAskAIThread {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !thread.attachments.isEmpty {
                            Text("\(thread.attachments.count) context attachments")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(Array(thread.messages.suffix(8))) { message in
                            AskAIMessageBubble(message: message, theme: model.activeTheme)
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Chat", systemImage: "sparkles", description: Text("Start a chat or attach context."))
                    .frame(maxHeight: .infinity)
            }

            VStack(spacing: 8) {
                TextEditor(text: $model.askAIPromptDraft)
                    .frame(minHeight: 76, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator.opacity(0.45), lineWidth: 1)
                    }
                    .help("Type a question or instruction for Ask AI")

                HStack {
                    Button {
                        model.createAskAIThread()
                    } label: {
                        Image(systemName: "plus.message")
                    }
                    .help("Start a new AI chat")

                    Spacer()

                    Button {
                        Task {
                            await model.sendAskAIMessage()
                        }
                    } label: {
                        Label(model.isAskAISending ? "Sending" : "Send", systemImage: "paperplane.fill")
                    }
                    .disabled(model.isAskAISending || model.askAIPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send this message to Ask AI")
                }
            }
        }
        .padding(12)
        .themeSurface(model.activeTheme, cornerRadius: 12, strong: false)
    }
}

private struct AskAIProviderSessionControls: View {
    @Bindable var model: AppModel
    var compact = false

    var body: some View {
        let provider = model.selectedAskAIProvider
        let modelChoices = model.askAIModelChoices(for: provider)

        Group {
            if compact {
                VStack(alignment: .leading, spacing: 6) {
                    controls(provider: provider, modelChoices: modelChoices)
                }
            } else {
                HStack(spacing: 10) {
                    controls(provider: provider, modelChoices: modelChoices)
                    Spacer()
                }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func controls(provider: TextLLMProviderKind, modelChoices: [String]) -> some View {
        Picker("Provider", selection: providerBinding) {
            ForEach(model.askAIProviderChoices) { provider in
                Text(model.askAIProviderLabel(provider)).tag(provider)
            }
        }
        .pickerStyle(.menu)
        .frame(width: compact ? 220 : 190)
        .help("Choose the AI provider for this chat session")

        if modelChoices.isEmpty {
            TextField("Model", text: modelBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: compact ? 220 : 260)
                .help("Enter the model for this Ask AI session")
        } else {
            Picker("Model", selection: modelBinding) {
                ForEach(modelChoices, id: \.self) { modelName in
                    Text(modelName).tag(modelName)
                }
            }
            .pickerStyle(.menu)
            .frame(width: compact ? 220 : 300)
            .help("Choose the model for this chat session")
        }

        Toggle(isOn: webSearchBinding) {
            Label("Web", systemImage: "network")
        }
        .toggleStyle(.switch)
        .help("Search the web and attach current results to this Ask AI message")
    }

    private var providerBinding: Binding<TextLLMProviderKind> {
        Binding(
            get: { model.selectedAskAIProvider },
            set: { model.setSelectedAskAIProvider($0) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { model.selectedAskAIModel },
            set: { model.setSelectedAskAIModel($0) }
        )
    }

    private var webSearchBinding: Binding<Bool> {
        Binding(
            get: { model.selectedAskAIWebSearchEnabled },
            set: { model.setSelectedAskAIWebSearchEnabled($0) }
        )
    }
}

private struct AskAIAttachmentPreviewCard: View {
    let attachment: AskAIContextAttachment

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(attachment.title, systemImage: attachment.kind.systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            switch attachment.kind {
            case .image:
                imagePreview
            case .audio:
                AskAIAudioPreview(attachment: attachment)
            default:
                Text(attachmentPreview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(width: attachment.kind == .image ? 190 : 220, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .help(attachmentHelp)
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = attachmentImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 170, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.separator.opacity(0.35), lineWidth: 1)
                }
        } else {
            Text(attachmentPreview)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var attachmentImage: NSImage? {
        if let filePath = attachment.filePath,
           let image = NSImage(contentsOfFile: filePath) {
            return image
        }

        guard let dataURL = attachment.dataURL,
              let data = Self.data(fromDataURL: dataURL) else {
            return nil
        }
        return NSImage(data: data)
    }

    private var attachmentPreview: String {
        if attachment.kind == .image {
            return attachment.mimeType ?? "image"
        }
        if attachment.kind == .audio {
            return attachment.mimeType ?? "audio"
        }
        let trimmed = attachment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (attachment.mimeType ?? "context") : trimmed
    }

    private var attachmentHelp: String {
        switch attachment.kind {
        case .image:
            "Image attachment. Vision-capable AI providers can receive this image."
        case .audio:
            "Audio attachment. You can play it here; AI receives the attachment metadata."
        default:
            "Context attachment sent with Ask AI messages."
        }
    }

    static func data(fromDataURL dataURL: String) -> Data? {
        guard let comma = dataURL.firstIndex(of: ",") else {
            return nil
        }
        return Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
    }
}

private struct AskAIAudioPreview: View {
    let attachment: AskAIContextAttachment
    @State private var sound: NSSound?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(isPlaying ? "Stop audio preview" : "Play audio preview")

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.mimeType ?? "audio")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(attachment.filePath ?? "Embedded audio")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            sound?.stop()
            isPlaying = false
            return
        }

        guard let nextSound = makeSound() else {
            return
        }
        sound = nextSound
        isPlaying = nextSound.play()
    }

    private func makeSound() -> NSSound? {
        if let filePath = attachment.filePath {
            return NSSound(contentsOfFile: filePath, byReference: true)
        }

        guard let dataURL = attachment.dataURL,
              let data = AskAIAttachmentPreviewCard.data(fromDataURL: dataURL) else {
            return nil
        }
        return NSSound(data: data)
    }
}

private struct AskAIMessageBubble: View {
    let message: AskAIMessage
    let theme: OmniVoiceTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role.displayName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(message.text)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: message.role == .user ? 540 : 720, alignment: .leading)
                .background(
                    message.role == .user
                        ? Color(themeColor: theme.accentColor).opacity(0.18)
                        : Color(themeColor: theme.surfaceTint).opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
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

private extension AskAIContextAttachmentKind {
    var systemImage: String {
        switch self {
        case .file:
            "doc"
        case .image:
            "photo"
        case .audio:
            "waveform"
        case .subject:
            "folder"
        case .conversation:
            "bubble.left.and.text.bubble.right"
        case .document:
            "doc.text"
        case .transcript:
            "text.quote"
        }
    }
}
