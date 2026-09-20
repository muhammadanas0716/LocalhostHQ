import Foundation

/// Locates the package and repository a working directory belongs to.
///
/// Walks upward from the cwd, recording two independent answers:
///
/// * **package root** — the *nearest* ancestor with a package manifest, so a
///   monorepo service resolves to `apps/web` rather than the repository.
/// * **repository root** — the *outermost* ancestor containing `.git`, so
///   sibling services in the same repo group together.
///
/// Both are kept because they genuinely differ, and collapsing them would lose
/// either the service's identity or its grouping.
struct ProjectDetector: Sendable {
    /// Files that mark a directory as a package root, most specific first.
    /// Order matters only for choosing which manifest to parse.
    static let packageMarkers: [String] = [
        "package.json",
        "pyproject.toml",
        "Cargo.toml",
        "go.mod",
        "Gemfile",
        "requirements.txt",
        "Pipfile",
        "docker-compose.yml",
        "docker-compose.yaml",
        "compose.yml",
        "compose.yaml",
    ]

    /// Markers that indicate a workspace *root* rather than a leaf package.
    /// A directory carrying one of these is never chosen as the package root
    /// when a nearer package.json exists below it.
    static let workspaceMarkers: Set<String> = [
        "pnpm-workspace.yaml",
        "lerna.json",
        "turbo.json",
        "rush.json",
    ]

    /// System directories the walk must never climb into.
    private static let systemRoots: Set<String> = [
        "/", "/Users", "/tmp", "/private", "/var", "/opt", "/usr", "/Applications", "/Library", "/System", "/Volumes",
    ]

    /// Depth limit, so a pathological path cannot spin the walk.
    private static let maximumDepth = 24

    private let fileSystem: FileSystemProbing
    /// The walk stops here. Many developers keep a dotfiles repository in their
    /// home directory; without this guard its `.git` would swallow every
    /// service into one bogus project.
    private let homeDirectory: String

    init(fileSystem: FileSystemProbing = LiveFileSystem(), homeDirectory: String = NSHomeDirectory()) {
        self.fileSystem = fileSystem
        self.homeDirectory = Self.normalize(homeDirectory)
    }

    func detect(workingDirectory: String) -> ProjectContext? {
        let normalized = Self.normalize(workingDirectory)
        guard fileSystem.directoryExists(atPath: normalized) else { return nil }

        var packageRoot: String?
        var repositoryRoot: String?

        var current = normalized
        var depth = 0
        while depth < Self.maximumDepth {
            defer { depth += 1 }

            if packageRoot == nil, hasPackageManifest(at: current) {
                packageRoot = current
            }
            // Keep climbing: the outermost .git wins, so a service inside a
            // submodule-free monorepo groups under the top-level repository.
            if fileSystem.directoryExists(atPath: current + "/.git")
                || fileSystem.fileExists(atPath: current + "/.git") {
                repositoryRoot = current
            }

            guard let parent = Self.parent(of: current), !isBoundary(parent) else { break }
            current = parent
        }

        // Nothing identifiable: the process just happens to run from some
        // directory. Not a project, and pretending otherwise creates fake ones.
        guard packageRoot != nil || repositoryRoot != nil else { return nil }

        let effectivePackageRoot = packageRoot
        let markerFiles = effectivePackageRoot.map { fileSystem.childNames(atPath: $0) } ?? []

        return ProjectContext(
            workingDirectory: normalized,
            packageRoot: effectivePackageRoot,
            repositoryRoot: repositoryRoot,
            manifest: nil,   // filled in by ManifestLoader
            markerFiles: markerFiles
        )
    }

    private func hasPackageManifest(at directory: String) -> Bool {
        Self.packageMarkers.contains { fileSystem.fileExists(atPath: directory + "/" + $0) }
    }

    // MARK: - Path helpers

    static func normalize(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }

    static func parent(of path: String) -> String? {
        guard path != "/", let slash = path.lastIndex(of: "/") else { return nil }
        let parent = String(path[path.startIndex..<slash])
        return parent.isEmpty ? "/" : parent
    }

    private func isBoundary(_ path: String) -> Bool {
        path == homeDirectory || Self.systemRoots.contains(path)
    }
}
