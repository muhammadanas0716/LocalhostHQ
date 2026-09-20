import Foundation

/// Pure display formatting. Kept free of `Foundation.Formatter` so the output is
/// locale-stable and directly unit-testable.
enum Format {

    // MARK: - Memory

    /// Decimal (1000-based) byte sizes, matching Activity Monitor's convention.
    /// Sub-gigabyte values are whole numbers; gigabytes carry one decimal.
    static func memory(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        switch value {
        case ..<1_000:
            return "\(bytes) B"
        case ..<1_000_000:
            return "\(Int((value / 1_000).rounded())) KB"
        case ..<1_000_000_000:
            return "\(Int((value / 1_000_000).rounded())) MB"
        default:
            return String(format: "%.1f GB", value / 1_000_000_000)
        }
    }

    // MARK: - CPU

    /// Percentage of a *single* core. A multi-threaded process legitimately
    /// exceeds 100%, so the value is never clamped.
    static func cpu(_ percent: Double) -> String {
        guard percent.isFinite, percent > 0 else { return "0%" }
        if percent < 1 { return "<1%" }
        return "\(Int(percent.rounded()))%"
    }

    /// One-decimal variant for the detail inspector.
    static func cpuPrecise(_ percent: Double) -> String {
        guard percent.isFinite, percent > 0 else { return "0.0%" }
        return String(format: "%.1f%%", percent)
    }

    // MARK: - Uptime

    /// Coarse, glanceable duration: `43s`, `12m`, `2h 13m`, `1d 4h`.
    static func uptime(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "—" }
        let total = Int(interval)
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = (total / 3_600) % 24
        let days = total / 86_400

        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    // MARK: - Paths

    /// Replaces the user's home directory with `~`.
    static func path(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// Trailing path components, for tight rows: `dicee/apps/web`.
    static func pathTail(_ path: String, components limit: Int = 3) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > limit else { return Format.path(path) }
        return "…/" + parts.suffix(limit).joined(separator: "/")
    }
}
