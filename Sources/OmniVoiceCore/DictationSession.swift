import Foundation

public struct DictationSession: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case listening
        case cleaning
        case inserting
        case failed(String)
    }

    public private(set) var state: State
    public private(set) var partialTranscript: String
    public private(set) var finalTranscript: String
    public private(set) var finalTextToInsert: String

    public var canStartCapture: Bool {
        switch state {
        case .idle, .failed:
            true
        case .listening, .cleaning, .inserting:
            false
        }
    }

    public init(
        state: State = .idle,
        partialTranscript: String = "",
        finalTranscript: String = "",
        finalTextToInsert: String = ""
    ) {
        self.state = state
        self.partialTranscript = partialTranscript
        self.finalTranscript = finalTranscript
        self.finalTextToInsert = finalTextToInsert
    }

    public mutating func pressHotkey() {
        state = .listening
        partialTranscript = ""
        finalTranscript = ""
        finalTextToInsert = ""
    }

    public mutating func receivePartial(_ text: String) {
        guard state == .listening else { return }
        partialTranscript = text
    }

    public mutating func releaseHotkey(finalTranscript: String) {
        guard state == .listening else { return }
        self.finalTranscript = finalTranscript
        state = .cleaning
    }

    public mutating func finishCleanup(_ text: String) {
        guard state == .cleaning else { return }
        finalTextToInsert = text
        state = .inserting
    }

    public mutating func fail(_ message: String) {
        state = .failed(message)
    }

    public mutating func reset() {
        state = .idle
        partialTranscript = ""
        finalTranscript = ""
        finalTextToInsert = ""
    }
}
