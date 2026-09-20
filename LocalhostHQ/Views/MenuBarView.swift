import SwiftUI

/// Compact summary shown when the menu bar item is clicked.
struct MenuBarView: View {
    @Environment(ServicesStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.border)

            if store.groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.groups) { group in
                            groupView(group)
                        }
                    }
                    .padding(.vertical, 9)
                }
                .frame(maxHeight: 360)
                .scrollBounceBehavior(.basedOnSize)
            }

            Divider().overlay(Theme.border)
            footer
        }
        .frame(width: 308)
        .background(Theme.chrome)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            HubMarkBadge(size: 19)
            Text(AppInfo.displayName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Text(countLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var countLabel: String {
        let count = store.visibleServices.count
        return count == 1 ? "1 running" : "\(count) running"
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Text("Nothing running")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("Start a dev server to see it here")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private func groupView(_ group: ServiceGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: group.title)
                .padding(.horizontal, 12)

            ForEach(group.services) { service in
                MenuBarServiceRow(service: service) { open(service) }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 1) {
            MenuBarActionButton(title: "Open Dashboard", symbol: "square.grid.2x2") {
                openDashboard()
            }
            MenuBarActionButton(title: "Quit Localhost HQ", symbol: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Actions

    private func open(_ service: LocalService) {
        if service.supportsBrowserOpen {
            ServiceActions.openInBrowser(service)
        } else {
            openDashboard()
        }
    }

    private func openDashboard() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: DashboardWindow.identifier)
    }
}

/// One service line in the menu bar popover.
///
/// Restart is the only control offered here; anything destructive lives in the
/// context menu, and logs belong in a window rather than a popover.
private struct MenuBarServiceRow: View {
    let service: LocalService
    let action: () -> Void

    @Environment(AppEnvironment.self) private var app
    @State private var isHovering = false

    private var state: ServiceRuntimeState { app.lifecycle.state(for: service.key) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ServiceGlyph(
                    category: service.category,
                    symbolName: service.framework?.symbolName ?? "circle.dotted",
                    size: 22,
                    showsStatusDot: false
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(service.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isHovering, service.capabilities.canRestart {
                    IconButton(
                        symbol: "arrow.clockwise",
                        help: "Restart",
                        isDisabled: app.controller.isBusy(service.key)
                    ) {
                        Task { await app.controller.restart(service) }
                    }
                }

                PortBadge(port: service.port, isProminent: isHovering)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Theme.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
        .onHover { isHovering = $0 }
        .help(service.supportsBrowserOpen ? "Open in browser" : "Show in dashboard")
        .contextMenu { ServiceContextMenu(service: service) }
    }

    private var subtitle: String {
        if case .running = state { return service.subtitle }
        return state.label
    }
}

private struct MenuBarActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Theme.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
        .onHover { isHovering = $0 }
    }
}

#Preview("Menu bar") {
    MenuBarView()
        .environment(AppEnvironment.preview(services: SampleData.all))
        .environment(ServicesStore.preview(services: SampleData.all))
}

#Preview("Menu bar – empty") {
    MenuBarView()
        .environment(AppEnvironment.preview(services: []))
        .environment(ServicesStore.preview(services: []))
}
