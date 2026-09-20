import Foundation

/// Free-text filtering for the dashboard search field.
///
/// Matches across every field a developer might type: project and service name,
/// framework, port, path, branch, process name and PID. Pure, and therefore
/// tested directly.
struct ServiceFilter: Sendable {

    func apply(query: String, to services: [LocalService]) -> [LocalService] {
        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return services }

        // Every term must match somewhere, so typing `dicee 3000` narrows.
        return services.filter { service in
            let haystack = searchableText(for: service)
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    private func searchableText(for service: LocalService) -> String {
        var parts: [String] = [
            service.displayName,
            service.process.name,
            String(service.port),
            String(service.pid),
        ]
        if let framework = service.framework {
            parts.append(framework.displayName)
            parts.append(framework.category.rawValue)
            if let runtime = framework.runtime { parts.append(runtime.displayName) }
        }
        if let branch = service.git?.branchName { parts.append(branch) }
        if let project = service.project {
            parts.append(project.workingDirectory)
            if let packageRoot = project.packageRoot { parts.append(packageRoot) }
            if let repositoryRoot = project.repositoryRoot { parts.append(repositoryRoot) }
            if let declaredName = project.manifest?.declaredName { parts.append(declaredName) }
        }
        return parts.joined(separator: " ").lowercased()
    }
}
