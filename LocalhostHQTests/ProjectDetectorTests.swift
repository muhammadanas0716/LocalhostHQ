import Testing
@testable import LocalhostHQ

@Suite("Project detection")
struct ProjectDetectorTests {

    /// The canonical monorepo from the spec:
    /// ```
    /// repo/.git, repo/pnpm-workspace.yaml, repo/apps/web/package.json
    /// ```
    private func monorepo() -> FakeFileSystem {
        var fs = FakeFileSystem()
        fs.addDirectory("/Users/dev/Code/dicee/.git")
        fs.addFile("/Users/dev/Code/dicee/pnpm-workspace.yaml", contents: "packages:\n  - apps/*")
        fs.addFile("/Users/dev/Code/dicee/package.json", contents: #"{"name":"dicee"}"#)
        fs.addFile("/Users/dev/Code/dicee/apps/web/package.json", contents: #"{"name":"@dicee/web"}"#)
        fs.addFile("/Users/dev/Code/dicee/apps/api/package.json", contents: #"{"name":"@dicee/api"}"#)
        return fs
    }

    @Test("Monorepo keeps package root and repository root distinct")
    func monorepoRoots() {
        let detector = ProjectDetector(fileSystem: monorepo(), homeDirectory: "/Users/dev")
        let context = detector.detect(workingDirectory: "/Users/dev/Code/dicee/apps/web")

        #expect(context?.packageRoot == "/Users/dev/Code/dicee/apps/web")
        #expect(context?.repositoryRoot == "/Users/dev/Code/dicee")
        #expect(context?.workingDirectory == "/Users/dev/Code/dicee/apps/web")
    }

    @Test("Sibling packages resolve to the same repository")
    func siblingsShareRepository() {
        let detector = ProjectDetector(fileSystem: monorepo(), homeDirectory: "/Users/dev")
        let web = detector.detect(workingDirectory: "/Users/dev/Code/dicee/apps/web")
        let api = detector.detect(workingDirectory: "/Users/dev/Code/dicee/apps/api")

        #expect(web?.repositoryRoot == api?.repositoryRoot)
        #expect(web?.packageRoot != api?.packageRoot)
    }

    @Test("A single-package repository reports the same path for both roots")
    func singlePackageRepository() {
        var fs = FakeFileSystem()
        fs.addDirectory("/Users/dev/Code/blog/.git")
        fs.addFile("/Users/dev/Code/blog/package.json", contents: #"{"name":"blog"}"#)

        let detector = ProjectDetector(fileSystem: fs, homeDirectory: "/Users/dev")
        let context = detector.detect(workingDirectory: "/Users/dev/Code/blog")

        #expect(context?.packageRoot == "/Users/dev/Code/blog")
        #expect(context?.repositoryRoot == "/Users/dev/Code/blog")
    }

    @Test("Running from a subdirectory still finds the package above it")
    func subdirectoryWalksUp() {
        var fs = FakeFileSystem()
        fs.addDirectory("/Users/dev/Code/api/.git")
        fs.addFile("/Users/dev/Code/api/pyproject.toml", contents: "[project]\nname = \"api\"")

        let detector = ProjectDetector(fileSystem: fs, homeDirectory: "/Users/dev")
        let context = detector.detect(workingDirectory: "/Users/dev/Code/api/src/handlers")

        #expect(context?.packageRoot == "/Users/dev/Code/api")
        #expect(context?.workingDirectory == "/Users/dev/Code/api/src/handlers")
    }

    @Test("The outermost repository wins, so nested packages group together")
    func outermostRepositoryWins() {
        var fs = FakeFileSystem()
        fs.addDirectory("/Users/dev/Code/outer/.git")
        fs.addFile("/Users/dev/Code/outer/package.json", contents: #"{"name":"outer"}"#)
        fs.addFile("/Users/dev/Code/outer/nested/package.json", contents: #"{"name":"nested"}"#)

        let detector = ProjectDetector(fileSystem: fs, homeDirectory: "/Users/dev")
        let context = detector.detect(workingDirectory: "/Users/dev/Code/outer/nested")

        #expect(context?.packageRoot == "/Users/dev/Code/outer/nested")
        #expect(context?.repositoryRoot == "/Users/dev/Code/outer")
    }

    @Test("A directory with no markers is not a project")
    func noMarkersIsNotAProject() {
        var fs = FakeFileSystem()
        fs.addDirectory("/Users/dev/Downloads/scratch")

        let detector = ProjectDetector(fileSystem: fs, homeDirectory: "/Users/dev")
        #expect(detector.detect(workingDirectory: "/Users/dev/Downloads/scratch") == nil)
    }

    @Test("A dotfiles repository in $HOME never becomes the project root")
    func homeDirectoryIsNotARepository() {
        var fs = FakeFileSystem()
        fs.addDirectory("/Users/dev/.git")
        fs.addDirectory("/Users/dev/scratch")

        let detector = ProjectDetector(fileSystem: fs, homeDirectory: "/Users/dev")
        #expect(detector.detect(workingDirectory: "/Users/dev/scratch") == nil)
    }

    @Test("A nonexistent working directory yields nothing")
    func missingDirectory() {
        let detector = ProjectDetector(fileSystem: FakeFileSystem(), homeDirectory: "/Users/dev")
        #expect(detector.detect(workingDirectory: "/no/such/place") == nil)
    }

    @Test("A worktree's .git file is recognised as well as a .git directory")
    func gitFileWorktree() {
        var fs = FakeFileSystem()
        fs.addFile("/Users/dev/Code/wt/.git", contents: "gitdir: /Users/dev/Code/main/.git/worktrees/wt")
        fs.addFile("/Users/dev/Code/wt/Cargo.toml", contents: "[package]\nname = \"wt\"")

        let detector = ProjectDetector(fileSystem: fs, homeDirectory: "/Users/dev")
        #expect(detector.detect(workingDirectory: "/Users/dev/Code/wt")?.repositoryRoot == "/Users/dev/Code/wt")
    }

    @Test("Trailing slashes are normalised away")
    func normalisesTrailingSlash() {
        var fs = FakeFileSystem()
        fs.addFile("/Users/dev/Code/app/go.mod", contents: "module github.com/dev/app")

        let detector = ProjectDetector(fileSystem: fs, homeDirectory: "/Users/dev")
        #expect(detector.detect(workingDirectory: "/Users/dev/Code/app/")?.packageRoot == "/Users/dev/Code/app")
    }

    @Test("Marker files at the package root are collected for detection")
    func collectsMarkerFiles() {
        var fs = FakeFileSystem()
        fs.addDirectory("/Users/dev/Code/site/.git")
        fs.addFile("/Users/dev/Code/site/package.json", contents: #"{"name":"site"}"#)
        fs.addFile("/Users/dev/Code/site/next.config.js", contents: "module.exports = {}")

        let detector = ProjectDetector(fileSystem: fs, homeDirectory: "/Users/dev")
        let markers = detector.detect(workingDirectory: "/Users/dev/Code/site")?.markerFiles ?? []

        #expect(markers.contains("next.config.js"))
        #expect(markers.contains("package.json"))
    }
}

@Suite("Project naming")
struct ProjectNamingTests {

    @Test("A scoped npm name displays as its last segment")
    func scopedPackageName() {
        let manifest = ProjectManifest(kind: .packageJSON, path: "/p/package.json",
                                       declaredName: "@dicee/web", dependencies: [])
        #expect(manifest.friendlyName == "web")
        // The raw name is preserved for the inspector.
        #expect(manifest.declaredName == "@dicee/web")
    }

    @Test("An unscoped name is used as-is")
    func plainPackageName() {
        let manifest = ProjectManifest(kind: .packageJSON, path: "/p/package.json",
                                       declaredName: "portfolio", dependencies: [])
        #expect(manifest.friendlyName == "portfolio")
    }

    @Test("Manifest name outranks the directory name")
    func manifestNameWins() {
        let context = ProjectContext(
            workingDirectory: "/Users/dev/Code/dicee/apps/web",
            packageRoot: "/Users/dev/Code/dicee/apps/web",
            repositoryRoot: "/Users/dev/Code/dicee",
            manifest: ProjectManifest(kind: .packageJSON, path: "", declaredName: "@dicee/storefront", dependencies: []),
            markerFiles: []
        )
        #expect(context.displayName == "storefront")
    }

    @Test("Without a manifest the package directory names the service")
    func fallsBackToDirectory() {
        let context = ProjectContext(
            workingDirectory: "/Users/dev/Code/dicee/apps/web",
            packageRoot: "/Users/dev/Code/dicee/apps/web",
            repositoryRoot: "/Users/dev/Code/dicee",
            manifest: nil,
            markerFiles: []
        )
        #expect(context.displayName == "web")
        #expect(context.repositoryName == "dicee")
    }
}
