import Foundation

/// The detection knowledge base.
///
/// Adding support for a framework means adding one entry here — no other file
/// changes. Weights are calibrated so that a framework declared in a manifest
/// (0.9+) always outranks the runtime baseline it is built on (0.5), and so
/// that meta-frameworks outrank the bundler they embed: a Nuxt project also
/// depends on Vite, and must still read as Nuxt.
enum FrameworkCatalog {

    static let signatures: [FrameworkSignature] = javaScript + python + otherLanguages + infrastructure

    // MARK: - JavaScript / TypeScript

    private static let javaScript: [FrameworkSignature] = [
        FrameworkSignature(.nextJS, rules: [
            .dependency("next", 0.95),
            // Next.js renames its worker's process title, so this is often the
            // only evidence on the listening process itself.
            .commandOrParent("next-server", 0.92),
            .commandOrParent("next dev", 0.88),
            .commandOrParent("next start", 0.85),
            .anyFile(["next.config.js", "next.config.ts", "next.config.mjs"], 0.75),
        ]),
        FrameworkSignature(.nuxt, rules: [
            .dependency("nuxt", 0.95),
            .commandOrParent("nuxt", 0.8),
            .anyFile(["nuxt.config.ts", "nuxt.config.js"], 0.75),
        ]),
        FrameworkSignature(.svelteKit, rules: [
            .dependency("@sveltejs/kit", 0.95),
            .anyFile(["svelte.config.js", "svelte.config.ts"], 0.7),
        ]),
        FrameworkSignature(.astro, rules: [
            .dependency("astro", 0.95),
            .commandOrParent("astro dev", 0.85),
            .anyFile(["astro.config.mjs", "astro.config.ts"], 0.75),
        ]),
        FrameworkSignature(.remix, rules: [
            .dependency("@remix-run/dev", 0.95),
            .dependency("@remix-run/node", 0.9),
        ]),
        FrameworkSignature(.vite, rules: [
            .dependency("vite", 0.9),
            .commandOrParent("vite", 0.75),
            .anyFile(["vite.config.ts", "vite.config.js", "vite.config.mjs"], 0.7),
        ]),
        FrameworkSignature(.reactDevServer, rules: [
            .dependency("react-scripts", 0.92),
            .commandOrParent("react-scripts start", 0.85),
        ]),
        FrameworkSignature(.nestJS, rules: [
            .dependency("@nestjs/core", 0.95),
            .commandOrParent("nest start", 0.85),
            .file("nest-cli.json", 0.8),
        ]),
        FrameworkSignature(.hono, rules: [
            .dependency("hono", 0.92),
            .dependency("@hono/node-server", 0.9),
        ]),
        FrameworkSignature(.express, rules: [
            .dependency("express", 0.85),
        ]),
        FrameworkSignature(.bun, rules: [
            .processName("bun", 0.9),
            .commandOrParent("bun run", 0.7),
            .file("bun.lockb", 0.6),
            .file("bun.lock", 0.6),
        ]),
        FrameworkSignature(.deno, rules: [
            .processName("deno", 0.9),
            .anyFile(["deno.json", "deno.jsonc"], 0.7),
        ]),
        // Runtime baseline: reported only when nothing more specific matches.
        FrameworkSignature(.node, rules: [
            .processName("node", 0.5),
            .manifestKind(.packageJSON, 0.35),
        ]),
    ]

    // MARK: - Python

    private static let python: [FrameworkSignature] = [
        FrameworkSignature(.django, rules: [
            .dependency("django", 0.9),
            .commandOrParent("manage.py", 0.85),
            .commandOrParent("runserver", 0.8),
            .file("manage.py", 0.8),
        ]),
        FrameworkSignature(.flask, rules: [
            .dependency("flask", 0.9),
            .commandOrParent("flask run", 0.88),
            .processName("flask", 0.85),
        ]),
        FrameworkSignature(.fastAPI, rules: [
            .dependency("fastapi", 0.92),
            .commandOrParent("fastapi", 0.8),
        ]),
        // Ranks just under FastAPI: a FastAPI app served by Uvicorn should read
        // as FastAPI, but a bare `uvicorn app:server` still gets a name.
        FrameworkSignature(.uvicorn, rules: [
            .processName("uvicorn", 0.88),
            .commandOrParent("uvicorn", 0.8),
            .dependency("uvicorn", 0.6),
        ]),
        FrameworkSignature(.jupyter, rules: [
            .commandOrParent("jupyter", 0.9),
            .commandOrParent("notebook", 0.6),
            .processName("jupyter", 0.9, allowingSuffix: true),
            .port(8_888, 0.3),
        ]),
        FrameworkSignature(.python, rules: [
            .processName("python", 0.5, allowingSuffix: true),
            .manifestKind(.pyProject, 0.35),
            .manifestKind(.requirements, 0.3),
        ]),
    ]

    // MARK: - Other languages

    private static let otherLanguages: [FrameworkSignature] = [
        FrameworkSignature(.rails, rules: [
            .dependency("rails", 0.9),
            .commandOrParent("rails", 0.85),
            .commandOrParent("puma", 0.6),
            .file("config.ru", 0.65),
        ]),
        FrameworkSignature(.rust, rules: [
            .manifestKind(.cargo, 0.8),
            // cargo run builds into target/debug, which names the binary.
            .custom(0.85) { $0.executablePath?.contains("/target/debug/") ?? false },
            .custom(0.8) { $0.executablePath?.contains("/target/release/") ?? false },
        ]),
        FrameworkSignature(.go, rules: [
            .manifestKind(.goModule, 0.8),
            // `go run` executes from a temporary build directory.
            .custom(0.85) { $0.executablePath?.contains("/go-build") ?? false },
        ]),
    ]

    // MARK: - Infrastructure

    private static let infrastructure: [FrameworkSignature] = [
        FrameworkSignature(.postgres, rules: [
            .processName("postgres", 0.95, allowingSuffix: true),
            .port(5_432, 0.4),
        ]),
        FrameworkSignature(.mysql, rules: [
            .processName("mysqld", 0.95),
            .processName("mariadbd", 0.95),
            .port(3_306, 0.4),
        ]),
        FrameworkSignature(.mongo, rules: [
            .processName("mongod", 0.95),
            .port(27_017, 0.4),
        ]),
        FrameworkSignature(.redis, rules: [
            .processName("redis-server", 0.95),
            .processName("redis", 0.9, allowingSuffix: true),
            .port(6_379, 0.4),
        ]),
        FrameworkSignature(.docker, rules: [
            .custom(0.9) { $0.processName.contains("docker") },
            .custom(0.6) { $0.processName.contains("containerd") },
        ]),
        FrameworkSignature(.supabase, rules: [
            .commandOrParent("supabase", 0.75),
            .custom(0.7) { $0.processName.contains("supabase") },
        ]),
    ]
}
