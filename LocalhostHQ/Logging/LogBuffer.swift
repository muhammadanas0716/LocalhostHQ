import Foundation

/// Fixed-capacity FIFO of log entries.
///
/// A dev server can emit thousands of lines a second, so retention is bounded
/// and the oldest entries are dropped. Backed by a ring buffer: appending at
/// capacity overwrites one slot instead of shifting the whole array, which
/// would make heavy output quadratic.
struct LogBuffer: Sendable {
    static let defaultCapacity = 10_000

    private var storage: [LogEntry?]
    private var head = 0
    private(set) var count = 0
    /// Total ever appended, including entries since evicted.
    private(set) var totalAppended: UInt64 = 0

    let capacity: Int

    init(capacity: Int = LogBuffer.defaultCapacity) {
        self.capacity = max(1, capacity)
        self.storage = Array(repeating: nil, count: self.capacity)
    }

    /// True once entries have been evicted, so the UI can say so.
    var hasDroppedEntries: Bool { totalAppended > UInt64(capacity) }

    var droppedCount: UInt64 {
        hasDroppedEntries ? totalAppended - UInt64(capacity) : 0
    }

    mutating func append(_ entry: LogEntry) {
        storage[head] = entry
        head = (head + 1) % capacity
        count = Swift.min(count + 1, capacity)
        totalAppended += 1
    }

    mutating func append(contentsOf entries: [LogEntry]) {
        for entry in entries { append(entry) }
    }

    /// Entries in chronological order.
    var entries: [LogEntry] {
        guard count > 0 else { return [] }
        var result: [LogEntry] = []
        result.reserveCapacity(count)

        let start = (head - count + capacity) % capacity
        for offset in 0..<count {
            if let entry = storage[(start + offset) % capacity] { result.append(entry) }
        }
        return result
    }

    /// The most recent `limit` entries, chronologically.
    func suffix(_ limit: Int) -> [LogEntry] {
        Array(entries.suffix(max(0, limit)))
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
        // totalAppended is deliberately kept: it records the session's volume.
    }
}
