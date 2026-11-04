import Foundation

public struct TranscriptionNote: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var subjectID: String
    public var title: String
    public var body: String
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = UUID().uuidString,
        subjectID: String,
        title: String = "Quick note",
        body: String = "",
        createdAt: String = OmniWorkspaceClock.now(),
        updatedAt: String = OmniWorkspaceClock.now()
    ) {
        self.id = id
        self.subjectID = subjectID
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case subjectID = "subject_id"
        case title
        case body
        case createdAt
        case updatedAt
    }
}

public struct TranscriptionSubject: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: String
    public var updatedAt: String
    public var notes: [TranscriptionNote]

    public init(
        id: String = UUID().uuidString,
        title: String,
        createdAt: String = OmniWorkspaceClock.now(),
        updatedAt: String = OmniWorkspaceClock.now(),
        notes: [TranscriptionNote] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
    }

    public func markdownContext() -> String {
        var lines = [
            "# \(title)",
            "",
            "- Created: \(createdAt)",
            "- Updated: \(updatedAt)",
            "",
        ]

        if notes.isEmpty {
            lines.append("_No notes in this subject._")
        } else {
            for note in notes {
                lines.append("## \(note.title)")
                lines.append("")
                lines.append(note.body.trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}

public struct EditorDocumentStyle: Codable, Equatable, Sendable {
    public var fontName: String
    public var fontSize: Double

    public init(fontName: String = "Avenir Next", fontSize: Double = 14) {
        self.fontName = fontName
        self.fontSize = fontSize
    }
}

public struct EditorDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var bodyMarkdown: String
    public var createdAt: String
    public var updatedAt: String
    public var sourceSubjectID: String?
    public var contextMarkdown: String
    public var style: EditorDocumentStyle

    public init(
        id: String = UUID().uuidString,
        title: String,
        bodyMarkdown: String = "",
        createdAt: String = OmniWorkspaceClock.now(),
        updatedAt: String = OmniWorkspaceClock.now(),
        sourceSubjectID: String? = nil,
        contextMarkdown: String = "",
        style: EditorDocumentStyle = EditorDocumentStyle()
    ) {
        self.id = id
        self.title = title
        self.bodyMarkdown = bodyMarkdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceSubjectID = sourceSubjectID
        self.contextMarkdown = contextMarkdown
        self.style = style
    }

    public static func from(subject: TranscriptionSubject, prompt: String = "") -> EditorDocument {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmedPrompt.isEmpty
            ? "# \(subject.title)\n\n"
            : "# \(subject.title)\n\n\(trimmedPrompt)\n"
        return EditorDocument(
            title: subject.title,
            bodyMarkdown: body,
            sourceSubjectID: subject.id,
            contextMarkdown: subject.markdownContext()
        )
    }

    public static func from(conversation: ConversationDetail) -> EditorDocument {
        let transcript = ConversationArchive.markdown(for: conversation)
        return EditorDocument(
            title: conversation.session.title,
            bodyMarkdown: transcript,
            contextMarkdown: transcript
        )
    }

    public var aiContext: String {
        let context = contextMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty ? bodyMarkdown : context
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case bodyMarkdown
        case createdAt
        case updatedAt
        case sourceSubjectID = "source_subject_id"
        case contextMarkdown
        case style
    }
}

public enum AskAIMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
}

public struct AskAIMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var role: AskAIMessageRole
    public var text: String
    public var createdAt: String

    public init(
        id: String = UUID().uuidString,
        role: AskAIMessageRole,
        text: String,
        createdAt: String = OmniWorkspaceClock.now()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public enum AskAIContextAttachmentKind: String, Codable, Equatable, Sendable {
    case file
    case image
    case audio
    case subject
    case conversation
    case document
    case transcript
}

public struct AskAIContextAttachment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: AskAIContextAttachmentKind
    public var title: String
    public var text: String
    public var filePath: String?
    public var mimeType: String?
    public var dataURL: String?

    public init(
        id: String = UUID().uuidString,
        kind: AskAIContextAttachmentKind,
        title: String,
        text: String,
        filePath: String? = nil,
        mimeType: String? = nil,
        dataURL: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.filePath = filePath
        self.mimeType = mimeType
        self.dataURL = dataURL
    }

    public init(subject: TranscriptionSubject) {
        self.init(kind: .subject, title: subject.title, text: subject.markdownContext())
    }

    public init(conversation: ConversationDetail) {
        self.init(
            kind: .conversation,
            title: conversation.session.title,
            text: ConversationArchive.markdown(for: conversation)
        )
    }

    public init(document: EditorDocument) {
        var sections = [
            "# \(document.title)",
            "",
            "## Document",
            "",
            document.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines),
        ]

        let context = document.contextMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !context.isEmpty {
            sections.append(contentsOf: ["", "## Source Context", "", context])
        }

        self.init(
            kind: .document,
            title: document.title,
            text: sections.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public init(transcript: EngineTranscriptRecord) {
        var lines = [
            "# Transcript \(transcript.createdAt)",
            "",
            "- Source: \(transcript.source)",
        ]
        if let provider = transcript.provider, !provider.isEmpty {
            lines.append("- Provider: \(provider)")
        }
        if let style = transcript.style, !style.isEmpty {
            lines.append("- Style: \(style)")
        }
        if let durationMs = transcript.durationMs {
            lines.append("- Duration: \(durationMs) ms")
        }
        lines.append(contentsOf: ["", transcript.displayText])

        self.init(
            kind: .transcript,
            title: "Transcript \(transcript.createdAt)",
            text: lines.joined(separator: "\n")
        )
    }

    public var contextMarkdown: String {
        "## \(title)\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

public struct AskAIThread: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: String
    public var updatedAt: String
    public var subjectID: String?
    public var providerOverride: TextLLMProviderKind?
    public var modelOverride: String?
    public var webSearchEnabled: Bool
    public var messages: [AskAIMessage]
    public var attachments: [AskAIContextAttachment]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case updatedAt
        case subjectID
        case providerOverride
        case modelOverride
        case webSearchEnabled
        case messages
        case attachments
    }

    public init(
        id: String = UUID().uuidString,
        title: String = "Ask AI",
        createdAt: String = OmniWorkspaceClock.now(),
        updatedAt: String = OmniWorkspaceClock.now(),
        subjectID: String? = nil,
        providerOverride: TextLLMProviderKind? = nil,
        modelOverride: String? = nil,
        webSearchEnabled: Bool = false,
        messages: [AskAIMessage] = [],
        attachments: [AskAIContextAttachment] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.subjectID = subjectID
        self.providerOverride = providerOverride
        self.modelOverride = modelOverride
        self.webSearchEnabled = webSearchEnabled
        self.messages = messages
        self.attachments = attachments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            createdAt: try container.decode(String.self, forKey: .createdAt),
            updatedAt: try container.decode(String.self, forKey: .updatedAt),
            subjectID: try container.decodeIfPresent(String.self, forKey: .subjectID),
            providerOverride: try container.decodeIfPresent(TextLLMProviderKind.self, forKey: .providerOverride),
            modelOverride: try container.decodeIfPresent(String.self, forKey: .modelOverride),
            webSearchEnabled: try container.decodeIfPresent(Bool.self, forKey: .webSearchEnabled) ?? false,
            messages: try container.decodeIfPresent([AskAIMessage].self, forKey: .messages) ?? [],
            attachments: try container.decodeIfPresent([AskAIContextAttachment].self, forKey: .attachments) ?? []
        )
    }

    public var contextText: String {
        attachments
            .map(\.contextMarkdown)
            .joined(separator: "\n\n")
    }
}

public struct OmniWorkspaceSnapshot: Codable, Equatable, Sendable {
    public var subjects: [TranscriptionSubject]
    public var editorDocuments: [EditorDocument]
    public var askAIThreads: [AskAIThread]

    public init(
        subjects: [TranscriptionSubject] = [],
        editorDocuments: [EditorDocument] = [],
        askAIThreads: [AskAIThread] = []
    ) {
        self.subjects = subjects
        self.editorDocuments = editorDocuments
        self.askAIThreads = askAIThreads
    }
}

public final class OmniWorkspaceStore: @unchecked Sendable {
    public let rootURL: URL

    public init(rootURL: URL = OmniWorkspaceArchive.defaultRootURL()) {
        self.rootURL = rootURL
    }

    public func load() throws -> OmniWorkspaceSnapshot {
        let url = rootURL.appending(path: "workspace.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return OmniWorkspaceSnapshot()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(OmniWorkspaceSnapshot.self, from: data)
    }

    public func save(_ snapshot: OmniWorkspaceSnapshot) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: rootURL.appending(path: "workspace.json"), options: .atomic)
        try writeTranscriberMarkdown(subjects: snapshot.subjects)
    }

    private func writeTranscriberMarkdown(subjects: [TranscriptionSubject]) throws {
        let fileManager = FileManager.default
        let transcriberURL = rootURL.appending(path: "Transcriber", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: transcriberURL.path) {
            try fileManager.removeItem(at: transcriberURL)
        }
        try fileManager.createDirectory(at: transcriberURL, withIntermediateDirectories: true)

        for subject in subjects {
            let subjectURL = transcriberURL.appending(path: sanitizedFileComponent(subject.title), directoryHint: .isDirectory)
            try fileManager.createDirectory(at: subjectURL, withIntermediateDirectories: true)
            try subject.markdownContext().write(to: subjectURL.appending(path: "_subject.md"), atomically: true, encoding: .utf8)
            for note in subject.notes {
                let noteURL = subjectURL.appending(path: "\(sanitizedFileComponent(note.title)).md")
                let markdown = "# \(note.title)\n\n\(note.body.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private func sanitizedFileComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}

public enum OmniWorkspaceArchive {
    public static func defaultRootURL(
        applicationSupportURL: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ) -> URL {
        let base = applicationSupportURL ?? URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
        let preferred = base.appending(path: ProductBrand.applicationSupportDirectoryName, directoryHint: .isDirectory)
        let legacy = base.appending(path: ProductBrand.legacyApplicationSupportDirectoryName, directoryHint: .isDirectory)
        let root = if FileManager.default.fileExists(atPath: legacy.path),
                      !FileManager.default.fileExists(atPath: preferred.path) {
            legacy
        } else {
            preferred
        }
        return root.appending(path: "Workspace", directoryHint: .isDirectory)
    }

    public static func writeMarkdown(
        _ document: EditorDocument,
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let exportURL = rootURL.appending(path: "Editor", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: exportURL, withIntermediateDirectories: true)
        let url = exportURL.appending(path: "\(sanitizedFileComponent(document.title)).md")
        try document.bodyMarkdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func writeDocx(
        _ document: EditorDocument,
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let exportURL = rootURL.appending(path: "Editor", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: exportURL, withIntermediateDirectories: true)
        let destinationURL = exportURL.appending(path: "\(sanitizedFileComponent(document.title)).docx")
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let packageURL = fileManager.temporaryDirectory
            .appending(path: "omnivoice-docx-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? fileManager.removeItem(at: packageURL)
        }

        try writeDocxPackage(document, packageURL: packageURL, fileManager: fileManager)
        try zipPackage(packageURL, destinationURL: destinationURL)
        return destinationURL
    }

    private static func writeDocxPackage(
        _ document: EditorDocument,
        packageURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: packageURL.appending(path: "_rels", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageURL.appending(path: "word", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try contentTypesXML.write(to: packageURL.appending(path: "[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rootRelationshipsXML.write(to: packageURL.appending(path: "_rels").appending(path: ".rels"), atomically: true, encoding: .utf8)
        try stylesXML(for: document.style).write(to: packageURL.appending(path: "word").appending(path: "styles.xml"), atomically: true, encoding: .utf8)
        try documentXML(for: document).write(to: packageURL.appending(path: "word").appending(path: "document.xml"), atomically: true, encoding: .utf8)
    }

    private static func zipPackage(_ packageURL: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", destinationURL.path, "."]
        process.currentDirectoryURL = packageURL
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func documentXML(for document: EditorDocument) -> String {
        let paragraphs = document.bodyMarkdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map { paragraphXML(for: $0) }
            .joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(paragraphs)
            <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private static func paragraphXML(for rawLine: String) -> String {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let isHeading = trimmed.hasPrefix("# ")
        let text = isHeading ? String(trimmed.dropFirst(2)) : rawLine
        let style = isHeading ? "<w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr>" : ""
        return """
        <w:p>\(style)<w:r><w:t xml:space="preserve">\(xmlEscaped(text))</w:t></w:r></w:p>
        """
    }

    private static func stylesXML(for style: EditorDocumentStyle) -> String {
        let fontName = xmlEscaped(style.fontName)
        let halfPoints = max(1, Int((style.fontSize * 2).rounded()))
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/>
            <w:rPr><w:rFonts w:ascii="\(fontName)" w:hAnsi="\(fontName)"/><w:sz w:val="\(halfPoints)"/></w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading1">
            <w:name w:val="heading 1"/>
            <w:rPr><w:b/><w:rFonts w:ascii="\(fontName)" w:hAnsi="\(fontName)"/><w:sz w:val="\(halfPoints + 12)"/></w:rPr>
          </w:style>
        </w:styles>
        """
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    </Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func sanitizedFileComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}

public enum DictationTriggerMode: Equatable, Sendable {
    case momentary
    case latched
}

public enum DictationTriggerPressDecision: Equatable, Sendable {
    case startMomentary
    case startLatched
    case finishLatched
    case ignore
}

public struct DictationTriggerState: Equatable, Sendable {
    public static let doubleTapInterval: TimeInterval = 0.35

    public private(set) var mode: DictationTriggerMode?
    private var lastMomentaryReleaseTime: TimeInterval?

    public init(mode: DictationTriggerMode? = nil) {
        self.mode = mode
    }

    @discardableResult
    public mutating func press(at time: TimeInterval) -> DictationTriggerPressDecision {
        if mode == .latched {
            mode = nil
            lastMomentaryReleaseTime = nil
            return .finishLatched
        }

        if let lastMomentaryReleaseTime, time - lastMomentaryReleaseTime <= Self.doubleTapInterval {
            mode = .latched
            self.lastMomentaryReleaseTime = nil
            return .startLatched
        }

        guard mode == nil else {
            return .ignore
        }

        mode = .momentary
        return .startMomentary
    }

    @discardableResult
    public mutating func release(at time: TimeInterval) -> Bool {
        switch mode {
        case .momentary:
            mode = nil
            lastMomentaryReleaseTime = time
            return true
        case .latched:
            return false
        case nil:
            return false
        }
    }

    public mutating func cancel() {
        mode = nil
        lastMomentaryReleaseTime = nil
    }
}

public enum OmniWorkspaceClock {
    public static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
