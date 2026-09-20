import Foundation

/// Ordering of dashboard sections: repositories first, then loose dev servers,
/// then infrastructure, then anything belonging to macOS itself.
enum ServiceGroupKind: Int, Sendable, Hashable, Comparable {
    case repository = 0
    case development = 1
    case infrastructure = 2
    case system = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A dashboard section.
struct ServiceGroup: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let kind: ServiceGroupKind
    /// Repository path, for the header's secondary line. `nil` for synthetic
    /// groups, which are not real projects.
    let directory: String?
    let services: [LocalService]
}
