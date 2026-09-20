import Foundation

/// Parses `lsof -F` field output.
///
/// Field mode emits one `<letter><value>` per line rather than aligned columns,
/// so nothing here depends on spacing or on names being free of whitespace.
/// Process-level fields (`p`, `c`) apply to every file record that follows
/// until the next `p`. Anything unrecognised or malformed is skipped rather
/// than aborting the parse — lsof reports partial results for processes it
/// cannot fully inspect, and one bad row must not lose the others.
enum LsofFieldParser {

    /// Field selector matching what `parse` expects.
    /// `p` pid, `c` command, `f` fd, `t` type (IPv4/IPv6), `P` protocol, `n` name.
    static let fieldSelector = "pcfntP"

    static func parse(_ output: String) -> [ListeningSocket] {
        var sockets: [ListeningSocket] = []

        var currentPID: Int32?
        var currentCommand: String?
        var recordFamily: AddressFamily?
        var recordProtocol: String?
        var recordName: String?

        func flushRecord() {
            defer {
                recordFamily = nil
                recordProtocol = nil
                recordName = nil
            }
            guard let pid = currentPID,
                  let command = currentCommand,
                  let name = recordName,
                  let family = recordFamily
            else { return }

            // `-iTCP` should make this redundant, but never trust it blindly.
            if let recordProtocol, recordProtocol.uppercased() != "TCP" { return }

            guard let endpoint = parseEndpoint(name) else { return }

            sockets.append(
                ListeningSocket(
                    pid: pid,
                    processName: command,
                    port: endpoint.port,
                    binding: SocketBinding(address: endpoint.address, family: family)
                )
            )
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())

            switch marker {
            case "p":
                flushRecord()
                currentPID = Int32(value)
                currentCommand = nil
            case "c":
                currentCommand = value.isEmpty ? nil : value
            case "f":
                // A new file descriptor closes the previous record.
                flushRecord()
            case "t":
                recordFamily = switch value.uppercased() {
                case "IPV4": .ipv4
                case "IPV6": .ipv6
                default: nil
                }
            case "P":
                recordProtocol = value
            case "n":
                recordName = value
            default:
                continue
            }
        }
        flushRecord()

        return sockets
    }

    /// Splits an lsof endpoint into address and port.
    ///
    /// Handles `*:3000`, `127.0.0.1:5432`, `[::1]:8000` and `[fe80::1%en0]:80`.
    /// Rejects anything without a numeric port in range, and anything carrying
    /// a `->` peer (a connected socket, not a listener).
    static func parseEndpoint(_ raw: String) -> (address: String, port: Int)? {
        guard !raw.contains("->") else { return nil }

        guard let separator = raw.lastIndex(of: ":") else { return nil }
        let portText = raw[raw.index(after: separator)...]
        guard let port = Int(portText), (1...65_535).contains(port) else { return nil }

        var address = String(raw[raw.startIndex..<separator])
        if address.hasPrefix("["), address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        guard !address.isEmpty else { return nil }

        return (address, port)
    }

    /// Collapses the raw socket rows into one entry per process/port.
    ///
    /// A dual-stack server binds the same port on IPv4 and IPv6 and must appear
    /// once. Bindings are sorted so the resulting value is stable across
    /// refreshes and does not churn the UI.
    static func deduplicate(_ sockets: [ListeningSocket]) -> [ListeningPort] {
        var order: [ServiceIdentifier] = []
        var grouped: [ServiceIdentifier: (name: String, bindings: [SocketBinding])] = [:]

        for socket in sockets {
            let key = ServiceIdentifier(pid: socket.pid, port: socket.port)
            if grouped[key] == nil {
                grouped[key] = (socket.processName, [])
                order.append(key)
            }
            if !grouped[key]!.bindings.contains(socket.binding) {
                grouped[key]!.bindings.append(socket.binding)
            }
        }

        return order.compactMap { key in
            guard let entry = grouped[key] else { return nil }
            let bindings = entry.bindings.sorted {
                ($0.family.rawValue, $0.address) < ($1.family.rawValue, $1.address)
            }
            return ListeningPort(
                pid: key.pid,
                processName: entry.name,
                port: key.port,
                bindings: bindings
            )
        }
    }
}
