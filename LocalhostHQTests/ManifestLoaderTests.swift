import Foundation
import Testing
@testable import LocalhostHQ

@Suite("Manifest parsing")
struct ManifestLoaderTests {

    private func loader(_ files: [String: String]) -> ManifestLoader {
        ManifestLoader(fileSystem: FakeFileSystem(files: files))
    }

    @Test("package.json name and dependencies")
    func packageJSON() {
        let manifest = loader([
            "/p/package.json": #"""
            {
              "name": "@dicee/web",
              "dependencies": { "next": "15.0.0", "react": "19.0.0" },
              "devDependencies": { "typescript": "5.6.0" }
            }
            """#,
        ]).load(packageRoot: "/p")

        #expect(manifest?.kind == .packageJSON)
        #expect(manifest?.declaredName == "@dicee/web")
        #expect(manifest?.friendlyName == "web")
        #expect(manifest?.dependencies.contains("next") == true)
        #expect(manifest?.dependencies.contains("typescript") == true)
    }

    /// In a monorepo the dependency is often hoisted out of the leaf package,
    /// leaving the dev script as the only local evidence.
    @Test("Scripts contribute detection tokens")
    func packageJSONScripts() {
        let manifest = loader([
            "/p/package.json": #"{"name":"site","scripts":{"dev":"next dev -p 3000"}}"#,
        ]).load(packageRoot: "/p")

        #expect(manifest?.dependencies.contains("next") == true)
    }

    @Test("Malformed JSON does not throw or crash")
    func malformedPackageJSON() {
        // A half-written file, as seen mid-save.
        let manifest = loader(["/p/package.json": #"{"name": "broken", "dep"#]).load(packageRoot: "/p")
        #expect(manifest == nil)
    }

    @Test("An empty manifest file is handled")
    func emptyFile() {
        #expect(loader(["/p/package.json": ""]).load(packageRoot: "/p") == nil)
    }

    @Test("package.json without a name still parses")
    func noName() {
        let manifest = loader([#"/p/package.json"#: #"{"dependencies":{"express":"4"}}"#]).load(packageRoot: "/p")
        #expect(manifest?.declaredName == nil)
        #expect(manifest?.friendlyName == nil)
        #expect(manifest?.dependencies.contains("express") == true)
    }

    @Test("pyproject.toml name")
    func pyProject() {
        let manifest = loader([
            "/p/pyproject.toml": """
            [project]
            name = "my-api"
            dependencies = ["fastapi", "uvicorn"]
            """,
        ]).load(packageRoot: "/p")

        #expect(manifest?.kind == .pyProject)
        #expect(manifest?.declaredName == "my-api")
        #expect(manifest?.dependencies.contains("fastapi") == true)
    }

    @Test("Commented-out TOML keys are ignored")
    func tomlComments() {
        let manifest = loader([
            "/p/Cargo.toml": """
            # name = "wrong"
            [package]
            name = "right"
            """,
        ]).load(packageRoot: "/p")

        #expect(manifest?.declaredName == "right")
    }

    @Test("go.mod reduces the module URL to its last segment")
    func goModule() {
        let manifest = loader([
            "/p/go.mod": """
            module github.com/dev/coolserver

            go 1.23
            """,
        ]).load(packageRoot: "/p")

        #expect(manifest?.kind == .goModule)
        #expect(manifest?.declaredName == "coolserver")
    }

    @Test("requirements.txt yields dependency tokens")
    func requirements() {
        let manifest = loader([
            "/p/requirements.txt": "Django==5.0.1\npsycopg2-binary==2.9.9\n",
        ]).load(packageRoot: "/p")

        #expect(manifest?.kind == .requirements)
        #expect(manifest?.dependencies.contains("django") == true)
    }

    @Test("package.json is preferred over other manifests in a polyglot root")
    func manifestPriority() {
        let manifest = loader([
            "/p/package.json": #"{"name":"js-app"}"#,
            "/p/requirements.txt": "flask",
        ]).load(packageRoot: "/p")

        #expect(manifest?.kind == .packageJSON)
        #expect(manifest?.declaredName == "js-app")
    }

    @Test("A directory with no manifest yields nothing")
    func noManifest() {
        #expect(loader([:]).load(packageRoot: "/p") == nil)
    }
}
