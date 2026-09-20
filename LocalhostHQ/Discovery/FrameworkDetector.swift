import Foundation

/// Everything detection is allowed to look at.
///
/// A plain value with no I/O: the caller gathers these facts once, which keeps
/// the detector pure and makes every signature directly unit-testable.
struct DetectionContext: Sendable {
    /// Executable basename, lowercased (`node`, `python3.12`, `postgres`).
    let processName: String
    let executablePath: String?
    /// The listening process's own `argv`, lowercased.
    let arguments: [String]
    /// The *parent* process's `argv`, lowercased.
    ///
    /// Essential in practice: Next.js rewrites its child's process title to
    /// `next-server (v16.3.1)`, and `npm run dev` / `pnpm dev` wrappers keep the
    /// real command only on the parent.
    let parentArguments: [String]
    let port: Int
    let manifest: ProjectManifest?
    /// Filenames present at the package root.
    let markerFiles: Set<String>

    /// Own arguments joined, for substring matching.
    let commandLine: String
    /// Own + parent arguments joined.
    let fullCommandLine: String

    init(
        processName: String,
        executablePath: String? = nil,
        arguments: [String] = [],
        parentArguments: [String] = [],
        port: Int = 0,
        manifest: ProjectManifest? = nil,
        markerFiles: Set<String> = []
    ) {
        self.processName = processName.lowercased()
        self.executablePath = executablePath
        self.arguments = arguments.map { $0.lowercased() }
        self.parentArguments = parentArguments.map { $0.lowercased() }
        self.port = port
        self.manifest = manifest
        self.markerFiles = markerFiles
        self.commandLine = self.arguments.joined(separator: " ")
        self.fullCommandLine = (self.arguments + self.parentArguments).joined(separator: " ")
    }

    func declaresDependency(_ name: String) -> Bool {
        manifest?.dependencies.contains(name.lowercased()) ?? false
    }

    func hasMarkerFile(_ name: String) -> Bool {
        markerFiles.contains(name)
    }
}

/// One piece of evidence for a framework.
struct DetectionRule: Sendable {
    let weight: Double
    /// Corroborating rules strengthen a detection but can never establish one
    /// on their own. A conventional port is the motivating case: something
    /// listening on 5432 is *probably* Postgres, but calling every unknown
    /// process on that port "PostgreSQL" would be a fabrication.
    let isCorroborating: Bool
    let matches: @Sendable (DetectionContext) -> Bool

    init(weight: Double, isCorroborating: Bool = false, matches: @escaping @Sendable (DetectionContext) -> Bool) {
        self.weight = weight
        self.isCorroborating = isCorroborating
        self.matches = matches
    }

    /// A dependency or script token in the package manifest — the strongest
    /// available signal, since it is declared by the project itself.
    static func dependency(_ name: String, _ weight: Double = 0.9) -> DetectionRule {
        DetectionRule(weight: weight) { $0.declaresDependency(name) }
    }

    /// A substring anywhere in the process's own command line.
    static func command(_ needle: String, _ weight: Double = 0.7) -> DetectionRule {
        let needle = needle.lowercased()
        return DetectionRule(weight: weight) { $0.commandLine.contains(needle) }
    }

    /// A substring in the process's or its parent's command line.
    static func commandOrParent(_ needle: String, _ weight: Double = 0.7) -> DetectionRule {
        let needle = needle.lowercased()
        return DetectionRule(weight: weight) { $0.fullCommandLine.contains(needle) }
    }

    /// Exact executable basename, optionally allowing a version suffix
    /// (`python` also matches `python3`, `python3.12`).
    static func processName(_ name: String, _ weight: Double = 0.8, allowingSuffix: Bool = false) -> DetectionRule {
        let name = name.lowercased()
        return DetectionRule(weight: weight) { context in
            allowingSuffix ? context.processName.hasPrefix(name) : context.processName == name
        }
    }

    static func file(_ name: String, _ weight: Double = 0.6) -> DetectionRule {
        DetectionRule(weight: weight) { $0.hasMarkerFile(name) }
    }

    static func anyFile(_ names: [String], _ weight: Double = 0.6) -> DetectionRule {
        DetectionRule(weight: weight) { context in names.contains { context.hasMarkerFile($0) } }
    }

    static func manifestKind(_ kind: ProjectManifest.Kind, _ weight: Double = 0.5) -> DetectionRule {
        DetectionRule(weight: weight) { $0.manifest?.kind == kind }
    }

    /// Conventional port. Corroborating only: never enough by itself.
    static func port(_ port: Int, _ weight: Double = 0.3) -> DetectionRule {
        DetectionRule(weight: weight, isCorroborating: true) { $0.port == port }
    }

    static func custom(
        _ weight: Double,
        isCorroborating: Bool = false,
        _ matches: @escaping @Sendable (DetectionContext) -> Bool
    ) -> DetectionRule {
        DetectionRule(weight: weight, isCorroborating: isCorroborating, matches: matches)
    }
}

/// A framework plus the evidence that identifies it.
struct FrameworkSignature: Sendable {
    let framework: Framework
    let rules: [DetectionRule]
    /// Rules that, when matched, disqualify the signature outright.
    let exclusions: [DetectionRule]

    init(_ framework: Framework, rules: [DetectionRule], excluding exclusions: [DetectionRule] = []) {
        self.framework = framework
        self.rules = rules
        self.exclusions = exclusions
    }

    /// Combines matching rules as independent evidence (noisy-OR):
    /// `1 - Π(1 - weight)`. Several weak signals reinforce each other without
    /// any single one being able to reach certainty.
    func confidence(in context: DetectionContext) -> Double {
        guard !exclusions.contains(where: { $0.matches(context) }) else { return 0 }

        var complement = 1.0
        var hasSubstantiveMatch = false
        for rule in rules where rule.matches(context) {
            if !rule.isCorroborating { hasSubstantiveMatch = true }
            complement *= (1 - min(max(rule.weight, 0), 0.99))
        }
        // Corroborating evidence alone proves nothing.
        guard hasSubstantiveMatch else { return 0 }
        return min(1 - complement, 0.99)
    }
}

/// Scores every signature against a context and returns the strongest match.
struct FrameworkDetector: Sendable {
    /// Below this, a guess is noise and no framework is reported.
    static let minimumConfidence = 0.25

    private let signatures: [FrameworkSignature]

    init(signatures: [FrameworkSignature] = FrameworkCatalog.signatures) {
        self.signatures = signatures
    }

    func detect(in context: DetectionContext) -> FrameworkDetection? {
        ranked(in: context).first
    }

    /// Full ranking, strongest first. Surfaced by the debug inspector, which is
    /// what makes misdetections diagnosable.
    func ranked(in context: DetectionContext) -> [FrameworkDetection] {
        signatures
            .map { FrameworkDetection(framework: $0.framework, confidence: $0.confidence(in: context)) }
            .filter { $0.confidence >= Self.minimumConfidence }
            // Tie-break on framework id so ordering never depends on catalog
            // order or dictionary iteration.
            .sorted {
                $0.confidence == $1.confidence
                    ? $0.framework.id < $1.framework.id
                    : $0.confidence > $1.confidence
            }
    }
}
