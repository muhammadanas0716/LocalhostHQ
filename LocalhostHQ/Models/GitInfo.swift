import Foundation

struct GitInfo: Sendable, Hashable {
    enum Head: Sendable, Hashable {
        case branch(String)
        /// Detached HEAD, carrying the abbreviated object name.
        case detached(String)

        var displayName: String {
            switch self {
            case .branch(let name): name
            case .detached(let sha): "detached @ \(sha)"
            }
        }
    }

    let repositoryRoot: String
    let head: Head

    var branchName: String { head.displayName }

    var isDetached: Bool {
        if case .detached = head { return true }
        return false
    }
}
