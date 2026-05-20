import Foundation

public struct ConversationUpdateToken: Equatable, Sendable {
    public let generation: UUID

    public init(generation: UUID) {
        self.generation = generation
    }
}

public final class ConversationUpdateTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var activeGenerations: Set<UUID> = []
    private var counts: [UUID: Int] = [:]
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    public init() {}

    public func start(generation: UUID) {
        lock.lock()
        activeGenerations.insert(generation)
        counts[generation] = counts[generation] ?? 0
        waiters[generation] = waiters[generation] ?? []
        lock.unlock()
    }

    public func begin(generation: UUID) -> ConversationUpdateToken? {
        lock.lock()
        defer { lock.unlock() }

        guard activeGenerations.contains(generation) else {
            return nil
        }

        counts[generation, default: 0] += 1
        return ConversationUpdateToken(generation: generation)
    }

    public func end(_ token: ConversationUpdateToken) {
        let resumable = decrementAndTakeWaitersIfIdle(generation: token.generation)
        resumable.forEach { $0.resume() }
    }

    public func retire(generation: UUID) {
        let resumable: [CheckedContinuation<Void, Never>]
        lock.lock()
        activeGenerations.remove(generation)
        if counts[generation, default: 0] == 0 {
            resumable = waiters[generation] ?? []
            counts[generation] = nil
            waiters[generation] = nil
        } else {
            resumable = []
        }
        lock.unlock()
        resumable.forEach { $0.resume() }
    }

    public func waitForIdle(generation: UUID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let shouldResume: Bool
            lock.lock()
            if counts[generation, default: 0] == 0 {
                shouldResume = true
            } else {
                shouldResume = false
                waiters[generation, default: []].append(continuation)
            }
            lock.unlock()

            if shouldResume {
                continuation.resume()
            }
        }
    }

    private func decrementAndTakeWaitersIfIdle(generation: UUID) -> [CheckedContinuation<Void, Never>] {
        lock.lock()
        guard let currentCount = counts[generation] else {
            lock.unlock()
            return []
        }

        let nextCount = max(0, currentCount - 1)
        counts[generation] = nextCount

        let resumable: [CheckedContinuation<Void, Never>]
        if nextCount == 0 {
            resumable = waiters[generation] ?? []
            waiters[generation] = []
            if !activeGenerations.contains(generation) {
                counts[generation] = nil
                waiters[generation] = nil
            }
        } else {
            resumable = []
        }

        lock.unlock()
        return resumable
    }
}
