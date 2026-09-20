import Testing
@testable import LocalhostHQ

@Suite("Framework detection")
struct FrameworkDetectorTests {
    private let detector = FrameworkDetector()

    private func nodeManifest(_ dependencies: [String], scripts: [String] = []) -> ProjectManifest {
        ProjectManifest(
            kind: .packageJSON,
            path: "/p/package.json",
            declaredName: "app",
            dependencies: Set((dependencies + scripts).map { $0.lowercased() })
        )
    }

    // MARK: - JavaScript

    @Test("Next.js from its dependency")
    func nextJS() {
        let context = DetectionContext(
            processName: "node",
            arguments: ["node", "server.js"],
            port: 3000,
            manifest: nodeManifest(["next", "react"])
        )
        #expect(detector.detect(in: context)?.framework == .nextJS)
    }

    /// Next.js rewrites its worker's process title, so the listening process
    /// shows no trace of the original command. This is the real-world case.
    @Test("Next.js from the rewritten process title alone")
    func nextJSFromProcessTitle() {
        let context = DetectionContext(
            processName: "node",
            arguments: ["next-server", "(v15.0.3)"],
            port: 3000
        )
        #expect(detector.detect(in: context)?.framework == .nextJS)
    }

    /// `npm run dev` leaves the real command only on the parent process.
    @Test("Next.js recovered from the parent's command line")
    func nextJSFromParent() {
        let context = DetectionContext(
            processName: "node",
            arguments: [],
            parentArguments: ["node", "node_modules/next/dist/bin/next", "dev", "-p", "3000"],
            port: 3000
        )
        #expect(detector.detect(in: context)?.framework == .nextJS)
    }

    @Test("Vite from its dependency")
    func vite() {
        let context = DetectionContext(
            processName: "node",
            arguments: ["vite"],
            port: 5173,
            manifest: nodeManifest(["vite"])
        )
        #expect(detector.detect(in: context)?.framework == .vite)
    }

    /// Nuxt, SvelteKit and Astro all depend on Vite; the meta-framework must win.
    @Test("Meta-frameworks outrank the bundler they embed", arguments: [
        (["nuxt", "vite"], Framework.nuxt),
        (["@sveltejs/kit", "vite"], Framework.svelteKit),
        (["astro", "vite"], Framework.astro),
    ])
    func metaFrameworksOutrankVite(dependencies: [String], expected: Framework) {
        let context = DetectionContext(
            processName: "node",
            port: 3000,
            manifest: nodeManifest(dependencies)
        )
        #expect(detector.detect(in: context)?.framework == expected)
    }

    @Test("NestJS from @nestjs/core")
    func nestJS() {
        let context = DetectionContext(
            processName: "node",
            arguments: ["node", "dist/main.js"],
            port: 3000,
            manifest: nodeManifest(["@nestjs/core", "express"])
        )
        #expect(detector.detect(in: context)?.framework == .nestJS)
    }

    @Test("Hono from its dependency")
    func hono() {
        let context = DetectionContext(
            processName: "node",
            port: 8787,
            manifest: nodeManifest(["hono"])
        )
        #expect(detector.detect(in: context)?.framework == .hono)
    }

    @Test("React dev server via react-scripts")
    func reactDevServer() {
        let context = DetectionContext(
            processName: "node",
            port: 3000,
            manifest: nodeManifest(["react-scripts", "react"])
        )
        #expect(detector.detect(in: context)?.framework == .reactDevServer)
    }

    @Test("Generic Node when nothing more specific matches")
    func genericNode() {
        let context = DetectionContext(
            processName: "node",
            arguments: ["node", "index.js"],
            port: 4000
        )
        let detection = detector.detect(in: context)
        #expect(detection?.framework == .node)
        #expect(detection?.framework.runtime == .node)
    }

    @Test("Bun from its process name")
    func bun() {
        let context = DetectionContext(processName: "bun", arguments: ["bun", "run", "dev"], port: 3000)
        #expect(detector.detect(in: context)?.framework == .bun)
    }

    // MARK: - Python

    @Test("Django from manage.py runserver")
    func django() {
        let context = DetectionContext(
            processName: "python3.12",
            arguments: ["python", "manage.py", "runserver"],
            port: 8000
        )
        #expect(detector.detect(in: context)?.framework == .django)
    }

    @Test("Flask from its dependency and command")
    func flask() {
        let context = DetectionContext(
            processName: "python3",
            arguments: ["flask", "run"],
            port: 5000,
            manifest: ProjectManifest(kind: .requirements, path: "/p/requirements.txt",
                                      declaredName: nil, dependencies: ["flask"])
        )
        #expect(detector.detect(in: context)?.framework == .flask)
    }

