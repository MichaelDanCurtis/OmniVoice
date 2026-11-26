import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import OmniVoiceCore
import OSLog
import Tokenizers

/// In-process Apple Silicon Metal LLM cleanup backed by `mlx-swift-lm`.
/// Runs Qwen3 1.7B / 4B 4-bit MLX models natively inside `OmniSpeak.app` with zero Python.
actor MLXLocalCleanupService {
    static let shared = MLXLocalCleanupService()

    private let logger = Logger(subsystem: "com.omnispeak.OmniVoiceApp", category: "MLXCleanup")
    private var loadedRepoID: String?
    private var loadedContainer: ModelContainer?
    private var didConfigureMetallib = false

    static func repoID(for providerID: String) -> String {
        switch providerID.trimmingCharacters(in: .whitespacesAndNewlines) {
        case CleanupModelRecommendation.qwen3_1_7BMLX4Bit.providerID, "":
            return "mlx-community/Qwen3-1.7B-4bit"
        case CleanupModelRecommendation.qwen3_4BInstructMLX4Bit.providerID:
            return "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        case let custom where custom.contains("/"):
            return custom
        default:
            return "mlx-community/Qwen3-1.7B-4bit"
        }
    }

    func isLoaded(providerID: String) -> Bool {
        loadedContainer != nil && loadedRepoID == Self.repoID(for: providerID)
    }

    func unload() {
        loadedContainer = nil
        loadedRepoID = nil
        Memory.clearCache()
    }

    func prepareModel(
        providerID: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let repoID = Self.repoID(for: providerID)
        _ = try await ensureContainer(repoID: repoID, onProgress: onProgress)
    }

    func cleanup(
        rawTranscript: String,
        style: StyleProfile,
        dictionaryTerms: [String],
        appContext: String,
        providerID: String
    ) async throws -> String {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, style != .raw else {
            return trimmed
        }

        let repoID = Self.repoID(for: providerID)
        let container = try await ensureContainer(repoID: repoID, onProgress: nil)

        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        let maxTokens = max(96, min(512, wordCount * 2 + 48))

        let instructions = Self.systemPrompt(
            style: style,
            dictionaryTerms: dictionaryTerms,
            appContext: appContext
        )

        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.0),
            additionalContext: ["enable_thinking": false]
        )

        let response = try await session.respond(to: "Transcript:\n\(trimmed)")
        let sanitized = Self.sanitizeOutput(response)
        guard !sanitized.isEmpty else {
            return trimmed
        }
        return sanitized
    }

    func translate(
        text: String,
        targetLanguage: String,
        providerID: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let repoID = Self.repoID(for: providerID)
        let container = try await ensureContainer(repoID: repoID, onProgress: nil)
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        let maxTokens = max(128, min(640, wordCount * 3 + 64))

        let instructions = """
        You are an accurate, natural translator. Translate the user's text into \(targetLanguage).
        Preserve tone, formatting, and technical terms. Output ONLY the translated text with no quotes or commentary.
        """
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.0),
            additionalContext: ["enable_thinking": false]
        )
        let response = try await session.respond(to: trimmed)
        let sanitized = Self.sanitizeOutput(response)
        return sanitized.isEmpty ? trimmed : sanitized
    }

    func transformSelection(
        selectedText: String,
        instruction: String,
        providerID: String
    ) async throws -> String {
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else { return selectedText }

        let repoID = Self.repoID(for: providerID)
        let container = try await ensureContainer(repoID: repoID, onProgress: nil)
        let wordCount = trimmedSelection.split(whereSeparator: \.isWhitespace).count
        let maxTokens = max(160, min(1024, wordCount * 2 + 128))

        let instructions = """
        You are a crisp inline text editor. Apply the user's instruction to the selected text.
        Output ONLY the transformed text with no quotes, preamble, or commentary.
        """
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.1),
            additionalContext: ["enable_thinking": false]
        )
        let prompt = "Instruction: \(instruction)\n\nSelected text:\n\(trimmedSelection)"
        let response = try await session.respond(to: prompt)
        let sanitized = Self.sanitizeOutput(response)
        return sanitized.isEmpty ? selectedText : sanitized
    }

    func generateRaw(
        instructions: String,
        prompt: String,
        maxTokens: Int = 512,
        providerID: String
    ) async throws -> String {
        let repoID = Self.repoID(for: providerID)
        let container = try await ensureContainer(repoID: repoID, onProgress: nil)
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.0),
            additionalContext: ["enable_thinking": false]
        )
        let response = try await session.respond(to: prompt)
        return Self.sanitizeOutput(response)
    }

    private func ensureContainer(
        repoID: String,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> ModelContainer {
        configureMetallibIfNeeded()

        if let existing = loadedContainer, loadedRepoID == repoID {
            return existing
        }

        logger.info("Loading MLX cleanup model \(repoID, privacy: .public)")
        let configuration = ModelConfiguration(id: repoID)
        let container = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration,
            progress: .download { progress in
                onProgress?(progress.fractionCompleted)
            }
        )
        loadedContainer = container
        loadedRepoID = repoID
        logger.info("Loaded MLX cleanup model \(repoID, privacy: .public)")
        return container
    }

    private func configureMetallibIfNeeded() {
        guard !didConfigureMetallib else { return }
        didConfigureMetallib = true

        // Cap MLX Metal scratch-buffer cache at 64 MB so unified GPU RAM doesn't bloat
        // between short dictation bursts while keeping loaded model weights resident.
        Memory.cacheLimit = 64 * 1024 * 1024

        if let resourceURL = Bundle.main.url(forResource: "mlx", withExtension: "metallib") {
            GPU.metallib = resourceURL
            logger.info("Configured MLX metallib at \(resourceURL.path, privacy: .public)")
        } else if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let colocated = execDir.appendingPathComponent("mlx.metallib")
            if FileManager.default.fileExists(atPath: colocated.path) {
                GPU.metallib = colocated
                logger.info("Configured colocated MLX metallib at \(colocated.path, privacy: .public)")
            }
        }
    }

    static func systemPrompt(
        style: StyleProfile,
        dictionaryTerms: [String],
        appContext: String
    ) -> String {
        let styleInstruction: String = switch style {
        case .professional:
            "Use clean, polished, professional prose with crisp punctuation and capitalization."
        case .expanded:
            "Write clear, complete, well-structured sentences while preserving the speaker's meaning."
        case .concise:
            "Remove filler words (um, uh, like, you know) and tighten wording while preserving all meaning."
        case .neutral, .raw:
            "Fix punctuation, capitalization, and obvious speech errors while preserving the speaker's exact wording and intent."
        }

        var lines: [String] = [
            "You are a fast, faithful dictation post-processor.",
            styleInstruction,
            "Resolve spoken self-corrections (e.g., 'going to the store, no wait, the house' -> 'going to the house').",
            "Output ONLY the cleaned text with no quotes, commentary, or explanations.",
        ]

        let cleanedTerms = dictionaryTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanedTerms.isEmpty {
            lines.append("Preserve exact spelling for these terms when spoken: \(cleanedTerms.prefix(40).joined(separator: ", ")).")
        }

        let trimmedContext = appContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContext.isEmpty {
            lines.append("Target app: \(trimmedContext).")
        }

        return lines.joined(separator: " ")
    }

    static func sanitizeOutput(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip any Qwen3 <think>...</think> reasoning block defensively.
        if let openRange = text.range(of: "<think>"),
           let closeRange = text.range(of: "</think>", range: openRange.upperBound..<text.endIndex) {
            text.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let openRange = text.range(of: "<think>") {
            text = String(text[..<openRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Strip wrapping double quotes if the model echoed quotes around the whole utterance.
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            let inner = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.contains("\"") {
                text = inner
            }
        }

        return text
    }
}
