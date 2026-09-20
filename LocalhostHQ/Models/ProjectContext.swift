import Foundation

/// A parsed project manifest.
struct ProjectManifest: Sendable, Hashable {
    enum Kind: String, Sendable, Hashable {
        case packageJSON
        case pyProject
        case requirements
        case pipfile
        case cargo
        case goModule
        case gemfile
        case compose

        /// Filenames that identify this manifest, most authoritative first.
        var filenames: [String] {
            switch self {
            case .packageJSON: ["package.json"]
            case .pyProject: ["pyproject.toml"]
            case .requirements: ["requirements.txt"]
            case .pipfile: ["Pipfile"]
            case .cargo: ["Cargo.toml"]
            case .goModule: ["go.mod"]
            case .gemfile: ["Gemfile"]
            case .compose: ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"]
            }
        }
    }

    let kind: Kind
    let path: String
    /// Name exactly as declared, e.g. `@dicee/web`.
    let declaredName: String?
    /// Declared dependency identifiers, lowercased.
    let dependencies: Set<String>

    /// Human-facing form of `declaredName`: scoped npm names collapse to their
    /// last segment, so `@dicee/web` shows as `web`.
    var friendlyName: String? {
        guard let declaredName, !declaredName.isEmpty else { return nil }
        if declaredName.hasPrefix("@"), let slash = declaredName.firstIndex(of: "/") {
            let tail = String(declaredName[declaredName.index(after: slash)...])
            return tail.isEmpty ? declaredName : tail
        }
        return declaredName
    }
}

/// Where a service lives on disk.
///
/// The three locations are kept distinct on purpose. In a monorepo they differ:
/// a server started in `~/Code/dicee/apps/web` has its package root there and
/// its repository root two levels up.
struct ProjectContext: Sendable, Hashable {
    /// The process's actual cwd.
    let workingDirectory: String
    /// Nearest enclosing directory holding a package manifest.
    let packageRoot: String?
    /// Outermost enclosing Git repository.
    let repositoryRoot: String?
    let manifest: ProjectManifest?
    /// Names of interesting files at `packageRoot`, used as detection signals.
    let markerFiles: Set<String>

    /// Directory the "Reveal in Finder" and "Open in Terminal" actions target:
    /// the package the service belongs to, falling back to its cwd.
    var primaryDirectory: String { packageRoot ?? workingDirectory }

    /// Repository folder name, used as the grouping title.
    var repositoryName: String? {
        repositoryRoot.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// Display name, in the priority the product calls for: manifest name,
    /// then package directory, then repository directory.
    var displayName: String? {
        if let friendly = manifest?.friendlyName { return friendly }
        if let packageRoot { return URL(fileURLWithPath: packageRoot).lastPathComponent }
        return repositoryName
    }
}