    @Test("A FastAPI app served by Uvicorn reads as FastAPI")
    func fastAPIOverUvicorn() {
        let context = DetectionContext(
            processName: "python3.12",
            arguments: ["uvicorn", "main:app", "--reload", "--port", "8000"],
            port: 8000,
            manifest: ProjectManifest(kind: .requirements, path: "/p/requirements.txt",
                                      declaredName: nil, dependencies: ["fastapi", "uvicorn"])
        )
        #expect(detector.detect(in: context)?.framework == .fastAPI)
    }

    @Test("Bare Uvicorn with no manifest still gets named")
    func bareUvicorn() {
        let context = DetectionContext(
            processName: "python3.12",
            arguments: ["uvicorn", "app:server"],
            port: 8000
        )
        #expect(detector.detect(in: context)?.framework == .uvicorn)
    }

    @Test("Jupyter from its command")
    func jupyter() {
        let context = DetectionContext(
            processName: "python3.12",
            arguments: ["python3", "-m", "jupyter", "lab"],
            port: 8888
        )
        let detection = detector.detect(in: context)
        #expect(detection?.framework == .jupyter)
        #expect(detection?.framework.category == .notebook)
    }

    @Test("Generic Python when nothing more specific matches")
    func genericPython() {
        let context = DetectionContext(
            processName: "python3.14",
            arguments: ["python3", "-m", "http.server", "8000"],
            port: 8000
        )
        #expect(detector.detect(in: context)?.framework == .python)
    }

    // MARK: - Other languages

    @Test("Rails from its gem")
    func rails() {
        let context = DetectionContext(
            processName: "ruby",
            arguments: ["puma"],
            port: 3000,
            manifest: ProjectManifest(kind: .gemfile, path: "/p/Gemfile",
                                      declaredName: nil, dependencies: ["rails", "puma"])
        )
        #expect(detector.detect(in: context)?.framework == .rails)
    }

    @Test("Rust from a cargo target binary")
    func rust() {
        let context = DetectionContext(
            processName: "my-server",
            executablePath: "/Users/dev/Code/my-server/target/debug/my-server",
            port: 8080,
            manifest: ProjectManifest(kind: .cargo, path: "/p/Cargo.toml",
                                      declaredName: "my-server", dependencies: ["axum"])
        )
        #expect(detector.detect(in: context)?.framework == .rust)
    }

    @Test("Go from its module manifest")
    func go() {
        let context = DetectionContext(
            processName: "server",
            executablePath: "/var/folders/xx/go-build123/b001/exe/server",
            port: 8080,
            manifest: ProjectManifest(kind: .goModule, path: "/p/go.mod",
                                      declaredName: "server", dependencies: [])
        )
        #expect(detector.detect(in: context)?.framework == .go)
    }

    // MARK: - Infrastructure

    @Test("Infrastructure services from their process names", arguments: [
        ("postgres", 5432, Framework.postgres, ServiceCategory.database),
        ("redis-server", 6379, Framework.redis, ServiceCategory.cache),
        ("mysqld", 3306, Framework.mysql, ServiceCategory.database),
        ("mongod", 27017, Framework.mongo, ServiceCategory.database),
    ])
    func infrastructure(name: String, port: Int, expected: Framework, category: ServiceCategory) {
        let context = DetectionContext(processName: name, port: port)
        let detection = detector.detect(in: context)
        #expect(detection?.framework == expected)
        #expect(detection?.framework.category == category)
        // Databases and caches must never offer a browser action.
        #expect(detection?.framework.servesHTTP == false)
    }

    @Test("Docker's backend is attributed to Docker")
    func docker() {
        let context = DetectionContext(processName: "com.docker.backend", port: 8080)
        #expect(detector.detect(in: context)?.framework == .docker)
    }

    // MARK: - Ranking behaviour

    @Test("A specific framework outranks the runtime baseline")
    func rankingOrder() {
        let context = DetectionContext(
            processName: "node",
            arguments: ["next-server"],
            port: 3000,
            manifest: nodeManifest(["next"])
        )
        let ranking = detector.ranked(in: context)

        #expect(ranking.first?.framework == .nextJS)
        #expect(ranking.contains { $0.framework == .node })
        let next = try? #require(ranking.first)
        #expect((next?.confidence ?? 0) > 0.9)
    }

    @Test("Confidence never reaches certainty")
    func confidenceIsBounded() {
        let context = DetectionContext(
            processName: "node",
            arguments: ["next-server", "next", "dev", "next start"],
            port: 3000,
            manifest: nodeManifest(["next"])
        )
        let confidence = detector.detect(in: context)?.confidence ?? 0
        #expect(confidence <= 0.99)
        #expect(confidence > 0.9)
    }

    @Test("An unrecognisable process yields no framework")
    func noMatch() {
        let context = DetectionContext(processName: "some-unknown-daemon", port: 51234)
        #expect(detector.detect(in: context) == nil)
    }

    @Test("Ports alone are too weak to identify anything")
    func portAloneIsInsufficient() {
        // Port 5432 with no Postgres evidence must not be called Postgres.
        let context = DetectionContext(processName: "mystery", port: 5432)
        #expect(detector.detect(in: context) == nil)
    }
}
