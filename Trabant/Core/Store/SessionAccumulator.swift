import Foundation

/// Thread-safe accumulator that batches proxy session callbacks from NIO threads
/// and delivers them to CaptureStore in a single main-actor task per interval.
/// This eliminates per-session Task { @MainActor in } creation, reducing main-actor
/// executor contention under heavy load.
final class SessionAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingCaptures: [ProxySession] = []
    private var pendingUpdates: [ProxySession] = []
    private var flushScheduled = false
    private let store: CaptureStore

    init(store: CaptureStore) {
        self.store = store
    }

    func captured(_ session: ProxySession) {
        lock.lock()
        pendingCaptures.append(session)
        let needsSchedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        if needsSchedule { scheduleFlush() }
    }

    func updated(_ session: ProxySession) {
        lock.lock()
        if let idx = pendingCaptures.firstIndex(where: { $0.id == session.id }) {
            pendingCaptures[idx] = session
            lock.unlock()
            return
        }
        if let idx = pendingUpdates.firstIndex(where: { $0.id == session.id }) {
            pendingUpdates[idx] = session
        } else {
            pendingUpdates.append(session)
        }
        let needsSchedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        if needsSchedule { scheduleFlush() }
    }

    private func scheduleFlush() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.flush()
        }
    }

    @MainActor
    private func flush() {
        lock.lock()
        let captures = pendingCaptures
        let updates = pendingUpdates
        pendingCaptures.removeAll(keepingCapacity: true)
        pendingUpdates.removeAll(keepingCapacity: true)
        flushScheduled = false
        lock.unlock()

        guard !captures.isEmpty || !updates.isEmpty else { return }

        for session in captures {
            store.addSession(session)
        }
        for session in updates {
            store.updateSession(session)
        }
        store.flushPendingChanges()
    }
}
