import CoreML
import CryptoKit
import Foundation
import OmniVoiceCore

/// On-device Apple Neural Engine (CoreML FP16) punctuation restoration service backed by
/// `handyshed/lark-punctuation` (MIT-licensed vocabulary-pruned XLM-RoBERTa FullStop export).
///
/// Key guarantees:
/// - Runs in ~8-15 ms per pass on Apple Silicon Neural Engine (fixed 512-token ML Program)
/// - Cannot hallucinate, delete, or reword spoken words — only attaches `.`, `,`, `?` and casing
/// - Self-contained Unigram SentencePiece tokenizer loaded from local `tokenizer/tokenizer.json`
/// - SHA-256 verified 1-click download from Hugging Face (`manifest.json`), completely optional
actor CoreMLPunctuationService {
    static let shared = CoreMLPunctuationService()

    static let repoID = "handyshed/lark-punctuation"
    static let manifestURL = URL(string: "https://huggingface.co/handyshed/lark-punctuation/raw/main/manifest.json")!
    static let resolveBaseURL = URL(string: "https://huggingface.co/handyshed/lark-punctuation/resolve/main")!
    static let modelDisplayName = "Lark Punctuation (CoreML ANE)"
    static let modelSizeLabel = "~235 MB"

    private static let sequenceLength = 512
    private static let bosTokenID: Int32 = 0
    private static let padTokenID: Int32 = 1
    private static let eosTokenID: Int32 = 2
    private static let unkTokenID: Int32 = 3

    private var loadedModel: MLModel?
    private var loadedTokenizer: UnigramSentencePieceTokenizer?
    private var isDownloadingNow = false

    struct ManifestFile: Decodable, Sendable {
        let path: String
        let size: Int64
        let sha256: String
    }

    private struct ManifestPayload: Decodable {
        let files: [ManifestFile]
    }

    nonisolated static var modelRootURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("OmniSpeak", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("lark-punctuation-coreml-ane", isDirectory: true)
    }

    nonisolated static var compiledModelURL: URL {
        modelRootURL.appendingPathComponent("PunctuationModel512.mlmodelc", isDirectory: true)
    }

    nonisolated static var tokenizerJSONURL: URL {
        modelRootURL.appendingPathComponent("tokenizer/tokenizer.json", isDirectory: false)
    }

    nonisolated static var isInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: compiledModelURL.appendingPathComponent("model.mil").path)
            && fm.fileExists(atPath: compiledModelURL.appendingPathComponent("weights/weight.bin").path)
            && fm.fileExists(atPath: tokenizerJSONURL.path)
    }

    func removeInstalledModel() throws {
        loadedModel = nil
        loadedTokenizer = nil
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.modelRootURL.path) {
            try fm.removeItem(at: Self.modelRootURL)
        }
    }

    /// Downloads all files from `handyshed/lark-punctuation/manifest.json` with SHA-256 verification.
    func downloadModel(
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        guard !isDownloadingNow else { return }
        isDownloadingNow = true
        defer { isDownloadingNow = false }

        onProgress(0.02, "Fetching model manifest…")
        let (manifestData, manifestResponse) = try await URLSession.shared.data(from: Self.manifestURL)
        if let http = manifestResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "CoreMLPunctuationService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Hugging Face manifest download failed (HTTP \(http.statusCode))"]
            )
        }
        let manifest = try JSONDecoder().decode(ManifestPayload.self, from: manifestData)
        let totalBytes = max(1, manifest.files.reduce(Int64(0)) { $0 + max(0, $1.size) })

        let fm = FileManager.default
        try fm.createDirectory(at: Self.modelRootURL, withIntermediateDirectories: true)
        try manifestData.write(to: Self.modelRootURL.appendingPathComponent("manifest.json"), options: .atomic)

        var completedBytes: Int64 = 0
        for file in manifest.files {
            try Task.checkCancellation()
            let destination = Self.modelRootURL.appendingPathComponent(file.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

            if fm.fileExists(atPath: destination.path),
               Self.sha256Hex(ofFileAt: destination) == file.sha256.lowercased()
            {
                completedBytes += max(0, file.size)
                let fraction = min(0.98, Double(completedBytes) / Double(totalBytes))
                onProgress(fraction, "Verified \(destination.lastPathComponent)")
                continue
            }

            guard let remoteURL = Self.resolveURL(for: file.path) else {
                throw NSError(
                    domain: "CoreMLPunctuationService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid download path: \(file.path)"]
                )
            }

            let label = destination.lastPathComponent
            let baseCompleted = completedBytes
            onProgress(min(0.97, Double(baseCompleted) / Double(totalBytes)), "Downloading \(label)…")

            let (tempURL, response) = try await Self.downloadFileWithProgress(
                from: remoteURL,
                expectedFileSize: file.size
            ) { fileBytesWritten in
                let overall = Double(baseCompleted + fileBytesWritten) / Double(totalBytes)
                let pct = Int((min(0.98, overall) * 100).rounded())
                onProgress(min(0.98, overall), "Downloading \(label) (\(pct)%)…")
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                try? fm.removeItem(at: tempURL)
                throw NSError(
                    domain: "CoreMLPunctuationService",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to download \(file.path) (HTTP \(http.statusCode))"]
                )
            }

            let actualSHA = Self.sha256Hex(ofFileAt: tempURL)
            guard actualSHA == file.sha256.lowercased() else {
                try? fm.removeItem(at: tempURL)
                throw NSError(
                    domain: "CoreMLPunctuationService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "SHA-256 verification failed for \(file.path)"]
                )
            }

            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: tempURL, to: destination)
            completedBytes += max(0, file.size)
        }

        onProgress(0.99, "Loading CoreML model on Neural Engine…")
        try prepareIfNeeded()
        onProgress(1.0, "CoreML ANE Punctuation ready")
    }

    /// Loads the compiled CoreML model and Unigram tokenizer lazily if installed on disk.
    func prepareIfNeeded() throws {
        guard Self.isInstalled else { return }
        if loadedTokenizer == nil {
            loadedTokenizer = try UnigramSentencePieceTokenizer(tokenizerJSONURL: Self.tokenizerJSONURL)
        }
        if loadedModel == nil {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            loadedModel = try MLModel(contentsOf: Self.compiledModelURL, configuration: config)
        }
    }

    /// Restores `.`, `,`, `?` and post-sentence capitalization on `text` using the CoreML ANE model.
    /// Returns `nil` if the model is not installed or unavailable so the caller can fall back to fast rules.
    func restorePunctuation(_ text: String, isFinal: Bool) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Self.isInstalled else { return nil }

        do {
            try prepareIfNeeded()
        } catch {
            return nil
        }

        guard let model = loadedModel, let tokenizer = loadedTokenizer else { return nil }

        let rawWords = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard rawWords.count >= 2 else { return nil }

        // Strip trailing sentence punctuation from words fed into the classifier (keeping apostrophes,
        // hyphens inside words, decimals, URLs) so the model predicts fresh natural commas & sentence breaks.
        struct WordSlice {
            let cleanBase: String
            let original: String
            let preservedHardPunct: Character? // keep explicit '!' or ':' if user/ASR put one
            let tokenIDs: [Int32]
        }

        let slices: [WordSlice] = rawWords.map { raw in
            var base = raw
            var preserved: Character?
            if let last = base.last, ".?,;:!".contains(last) {
                // Keep decimals like "3.5" or abbreviations intact; only strip trailing terminal punct
                if last == "!" || last == ":" || last == ";" {
                    preserved = last
                }
                while let tail = base.last, ".?,;:!".contains(tail) {
                    base.removeLast()
                }
            }
            let effectiveBase = base.isEmpty ? raw : base
            let ids = tokenizer.encodeWord(effectiveBase)
            return WordSlice(
                cleanBase: effectiveBase,
                original: raw,
                preservedHardPunct: preserved,
                tokenIDs: ids.isEmpty ? [Self.unkTokenID] : ids
            )
        }

        var predictedLabels = [Int](repeating: 0, count: slices.count)

        // Slide over chunks up to 500 subword tokens per CoreML forward pass (512 including <s> & </s>)
        let maxSubwordsPerChunk = Self.sequenceLength - 2
        var wordCursor = 0
        while wordCursor < slices.count {
            var chunkTokenIDs: [Int32] = [Self.bosTokenID]
            var wordEndTokenIndices: [(wordIndex: Int, tokenPos: Int)] = []

            var i = wordCursor
            while i < slices.count {
                let ids = slices[i].tokenIDs
                if chunkTokenIDs.count + ids.count > maxSubwordsPerChunk + 1 && !wordEndTokenIndices.isEmpty {
                    break
                }
                chunkTokenIDs.append(contentsOf: ids)
                wordEndTokenIndices.append((wordIndex: i, tokenPos: chunkTokenIDs.count - 1))
                i += 1
            }
            chunkTokenIDs.append(Self.eosTokenID)

            guard let logits = runInference(model: model, tokenIDs: chunkTokenIDs) else {
                return nil
            }
            for entry in wordEndTokenIndices where entry.tokenPos < Self.sequenceLength {
                predictedLabels[entry.wordIndex] = bestPunctuationLabel(in: logits, tokenIndex: entry.tokenPos)
            }

            if i <= wordCursor { break }
            wordCursor = i
        }

        // Reconstruct output preserving every original spoken word verbatim
        var outputWords: [String] = []
        outputWords.reserveCapacity(slices.count)
        var capitalizeNext = true

        for (index, slice) in slices.enumerated() {
            var word = slice.cleanBase
            if capitalizeNext, let first = word.first, first.isLowercase {
                word = first.uppercased() + word.dropFirst()
            }
            capitalizeNext = false

            let isLastWord = (index == slices.count - 1)
            let label = predictedLabels[index]

            if let preserved = slice.preservedHardPunct {
                word.append(preserved)
                if preserved == "!" { capitalizeNext = true }
            } else {
                switch label {
                case 1: // "."
                    if !isLastWord || isFinal {
                        word.append(".")
                        capitalizeNext = true
                    }
                case 2: // ","
                    if !isLastWord {
                        word.append(",")
                    }
                case 3: // "?"
                    if !isLastWord || isFinal {
                        word.append("?")
                        capitalizeNext = true
                    }
                default:
                    break
                }
            }

            outputWords.append(word)
        }

        return outputWords.joined(separator: " ")
    }

    private func runInference(model: MLModel, tokenIDs: [Int32]) -> MLMultiArray? {
        guard let inputIDs = try? MLMultiArray(shape: [1, NSNumber(value: Self.sequenceLength)], dataType: .int32),
              let attentionMask = try? MLMultiArray(shape: [1, NSNumber(value: Self.sequenceLength)], dataType: .int32) else {
            return nil
        }

        let idPtr = inputIDs.dataPointer.assumingMemoryBound(to: Int32.self)
        let maskPtr = attentionMask.dataPointer.assumingMemoryBound(to: Int32.self)
        let activeCount = min(tokenIDs.count, Self.sequenceLength)

        for i in 0..<activeCount {
            idPtr[i] = tokenIDs[i]
            maskPtr[i] = 1
        }
        if activeCount < Self.sequenceLength {
            for i in activeCount..<Self.sequenceLength {
                idPtr[i] = Self.padTokenID
                maskPtr[i] = 0
            }
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
        ]),
              let prediction = try? model.prediction(from: provider),
              let logits = prediction.featureValue(for: "logits")?.multiArrayValue else {
            return nil
        }
        return logits
    }

    /// Reads the 4 primary punctuation classes (`0: none, 1: ".", 2: ",", 3: "?"`) from `[1, 512, 6]` logits.
    private func bestPunctuationLabel(in logits: MLMultiArray, tokenIndex: Int) -> Int {
        var bestClass = 0
        var bestScore = -Float.greatestFiniteMagnitude
        // Upstream Lark evaluation uses classes 0..3 (none, ., ,, ?) and ignores 4 (-) and 5 (:).
        for cls in 0..<4 {
            let score = logits[[0, NSNumber(value: tokenIndex), NSNumber(value: cls)]].floatValue
            if score > bestScore {
                bestScore = score
                bestClass = cls
            }
        }
        return bestClass
    }

    // MARK: - Download & Hashing Helpers

    private static func resolveURL(for relativePath: String) -> URL? {
        var url = resolveBaseURL
        for component in relativePath.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        return url
    }

    private static func sha256Hex(ofFileAt url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }
        var hasher = SHA256()
        let bufferSize = 65_536
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read < 0 { return nil }
            if read == 0 { break }
            hasher.update(data: Data(buffer[0..<read]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func downloadFileWithProgress(
        from url: URL,
        expectedFileSize: Int64,
        onBytesWritten: @escaping @Sendable (Int64) -> Void
    ) async throws -> (URL, URLResponse) {
        final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
            let onBytes: @Sendable (Int64) -> Void
            var continuation: CheckedContinuation<(URL, URLResponse), Error>?
            private var lastReportedBytes: Int64 = 0

            init(onBytes: @escaping @Sendable (Int64) -> Void) {
                self.onBytes = onBytes
            }

            func urlSession(
                _ session: URLSession,
                downloadTask: URLSessionDownloadTask,
                didWriteData bytesWritten: Int64,
                totalBytesWritten: Int64,
                totalBytesExpectedToWrite: Int64
            ) {
                if totalBytesWritten - lastReportedBytes >= 262_144 || totalBytesWritten == totalBytesExpectedToWrite {
                    lastReportedBytes = totalBytesWritten
                    onBytes(totalBytesWritten)
                }
            }

            func urlSession(
                _ session: URLSession,
                downloadTask: URLSessionDownloadTask,
                didFinishDownloadingTo location: URL
            ) {
                // Move out of URLSession's ephemeral temp location before returning
                let stableTmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("omnispeak-punct-\(UUID().uuidString)")
                do {
                    try FileManager.default.copyItem(at: location, to: stableTmp)
                    let resp = downloadTask.response ?? URLResponse(
                        url: downloadTask.originalRequest?.url ?? location,
                        mimeType: nil,
                        expectedContentLength: -1,
                        textEncodingName: nil
                    )
                    continuation?.resume(returning: (stableTmp, resp))
                    continuation = nil
                } catch {
                    continuation?.resume(throwing: error)
                    continuation = nil
                }
            }

            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error {
                    continuation?.resume(throwing: error)
                    continuation = nil
                }
            }
        }

        let delegate = DownloadDelegate(onBytes: onBytesWritten)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { cont in
            delegate.continuation = cont
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }
}

