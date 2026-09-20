import Foundation

/// An in-flight control operation.
///
/// Modelled explicitly so the UI can disable controls for the duration. Without
/// this, four impatient clicks on Restart would start four overlapping restarts
/// of the same service.
struct ServiceOperation: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable, Hashable {
        case stopping
        case forceStopping
        case restarting

        var label: String {
            switch self {
            case .stopping: "Stopping…"
            case .forceStopping: "Force stopping…"
            case .restarting: "Restarting…"
            }
        }
    }

    let serviceKey: ServiceKey
    let kind: Kind
    let startedAt: Date

    var id: ServiceKey { serviceKey }
}

/// Offered when a graceful stop has not taken effect.
///
/// Escalation to SIGKILL is never automatic: the user is told what happened and
/// chooses. `remainingPIDs` is carried across so the escalation signals exactly
/// the processes that survived, rather than re-resolving a tree that has since
/// partly exited.
struct ForceStopPrompt: Identifiable, Sendable {
    let service: LocalService
    let remainingPIDs: [Int32]
    let waitedFor: Duration

    var id: ServiceKey { service.key }
}

/// Outcome of restarting several services at once.
struct ProjectOperationReport: Identifiable, Sendable {
    struct Item: Sendable, Hashable, Identifiable {
        let name: String
        let succeeded: Bool
        let detail: String?
        var id: String { name }
    }

    let id = UUID()
    let title: String
    let items: [Item]

    var succeededCount: Int { items.count(where: \.succeeded) }
    var failedCount: Int { items.count - succeededCount }
}
