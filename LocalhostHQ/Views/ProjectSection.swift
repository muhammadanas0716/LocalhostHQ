import SwiftUI

/// A dashboard section: a repository, or one of the synthetic groupings.
struct ProjectSection: View {
    let group: ServiceGroup
    @Binding var selection: ServiceIdentifier?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            VStack(spacing: 4) {
                ForEach(group.services) { service in
                    ServiceRow(
                        service: service,
                        isSelected: selection == service.id,
                        onSelect: { selection = service.id }
                    )
                    .contextMenu { ServiceContextMenu(service: service) }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: group.kind.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            SectionLabel(text: group.title)

            if let directory = group.directory {
                Text(Format.path(directory))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            Text("\(group.services.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
    }
}

extension ServiceGroupKind {
    var symbolName: String {
        switch self {
        case .repository: "folder.fill"
        case .development: "hammer.fill"
        case .infrastructure: "server.rack"
        case .system: "gearshape.fill"
        }
    }
}

/// Shared between the row context menu and the detail view.
struct ServiceContextMenu: View {
    let service: LocalService

    var body: some View {
        if let url = service.browserURL {
            Button("Open in Browser") { ServiceActions.openInBrowser(service) }
            Button("Copy URL") { ServiceActions.copyToPasteboard(url.absoluteString) }
            Divider()
        }
        if service.actionableDirectory != nil {
            Button("Reveal in Finder") { ServiceActions.revealInFinder(service) }
            Button("Open in Terminal") { ServiceActions.openInTerminal(service) }
            Divider()
        }
        Button("Copy Port") { ServiceActions.copyToPasteboard(String(service.port)) }
        Button("Copy PID") { ServiceActions.copyToPasteboard(String(service.pid)) }
    }
}

#Preview {
    @Previewable @State var selection: ServiceIdentifier?
    return ProjectSection(
        group: ServiceGroup(
            id: "/Users/anas/Code/dicee",
            title: "dicee",
            kind: .repository,
            directory: "/Users/anas/Code/dicee",
            services: [SampleData.web, SampleData.api]
        ),
        selection: $selection
    )
    .padding(14)
    .frame(width: 600)
    .background(Theme.canvas)
    .preferredColorScheme(.dark)
}
