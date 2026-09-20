import SwiftUI

/// A dashboard section: a repository, or one of the synthetic groupings.
struct ProjectSection: View {
    let group: ServiceGroup
    @Binding var selection: ServiceIdentifier?

    var body: some View {
        Section {
            ForEach(group.services) { service in
                ServiceRow(service: service, isSelected: selection == service.id)
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                    .listRowSeparator(.hidden)
                    .tag(service.id)
                    .contextMenu { ServiceContextMenu(service: service) }
            }
        } header: {
            header
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: group.kind.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            Text(group.title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(.secondary)

            if let directory = group.directory {
                Text(Format.path(directory))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            Text("\(group.services.count)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

extension ServiceGroupKind {
    var symbolName: String {
        switch self {
        case .repository: "folder"
        case .development: "hammer"
        case .infrastructure: "server.rack"
        case .system: "gearshape"
        }
    }
}

/// Shared between the row context menu and the detail view's toolbar.
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
    return List(selection: $selection) {
        ProjectSection(
            group: ServiceGroup(
                id: "/Users/anas/Code/dicee",
                title: "dicee",
                kind: .repository,
                directory: "/Users/anas/Code/dicee",
                services: [SampleData.web, SampleData.api]
            ),
            selection: $selection
        )
    }
    .frame(width: 560, height: 260)
}
