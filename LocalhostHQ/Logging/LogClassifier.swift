import Foundation

/// Assigns heuristic levels to log lines and recognises a few well-known
/// failures.
///
/// Deliberately small and deterministic. Dev-server output has no common
/// format, so this aims to be *useful and honest* rather than complete: lines
/// it cannot classify get no level and are shown unchanged.
struct LogClassifier: Sendable {

    // MARK: - Level

    /// Substrings that mark a line as an error, matched case-insensitively.
    private static let errorMarkers = [
        "error", "exception", "fatal", "failed", "failure",
        "panic", "traceback", "unhandled", "cannot find", "not found",
    ]

    private static let warningMarkers = [
        "warn", "warning", "deprecat", "experimental",
    ]

    private static let debugMarkers = ["debug", "trace", "verbose"]

    /// Substrings that look like errors but routinely appear in healthy output,
    /// most often HTTP access logs (`GET /error-page 200`).
    private static let falsePositives = [
        " 200", " 201", " 204", " 301", " 302", " 304",
    ]

    func level(of line: String) -> LogLevel? {
        let lowered = line.lowercased()

        // A 5xx status in an access log is a genuine error; a 2xx line that
        // merely mentions "error" in a path is not.
        if Self.looksLikeSuccessfulAccessLog(lowered) { return .info }

        if Self.errorMarkers.contains(where: lowered.contains) { return .error }
        if Self.warningMarkers.contains(where: lowered.contains) { return .warning }
        if Self.debugMarkers.contains(where: lowered.contains) { return .debug }
        return nil
    }

    private static func looksLikeSuccessfulAccessLog(_ lowered: String) -> Bool {
        let isRequestLine = ["get ", "post ", "put ", "patch ", "delete "].contains { lowered.hasPrefix($0) }
        guard isRequestLine else { return false }
        return falsePositives.contains(where: lowered.contains)
    }

    /// The level to record for a line, taking the stream into account.
    ///
    /// stderr is not treated as an error by default: a great many tools log
    /// perfectly ordinary progress there.
    func level(of line: String, stream: LogStream) -> LogLevel? {
        level(of: line)
    }

    // MARK: - Diagnosis

    private struct Signature {
        let markers: [String]
        let summary: String
        let detail: String
        let extractsPort: Bool
    }

    private static let signatures: [Signature] = [
        Signature(
            // Covers Node's `EADDRINUSE`, Python's "address already in use"
            // and the plain-English phrasing frameworks print themselves.
            markers: ["eaddrinuse", "already in use", "address in use", "port is in use"],
            summary: "Port already in use",
            detail: "Another process is already listening on this port.",
            extractsPort: true
        ),
        Signature(
            markers: ["module_not_found", "cannot find module", "modulenotfounderror"],
            summary: "Missing dependency",
            detail: "A required module could not be found. Installing dependencies usually fixes this.",
            extractsPort: false
        ),
        Signature(
            markers: ["command not found", "no such file or directory"],
            summary: "Launch command not found",
            detail: "The command could not be found. Check that its tooling is installed and on PATH.",
            extractsPort: false
        ),
        Signature(
            markers: ["eacces", "permission denied"],
            summary: "Permission denied",
            detail: "The process was not allowed to access a file or port.",
            extractsPort: false
        ),
        Signature(
            markers: ["econnrefused", "connection refused"],
            summary: "Connection refused",
            detail: "A service this one depends on is not reachable.",
            extractsPort: false
        ),
        Signature(
            markers: ["out of memory", "heap out of memory", "javascript heap"],
            summary: "Out of memory",
            detail: "The process exhausted its available memory.",
            extractsPort: false
        ),
    ]

    /// Scans recent output for a recognised failure, newest first.
    func diagnose(_ lines: [String]) -> LogDiagnosis? {
        for line in lines.reversed() {
            let lowered = line.lowercased()
            guard let signature = Self.signatures.first(where: { candidate in
                candidate.markers.contains(where: lowered.contains)
            }) else { continue }

            return LogDiagnosis(
                summary: signature.summary,
                detail: signature.detail,
                conflictingPort: signature.extractsPort ? Self.extractPort(from: line) : nil
            )
        }
        return nil
    }

    /// Pulls a port out of text like `Port 3000 is already in use` or
    /// `listen EADDRINUSE: address already in use :::3000`.
    static func extractPort(from line: String) -> Int? {
        var candidates: [Int] = []
        var digits = ""

        for character in line {
            if character.isNumber {
                digits.append(character)
            } else {
                if let value = Int(digits) { candidates.append(value) }
                digits = ""
            }
        }
        if let value = Int(digits) { candidates.append(value) }

        // Ports live in a known range; other numbers in the line (byte counts,
        // IPv4 octets, error codes) generally do not.
        return candidates.last { (1_024...65_535).contains($0) }
            ?? candidates.last { (1...65_535).contains($0) }
    }
}
