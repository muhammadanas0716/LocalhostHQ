import Foundation

/// Reads and parses the package manifest at a package root.
///
/// Parsing is intentionally shallow: only the project name and the set of
/// dependency identifiers are extracted, because that is all naming and
/// framework detection need. Malformed manifests yield `nil` rather than
/// throwing — a half-written `package.json` during a save is routine.
struct ManifestLoader: Sendable {
    private let fileSystem: FileSystemProbing

    init(fileSystem: FileSystemProbing = LiveFileSystem()) {
        self.fileSystem = fileSystem
    }

    func load(packageRoot: String) -> ProjectManifest? {
        for kind in Self.kindPriority {
            for filename in kind.filenames {
                let path = packageRoot + "/" + filename
                guard fileSystem.fileExists(atPath: path),
                      let data = fileSystem.contents(atPath: path)
                else { continue }

                if let manifest = parse(kind: kind, path: path, data: data) {
                    return manifest
                }
            }
        }
        return nil
    }

    /// Node first: a polyglot repo usually has its runnable server described by
    /// package.json, and it carries the richest dependency signal.
    private static let kindPriority: [ProjectManifest.Kind] = [
        .packageJSON, .pyProject, .cargo, .goModule, .gemfile, .requirements, .pipfile, .compose,
    ]

    private func parse(kind: ProjectManifest.Kind, path: String, data: Data) -> ProjectManifest? {
        switch kind {
        case .packageJSON: parsePackageJSON(path: path, data: data)
        case .pyProject: parsePyProject(path: path, data: data)
        case .cargo: parseCargo(path: path, data: data)
        case .goModule: parseGoModule(path: path, data: data)
        case .requirements: parseRequirements(path: path, data: data)
        case .gemfile: parseGemfile(path: path, data: data)
        case .pipfile: parsePlainDependencies(kind: .pipfile, path: path, data: data)
        case .compose: ProjectManifest(kind: .compose, path: path, declaredName: nil, dependencies: [])
        }
    }

    // MARK: - Node

    private func parsePackageJSON(path: String, data: Data) -> ProjectManifest? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var dependencies: Set<String> = []
        for key in ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"] {
            guard let table = root[key] as? [String: Any] else { continue }
            dependencies.formUnion(table.keys.map { $0.lowercased() })
        }
        // Scripts reveal the dev server even when the dependency is hoisted out
        // of this package, which is common in monorepos.
        if let scripts = root["scripts"] as? [String: Any] {
            for value in scripts.values.compactMap({ $0 as? String }) {
                dependencies.formUnion(Self.tokens(in: value))
            }
        }

        return ProjectManifest(
            kind: .packageJSON,
            path: path,
            declaredName: root["name"] as? String,
            dependencies: dependencies
        )
    }

    // MARK: - Python

    /// Minimal TOML probing. A full parser is unwarranted: only `name` under
    /// `[project]`/`[tool.poetry]` and the dependency identifiers are needed.
    private func parsePyProject(path: String, data: Data) -> ProjectManifest? {
        let text = String(decoding: data, as: UTF8.self)
        return ProjectManifest(
            kind: .pyProject,
            path: path,
            declaredName: Self.tomlString(key: "name", in: text),
            dependencies: Self.tokens(in: text)
        )
    }

    private func parseRequirements(path: String, data: Data) -> ProjectManifest? {
        ProjectManifest(
            kind: .requirements,
            path: path,
            declaredName: nil,
            dependencies: Self.tokens(in: String(decoding: data, as: UTF8.self))
        )
    }

    private func parsePlainDependencies(kind: ProjectManifest.Kind, path: String, data: Data) -> ProjectManifest? {
        ProjectManifest(
            kind: kind,
            path: path,
            declaredName: nil,
            dependencies: Self.tokens(in: String(decoding: data, as: UTF8.self))
        )
    }

    // MARK: - Rust / Go / Ruby

    private func parseCargo(path: String, data: Data) -> ProjectManifest? {
        let text = String(decoding: data, as: UTF8.self)
        return ProjectManifest(
            kind: .cargo,
            path: path,
            declaredName: Self.tomlString(key: "name", in: text),
            dependencies: Self.tokens(in: text)
        )
    }

    private func parseGoModule(path: String, data: Data) -> ProjectManifest? {
        let text = String(decoding: data, as: UTF8.self)
        var moduleName: String?
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("module ") else { continue }
            // Go module paths are URLs; the last segment is the useful name.
            let value = trimmed.dropFirst("module ".count).trimmingCharacters(in: .whitespaces)
            moduleName = value.split(separator: "/").last.map(String.init) ?? value
            break
        }
        return ProjectManifest(
            kind: .goModule,
            path: path,
            declaredName: moduleName,
            dependencies: Self.tokens(in: text)
        )
    }

    private func parseGemfile(path: String, data: Data) -> ProjectManifest? {
        ProjectManifest(
            kind: .gemfile,
            path: path,
            declaredName: nil,
            dependencies: Self.tokens(in: String(decoding: data, as: UTF8.self))
        )
    }

    // MARK: - Shared text helpers

    /// Lowercased identifier-ish tokens, used as a dependency-presence set.
    /// Deliberately loose: detection only ever asks "does this name appear".
    static func tokens(in text: String) -> Set<String> {
        var tokens: Set<String> = []
        var current = ""
        current.reserveCapacity(32)

        for character in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(character) || character == "-" || character == "_"
                || character == "." || character == "@" || character == "/" {
                current.unicodeScalars.append(character)
            } else if !current.isEmpty {
                tokens.insert(current.lowercased())
                current = ""
            }
        }
        if !current.isEmpty { tokens.insert(current.lowercased()) }
        return tokens
    }

    /// Finds `key = "value"` in TOML-ish text, ignoring commented lines.
    static func tomlString(key: String, in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }

            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            guard raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") else { continue }
            let value = String(raw.dropFirst().dropLast())
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
