import Foundation

/// Arranges services into dashboard sections.
///
/// Services sharing a repository root become a named project group. Everything
/// else falls into one of two synthetic sections — loose dev servers, and
/// infrastructure — rather than being forced into invented projects.
///
/// Ordering is fully determined by the data (never by discovery order), so the
/// dashboard does not reshuffle on every refresh.
struct ServiceGrouper: Sendable {

    func group(_ services: [LocalService]) -> [ServiceGroup] {
        var byRepository: [String: [LocalService]] = [:]
        var development: [LocalService] = []
        var infrastructure: [LocalService] = []
        var system: [LocalService] = []

        for service in services {
            if service.origin == .system {
                system.append(service)
            } else if let repositoryRoot = service.repositoryRoot {
                byRepository[repositoryRoot, default: []].append(service)
            } else if service.category.groupKind == .infrastructure {
                infrastructure.append(service)
            } else {
                development.append(service)
            }
        }

        var groups: [ServiceGroup] = byRepository
            .map { root, members in
                ServiceGroup(
                    id: root,
                    title: URL(fileURLWithPath: root).lastPathComponent,
                    kind: .repository,
                    directory: root,
                    services: sorted(members)
                )
            }
            .sorted { lhs, rhs in
                // Case-insensitive so `Api` and `api` do not interleave oddly.
                let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
            }

        if !development.isEmpty {
            groups.append(
                ServiceGroup(
                    id: "group.development",
                    title: "Development Servers",
                    kind: .development,
                    directory: nil,
                    services: sorted(development)
                )
            )
        }
        if !infrastructure.isEmpty {
            groups.append(
                ServiceGroup(
                    id: "group.infrastructure",
                    title: "Infrastructure",
                    kind: .infrastructure,
                    directory: nil,
                    services: sorted(infrastructure)
                )
            )
        }
        if !system.isEmpty {
            groups.append(
                ServiceGroup(
                    id: "group.system",
                    title: "System & Apps",
                    kind: .system,
                    directory: nil,
                    services: sorted(system)
                )
            )
        }

        return groups.sorted { lhs, rhs in
            lhs.kind == rhs.kind ? lhs.id < rhs.id : lhs.kind < rhs.kind
        }
    }

    /// Port first — it is the stable, memorable handle — then name, then PID so
    /// the order is total even for two ports of one process.
    private func sorted(_ services: [LocalService]) -> [LocalService] {
        services.sorted {
            if $0.port != $1.port { return $0.port < $1.port }
            let comparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0.pid < $1.pid
        }
    }
}
