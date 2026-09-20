import Foundation

enum LocalhostURL {
    static func make(port: Int, preferringTLS: Bool = false) -> URL? {
        guard (1...65_535).contains(port) else { return nil }
        var components = URLComponents()
        components.scheme = preferringTLS ? "https" : "http"
        components.host = "localhost"
        // 80 and 443 are implied by the scheme and read better without.
        let isDefault = (preferringTLS && port == 443) || (!preferringTLS && port == 80)
        components.port = isDefault ? nil : port
        components.path = "/"
        return components.url
    }

    /// Display form, without the trailing slash: `http://localhost:3000`.
    static func displayString(port: Int, preferringTLS: Bool = false) -> String? {
        guard let url = make(port: port, preferringTLS: preferringTLS) else { return nil }
        var text = url.absoluteString
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
