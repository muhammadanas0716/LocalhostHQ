import Foundation

/// What Localhost HQ may safely do to a service.
///
/// Computed once, from process ownership, control-root safety and launch
/// reconstructability. Views read these flags rather than re-deriving rules
/// from framework names, so a capability decision is made in exactly one place.
struct ServiceCapabilities: Sendable, Hashable {
    let canOpenInBrowser: Bool
    let canRevealInFinder: Bool
    let canStop: Bool
    let canForceStop: Bool
    let canRestart: Bool
    /// Whether logs can be *streamed*. Only true when Localhost HQ launched the
    /// process, because macOS offers no way to attach to the stdout of a
    /// process we did not start.
    let canStreamLogs: Bool

    /// Why stopping is unavailable, for the UI to explain rather than just
    /// greying a button out.
    let restriction: Restriction?

    enum Restriction: Sendable, Hashable {
        /// Owned by another user; signalling it would need root.
        case notOwnedByUser
        /// macOS denied the inspection needed to verify identity.
        case inspectionDenied
        /// It is macOS's own, or an installed app's.
        case systemService
        /// No control root could be established safely.
        case noSafeControlRoot

        var explanation: String {
            switch self {
            case .notOwnedByUser:
                "This process belongs to another user, so Localhost HQ cannot stop it without administrator rights."
            case .inspectionDenied:
                "macOS denied inspection of this process, so its identity cannot be verified before stopping it."
            case .systemService:
                "This service belongs to macOS or an installed app. Localhost HQ does not stop system services."
            case .noSafeControlRoot:
                "Localhost HQ could not determine which processes belong to this service, so it will not signal any of them."
            }
        }
    }

    static let none = ServiceCapabilities(
        canOpenInBrowser: false,
        canRevealInFinder: false,
        canStop: false,
        canForceStop: false,
        canRestart: false,
        canStreamLogs: false,
        restriction: nil
    )
}
