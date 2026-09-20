import Foundation

enum ServiceEventKind: String, Sendable, Hashable {
    case discovered
    case started
    case stopped
    case restarted
    case crashed
    case portConflict
    case operationFailed

    var symbolName: String {
        switch self {
        case .discovered: "sparkle"
        case .started: "play.fill"
        case .stopped: "stop.fill"
        case .restarted: "arrow.clockwise"
        case .crashed: "exclamationmark.triangle.fill"
        case .portConflict: "arrow.triangle.branch"
        case .operationFailed: "xmark.octagon.fill"
        }
    }

    var isProblem: Bool {
        switch self {
        case .crashed, .portConflict, .operationFailed: true
        case .discovered, .started, .stopped, .restarted: false
        }
    }
}

/// Something that happened to a service during this session.
///
/// Session-scoped and bounded: this is a debugging aid, not analytics, and
/// nothing is persisted.
struct ServiceEvent: Identifiable, Sendable, Hashable {
    let id: UUID
    let timestamp: Date
    let kind: ServiceEventKind
    let serviceKey: ServiceKey
    let serviceName: String
    let message: String

    init(
        kind: ServiceEventKind,
        serviceKey: ServiceKey,
        serviceName: String,
        message: String,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.kind = kind
        self.serviceKey = serviceKey
        self.serviceName = serviceName
        self.message = message
    }
}
