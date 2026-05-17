import Foundation

struct EngineStreamingConnectionToken: Equatable, Sendable {
    fileprivate let id: UUID
}

final class EngineStreamingConnectionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var currentID: UUID?

    func start() -> EngineStreamingConnectionToken {
        let id = UUID()
        lock.lock()
        currentID = id
        lock.unlock()
        return EngineStreamingConnectionToken(id: id)
    }

    func clear(_ token: EngineStreamingConnectionToken) {
        lock.lock()
        if currentID == token.id {
            currentID = nil
        }
        lock.unlock()
    }

    func isCurrent(_ token: EngineStreamingConnectionToken) -> Bool {
        lock.lock()
        let isCurrent = currentID == token.id
        lock.unlock()
        return isCurrent
    }
}
