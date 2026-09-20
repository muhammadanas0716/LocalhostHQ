import Foundation

/// Coarse role of a service. Drives grouping, sort order and which actions the
/// UI offers, so those checks live here rather than being re-derived in views.
enum ServiceCategory: String, Sendable, Hashable, CaseIterable {
    case web
    case api
    case database
    case cache
    case notebook
    case infrastructure
    case generic

    /// Where the service sorts on the dashboard.
    var groupKind: ServiceGroupKind {
        switch self {
        case .web, .api, .notebook, .generic: .development
        case .database, .cache, .infrastructure: .infrastructure
        }
    }
}

enum Runtime: String, Sendable, Hashable {
    case node
    case bun
    case deno
    case python
    case ruby
    case rust
    case go
    case java
    case native

    var displayName: String {
        switch self {
        case .node: "Node.js"
        case .bun: "Bun"
        case .deno: "Deno"
        case .python: "Python"
        case .ruby: "Ruby"
        case .rust: "Rust"
        case .go: "Go"
        case .java: "Java"
        case .native: "Native"
        }
    }
}

/// A framework, runtime or service that Localhost HQ can recognise.
struct Framework: Sendable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let category: ServiceCategory
    let runtime: Runtime?
    /// SF Symbol used as the row glyph.
    let symbolName: String
    /// Whether the service speaks HTTP, and so can be opened in a browser.
    /// Modelled here so no view has to special-case Postgres or Redis.
    let servesHTTP: Bool
}

// MARK: - Catalog

extension Framework {
    // JavaScript / TypeScript
    static let nextJS = Framework(id: "nextjs", displayName: "Next.js", category: .web, runtime: .node, symbolName: "triangle", servesHTTP: true)
    static let vite = Framework(id: "vite", displayName: "Vite", category: .web, runtime: .node, symbolName: "bolt", servesHTTP: true)
    static let reactDevServer = Framework(id: "cra", displayName: "React Dev Server", category: .web, runtime: .node, symbolName: "atom", servesHTTP: true)
    static let nuxt = Framework(id: "nuxt", displayName: "Nuxt", category: .web, runtime: .node, symbolName: "mountain.2", servesHTTP: true)
    static let svelteKit = Framework(id: "sveltekit", displayName: "SvelteKit", category: .web, runtime: .node, symbolName: "flame", servesHTTP: true)
    static let astro = Framework(id: "astro", displayName: "Astro", category: .web, runtime: .node, symbolName: "sparkles", servesHTTP: true)
    static let remix = Framework(id: "remix", displayName: "Remix", category: .web, runtime: .node, symbolName: "square.stack.3d.up", servesHTTP: true)
    static let express = Framework(id: "express", displayName: "Express", category: .api, runtime: .node, symbolName: "arrow.left.arrow.right", servesHTTP: true)
    static let hono = Framework(id: "hono", displayName: "Hono", category: .api, runtime: .node, symbolName: "flame.fill", servesHTTP: true)
    static let nestJS = Framework(id: "nestjs", displayName: "NestJS", category: .api, runtime: .node, symbolName: "cube.transparent", servesHTTP: true)
    static let node = Framework(id: "node", displayName: "Node.js", category: .generic, runtime: .node, symbolName: "hexagon", servesHTTP: true)
    static let bun = Framework(id: "bun", displayName: "Bun", category: .generic, runtime: .bun, symbolName: "takeoutbag.and.cup.and.straw", servesHTTP: true)
    static let deno = Framework(id: "deno", displayName: "Deno", category: .generic, runtime: .deno, symbolName: "drop", servesHTTP: true)

    // Python
    static let django = Framework(id: "django", displayName: "Django", category: .web, runtime: .python, symbolName: "square.grid.2x2", servesHTTP: true)
    static let flask = Framework(id: "flask", displayName: "Flask", category: .web, runtime: .python, symbolName: "testtube.2", servesHTTP: true)
    static let fastAPI = Framework(id: "fastapi", displayName: "FastAPI", category: .api, runtime: .python, symbolName: "bolt.horizontal", servesHTTP: true)
    static let uvicorn = Framework(id: "uvicorn", displayName: "Uvicorn", category: .api, runtime: .python, symbolName: "arrow.up.forward.app", servesHTTP: true)
    static let jupyter = Framework(id: "jupyter", displayName: "Jupyter", category: .notebook, runtime: .python, symbolName: "book.closed", servesHTTP: true)
    static let python = Framework(id: "python", displayName: "Python", category: .generic, runtime: .python, symbolName: "chevron.left.forwardslash.chevron.right", servesHTTP: true)

    // Other languages
    static let rails = Framework(id: "rails", displayName: "Rails", category: .web, runtime: .ruby, symbolName: "tram.fill", servesHTTP: true)
    static let rust = Framework(id: "rust", displayName: "Rust", category: .generic, runtime: .rust, symbolName: "gearshape.2", servesHTTP: true)
    static let go = Framework(id: "go", displayName: "Go", category: .generic, runtime: .go, symbolName: "hare", servesHTTP: true)

    // Infrastructure
    static let postgres = Framework(id: "postgres", displayName: "PostgreSQL", category: .database, runtime: .native, symbolName: "cylinder.split.1x2", servesHTTP: false)
    static let mysql = Framework(id: "mysql", displayName: "MySQL", category: .database, runtime: .native, symbolName: "cylinder.split.1x2", servesHTTP: false)
    static let mongo = Framework(id: "mongodb", displayName: "MongoDB", category: .database, runtime: .native, symbolName: "leaf", servesHTTP: false)
    static let redis = Framework(id: "redis", displayName: "Redis", category: .cache, runtime: .native, symbolName: "bolt.square", servesHTTP: false)
    static let docker = Framework(id: "docker", displayName: "Docker", category: .infrastructure, runtime: .native, symbolName: "shippingbox", servesHTTP: false)
    static let supabase = Framework(id: "supabase", displayName: "Supabase", category: .infrastructure, runtime: .native, symbolName: "bolt.circle", servesHTTP: true)
}

/// A framework guess with the confidence that produced it. Detection is
/// heuristic and the ranking matters, so confidence is part of the model even
/// though Part 1's UI only surfaces it in the debug inspector.
struct FrameworkDetection: Sendable, Hashable {
    let framework: Framework
    let confidence: Double
}
