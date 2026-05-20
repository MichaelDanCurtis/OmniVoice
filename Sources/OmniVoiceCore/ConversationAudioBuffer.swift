import Foundation

public struct ConversationAudioBuffer: Equatable, Sendable {
    private struct Chunk: Equatable, Sendable {
        let startMs: Int
        let endMs: Int
        let sampleRate: Int
        let data: Data

        var frameCount: Int {
            data.count / MemoryLayout<Float>.size
        }
    }

    private let maxDurationMs: Int
    private var chunks: [Chunk]
    private var nextStartMs: Int

    public init(maxDurationMs: Int = 300_000) {
        self.maxDurationMs = maxDurationMs
        self.chunks = []
        self.nextStartMs = 0
    }

    public var durationMs: Int {
        nextStartMs
    }

    public mutating func reset() {
        chunks = []
        nextStartMs = 0
    }

    public mutating func appendPCMFloat32(_ data: Data, sampleRate: Int) {
        guard sampleRate > 0 else { return }
        let alignedCount = data.count - (data.count % MemoryLayout<Float>.size)
        guard alignedCount > 0 else { return }

        let aligned = data.count == alignedCount ? data : data.prefixData(alignedCount)
        let frameCount = aligned.count / MemoryLayout<Float>.size
        let durationMs = max(1, Int((Double(frameCount) / Double(sampleRate) * 1_000).rounded()))
        let chunk = Chunk(
            startMs: nextStartMs,
            endMs: nextStartMs + durationMs,
            sampleRate: sampleRate,
            data: aligned
        )
        chunks.append(chunk)
        nextStartMs = chunk.endMs
        pruneOldChunks()
    }

    public func audioPCMFloat32(from startMs: Int, to endMs: Int?) -> Data? {
        let lowerBound = max(0, startMs)
        let upperBound = max(lowerBound, endMs ?? nextStartMs)
        guard upperBound > lowerBound else { return nil }

        var result = Data()
        for chunk in chunks {
            let overlapStart = max(lowerBound, chunk.startMs)
            let overlapEnd = min(upperBound, chunk.endMs)
            guard overlapEnd > overlapStart else { continue }

            let startFrame = frameOffset(for: overlapStart - chunk.startMs, sampleRate: chunk.sampleRate, roundedUp: false)
            let endFrame = frameOffset(for: overlapEnd - chunk.startMs, sampleRate: chunk.sampleRate, roundedUp: true)
            let clampedStartFrame = min(max(0, startFrame), chunk.frameCount)
            let clampedEndFrame = min(max(clampedStartFrame, endFrame), chunk.frameCount)
            guard clampedEndFrame > clampedStartFrame else { continue }

            let byteStart = clampedStartFrame * MemoryLayout<Float>.size
            let byteEnd = clampedEndFrame * MemoryLayout<Float>.size
            result.append(chunk.data.subdata(in: byteStart..<byteEnd))
        }

        return result.isEmpty ? nil : result
    }

    private func frameOffset(for deltaMs: Int, sampleRate: Int, roundedUp: Bool) -> Int {
        let frames = Double(deltaMs) / 1_000 * Double(sampleRate)
        return Int(roundedUp ? frames.rounded(.up) : frames.rounded(.down))
    }

    private mutating func pruneOldChunks() {
        let cutoff = max(0, nextStartMs - maxDurationMs)
        chunks.removeAll { $0.endMs < cutoff }
    }
}

private extension Data {
    func prefixData(_ count: Int) -> Data {
        subdata(in: startIndex..<index(startIndex, offsetBy: count))
    }
}