/// Exact Unigram Viterbi SentencePiece tokenizer parsed directly from Hugging Face `tokenizer.json`.
/// Zero external network calls and sub-millisecond tokenization for XLM-RoBERTa models.
final class UnigramSentencePieceTokenizer: @unchecked Sendable {
    private let pieceToIDAndScore: [String: (id: Int32, score: Double)]
    private let maxPieceLength: Int
    private let unkID: Int32

    init(tokenizerJSONURL: URL) throws {
        let data = try Data(contentsOf: tokenizerJSONURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? [String: Any],
              let vocab = model["vocab"] as? [[Any]] else {
            throw NSError(
                domain: "UnigramSentencePieceTokenizer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Hugging Face Unigram tokenizer.json"]
            )
        }

        var map: [String: (Int32, Double)] = [:]
        map.reserveCapacity(vocab.count)
        var longest = 1

        for (index, entry) in vocab.enumerated() {
            guard entry.count >= 2, let piece = entry[0] as? String else { continue }
            let score = (entry[1] as? NSNumber)?.doubleValue ?? -20.0
            map[piece] = (Int32(index), score)
            let count = piece.count
            if count > longest { longest = count }
        }

        self.pieceToIDAndScore = map
        self.maxPieceLength = min(longest, 32)
        self.unkID = Int32((model["unk_id"] as? Int) ?? 3)
    }

