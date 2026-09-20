import Foundation
import Observation

/// Observable log state for one service.
///
/// `@MainActor` because SwiftUI observes it directly. Writes arrive already
/// batched from `ProcessOutputCapture`, so a burst of output costs one state
/// mutation rather than one per line — the difference between a smooth log
/// viewer and an unusable one.
@MainActor
@Observable
final class LogStore {
    let key: ServiceKey
    private(set) var source: LogSource
    private(set) var entries: [LogEntry] = []
    private(set) var droppedCount: UInt64 = 0
    /// Most recent recognised failure, if any.
    private(set) var diagnosis: LogDiagnosis?

    private var buffer: LogBuffer
    private let classifier = LogClassifier()
    private var nextID: UInt64 = 0

    init(key: ServiceKey, source: LogSource = .unavailable, capacity: Int = LogBuffer.defaultCapacity) {
        self.key = key
        self.source = source
        self.buffer = LogBuffer(capacity: capacity)
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Lines that classified as errors, newest last.
    var errorEntries: [LogEntry] { entries.filter { $0.level == .error } }

    func setSource(_ source: LogSource) {
        self.source = source
    }

    /// Appends a batch of raw lines. One published mutation per batch.
    func append(lines: [String], stream: LogStream, at timestamp: Date = Date()) {
        guard !lines.isEmpty else { return }

        var batch: [LogEntry] = []
        batch.reserveCapacity(lines.count)
        for line in lines {
            batch.append(
                LogEntry(
                    id: nextID,
                    timestamp: timestamp,
                    stream: stream,
                    message: line,
                    level: classifier.level(of: line, stream: stream)
                )
            )
            nextID += 1
        }

        buffer.append(contentsOf: batch)
        entries = buffer.entries
        droppedCount = buffer.droppedCount

        if let found = classifier.diagnose(batch.map(\.message)) {
            diagnosis = found
        }
    }

    /// Notes a lifecycle moment inline, so the log reads as a continuous story
    /// across restarts rather than silently resetting.
    func appendNotice(_ text: String) {
        append(lines: ["— \(text) —"], stream: .stdout)
    }

    func clear() {
        buffer.removeAll()
        entries = []
        droppedCount = buffer.droppedCount
        diagnosis = nil
    }

    /// Case-insensitive substring filter.
    func filtered(query: String, levels: Set<LogLevel>?) -> [LogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { entry in
            if let levels, let level = entry.level, !levels.contains(level) { return false }
            if let levels, entry.level == nil, !levels.isEmpty { return false }
            guard !trimmed.isEmpty else { return true }
            return entry.message.lowercased().contains(trimmed)
        }
    }
}

/// Owns one `LogStore` per logical service.
///
/// Keyed by `ServiceKey` rather than PID, so a restart continues the same log
/// rather than starting a new one.
@MainActor
@Observable
final class LogManager {
    private var stores: [ServiceKey: LogStore] = [:]

    /// Existing store for a service, or a new empty one.
    func store(for key: ServiceKey) -> LogStore {
        if let existing = stores[key] { return existing }
        let created = LogStore(key: key)
        stores[key] = created
        return created
    }

    func existingStore(for key: ServiceKey) -> LogStore? { stores[key] }

    /// Moves a store to a new key, for a service that came back on a different
    /// port. Preserves the log across the change.
    func rekey(from old: ServiceKey, to new: ServiceKey) {
        guard old != new, let store = stores.removeValue(forKey: old) else { return }
        let merged = LogStore(key: new, source: store.source)
        merged.append(lines: store.entries.map(\.message), stream: .stdout)
        stores[new] = merged
    }

    func hasLiveLogs(for key: ServiceKey) -> Bool {
        stores[key]?.source.isLive ?? false
    }

    func removeAll() { stores.removeAll() }
}
