import Foundation

protocol GitInspecting: Sendable {
    /// `nil` when the directory is not inside a repository, or when git is
    /// unavailable. Never throws into the UI.
    func inspect(directory: String) async -> GitInfo?
}

/// Reads repository root and current HEAD by shelling out to `git`.
///
/// Libgit2 would avoid the subprocess, but `git` is already on every developer
/// Mac and one invocation answers both questions in ~10ms. Results are cached
/// upstream by repository path, so a steady-state refresh runs no git at all.
struct GitInspector: GitInspecting {
    /// Xcode's git shim, present whenever Command Line Tools are installed.
    private static let candidatePaths = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]

    private let runner: CommandRunning
    private let executablePath: String?

    init(runner: CommandRunning = Shell(), executablePath: String? = nil) {
        self.runner = runner
        self.executablePath = executablePath ?? Self.candidatePaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    func inspect(directory: String) async -> GitInfo? {
        guard let executablePath else { return nil }

        // One invocation yields both values: toplevel on the first line, the
        // symbolic ref (or literal "HEAD" when detached) on the second.
        let arguments = ["-C", directory, "rev-parse", "--show-toplevel", "--abbrev-ref", "HEAD"]
        guard let output = try? await runner.run(executablePath, arguments: arguments, timeout: .seconds(3)),
              output.succeeded
        else { return nil }

        let lines = output.standardOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let root = lines.first, !root.isEmpty else { return nil }
        let reference = lines.count > 1 ? lines[1] : "HEAD"

        if reference == "HEAD" {
            let sha = await shortSHA(directory: directory, executablePath: executablePath)
            return GitInfo(repositoryRoot: root, head: .detached(sha ?? "unknown"))
        }
        return GitInfo(repositoryRoot: root, head: .branch(reference))
    }

    private func shortSHA(directory: String, executablePath: String) async -> String? {
        let arguments = ["-C", directory, "rev-parse", "--short", "HEAD"]
        guard let output = try? await runner.run(executablePath, arguments: arguments, timeout: .seconds(3)),
              output.succeeded
        else { return nil }
        let sha = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }
}