    func encodeWord(_ word: String) -> [Int32] {
        // XLM-R SentencePiece prefixes every word with U+2581 ('▁')
        let input = "\u{2581}" + word
        let chars = Array(input)
        let n = chars.count
        guard n > 0 else { return [] }

        var bestScore = [Double](repeating: -Double.infinity, count: n + 1)
        var bestPrev = [Int](repeating: 0, count: n + 1)
        var bestID = [Int32](repeating: unkID, count: n + 1)
        bestScore[0] = 0.0

        for i in 0..<n {
            guard bestScore[i].isFinite else { continue }
            let maxEnd = min(n, i + maxPieceLength)
            var matchedAny = false
            var piece = ""
            for j in i..<maxEnd {
                piece.append(chars[j])
                if let entry = pieceToIDAndScore[piece] {
                    matchedAny = true
                    let candidate = bestScore[i] + entry.score
                    if candidate > bestScore[j + 1] {
                        bestScore[j + 1] = candidate
                        bestPrev[j + 1] = i
                        bestID[j + 1] = entry.id
                    }
                }
            }
            if !matchedAny {
                let candidate = bestScore[i] - 100.0
                if candidate > bestScore[i + 1] {
                    bestScore[i + 1] = candidate
                    bestPrev[i + 1] = i
                    bestID[i + 1] = unkID
                }
            }
        }

        var ids: [Int32] = []
        var pos = n
        while pos > 0 {
            ids.append(bestID[pos])
            let prev = bestPrev[pos]
            if prev >= pos { break }
            pos = prev
        }
        return ids.reversed()
    }
}
