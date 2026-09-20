import Foundation

/// A small expiring cache.
///
/// Deliberately a `struct` with mutating access: every user lives inside an
/// actor, so the actor already provides the isolation and no extra locking is
/// warranted.
struct TimedCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private struct Entry {
        let value: Value
        let storedAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private let lifetime: TimeInterval

    init(lifetime: Duration) {
        self.lifetime = Double(lifetime.components.seconds)
            + Double(lifetime.components.attoseconds) / 1e18
    }

    subscript(key: Key, now now: Date = Date()) -> Value? {
        mutating get {
            guard let entry = entries[key] else { return nil }
            guard now.timeIntervalSince(entry.storedAt) < lifetime else {
                entries.removeValue(forKey: key)
                return nil
            }
            return entry.value
        }
    }

    mutating func insert(_ value: Value, for key: Key, now: Date = Date()) {
        entries[key] = Entry(value: value, storedAt: now)
    }

    /// Drops expired entries so long-lived caches do not grow without bound.
    mutating func purgeExpired(now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.storedAt) < lifetime }
    }

    /// Restricts the cache to the given keys. Used to evict metadata for
    /// services that are no longer running.
    mutating func retain(keys: Set<Key>) {
        entries = entries.filter { keys.contains($0.key) }
    }

    var count: Int { entries.count }
}
