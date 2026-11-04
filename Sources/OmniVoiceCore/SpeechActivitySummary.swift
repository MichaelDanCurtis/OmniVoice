import Foundation

public struct SpeechActivitySummary: Equatable, Sendable {
    public static let defaultActiveLevelThreshold: Float = 0.008
    public static let defaultSpeechPeakThreshold: Float = 0.02
    public static let defaultSpeechAverageThreshold: Float = 0.002
    public static let defaultSpeechActiveBufferRatio: Float = 0.04

    public private(set) var bufferCount: Int
    public private(set) var activeBufferCount: Int
    public private(set) var accumulatedLevel: Float
    public private(set) var peakLevel: Float

    public init(
        bufferCount: Int = 0,
        activeBufferCount: Int = 0,
        accumulatedLevel: Float = 0,
        peakLevel: Float = 0
    ) {
        self.bufferCount = bufferCount
        self.activeBufferCount = activeBufferCount
        self.accumulatedLevel = accumulatedLevel
        self.peakLevel = peakLevel
    }

    public var averageLevel: Float {
        guard bufferCount > 0 else { return 0 }
        return accumulatedLevel / Float(bufferCount)
    }

    public var activeBufferRatio: Float {
        guard bufferCount > 0 else { return 0 }
        return Float(activeBufferCount) / Float(bufferCount)
    }

    public mutating func observe(
        level: Float,
        activeLevelThreshold: Float = Self.defaultActiveLevelThreshold
    ) {
        let normalized = max(0, level)
        bufferCount += 1
        accumulatedLevel += normalized
        peakLevel = max(peakLevel, normalized)
        if normalized >= activeLevelThreshold {
            activeBufferCount += 1
        }
    }

    public func containsLikelySpeech(
        peakThreshold: Float = Self.defaultSpeechPeakThreshold,
        averageThreshold: Float = Self.defaultSpeechAverageThreshold,
        activeBufferRatioThreshold: Float = Self.defaultSpeechActiveBufferRatio
    ) -> Bool {
        guard bufferCount > 0 else { return false }
        return peakLevel >= peakThreshold
            || averageLevel >= averageThreshold
            || activeBufferRatio >= activeBufferRatioThreshold
    }
}
