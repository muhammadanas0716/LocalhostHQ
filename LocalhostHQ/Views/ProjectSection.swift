import SwiftUI

/// A dashboard section: a repository, or one of the synthetic groupings.
struct ProjectSection: View {
    let group: ServiceGroup
    @Binding var selection: ServiceKey?

    @Environment(AppEnvironment.self) private var app
    @State private var isHoveringHeader = false
    @State private var confirmingStopProject = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            VStack(spacing: 4) {
                ForEach(group.services) { service in
                    ServiceRow(
                        service: service,
                        isSelected: selection == service.key,
                        onSelect: { selection = service.key }
                    )
                    .contextMenu { ServiceContextMenu(service: service) }
                }
            }
        }
        .onHover { isHoveringHeader = $0 }
        .confirmationDialog(
            "Stop \(group.services.count) \(group.title) services?",
            isPresented: $confirmingStopProject,
            titleVisibility: .visible
        ) {
            Button("Stop All", role: .destructive) {
                Task { await app.controller.stopProject(named: group.title, services: group.services) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops every service in this project that Localhost HQ can control.")
        }
    }

    /// Project-level controls appear only for real repositories, and only when
    /// something in them is actually controllable.
    private var restartableCount: Int {
        group.services.count { $0.capabilities.canRestart }
    }

    private var stoppableCount: Int {
        group.services.count { $0.capabilities.canStop }
    }

    private var showsProjectControls: Bool {
        group.kind == .repository && isHoveringHeader && (restartableCount > 0 || stoppableCount > 0)
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

            if showsProjectControls {
                projectControls
            } else {
                Text("\(group.services.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeOut(duration: 0.12), value: showsProjectControls)
    }

    private var projectControls: some View {
        HStack(spacing: 6) {
            // Partial capability is stated rather than hidden.
            if restartableCount < group.services.count {
                Text("\(restartableCount) of \(group.services.count) restartable")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
            }

            if restartableCount > 0 {
                Button("Restart Project") {
                    Task { await app.controller.restartProject(named: group.title, services: group.services) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.accent)
            }

            if stoppableCount > 0 {
                Button("Stop Project") {
                    // Confirm whenever more than one process is affected.
                    if stoppableCount > 1 {
                        confirmingStopProject = true
                    } else {
                        Task { await app.controller.stopProject(named: group.title, services: group.services) }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.danger)
            }
        }
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

/// Shared between the row context menu, the row overflow menu and the menu bar.
///
/// Destructive actions are separated from ordinary ones and marked, per macOS
/// convention — Stop must not sit flush against Open.
struct ServiceContextMenu: View {
    let service: LocalService
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openWindow) private var openWindow

    private var isBusy: Bool { app.controller.isBusy(service.key) }

    var body: some View {
        if let url = service.browserURL {
            Button("Open in Browser") { ServiceActions.openInBrowser(service) }
            Button("Copy URL") { ServiceActions.copyToPasteboard(url.absoluteString) }
        }

        Button("View Logs") {
            openWindow(id: LogWindow.identifier, value: service.key)
        }

        if service.actionableDirectory != nil {
            Divider()
            Button("Reveal in Finder") { ServiceActions.revealInFinder(service) }
            Button("Open in Terminal") { ServiceActions.openInTerminal(service) }
        }

        Divider()
        Button("Copy Port") { ServiceActions.copyToPasteboard(String(service.port)) }
        Button("Copy PID") { ServiceActions.copyToPasteboard(String(service.pid)) }

        if service.capabilities.canRestart || service.capabilities.canStop {
            Divider()
            if service.capabilities.canRestart {
                Button("Restart") { Task { await app.controller.restart(service) } }
                    .disabled(isBusy)
            }
            if service.capabilities.canStop {
                Button("Stop", role: .destructive) {
                    Task { await app.controller.stop(service) }
                }
                .disabled(isBusy)
            }
        }
    }
}

#Preview {
    @Previewable @State var selection: ServiceKey?
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
    .environment(AppEnvironment.preview(services: SampleData.all))
    .preferredColorScheme(.dark)
}
