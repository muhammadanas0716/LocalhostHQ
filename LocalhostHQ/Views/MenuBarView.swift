import SwiftUI

/// Compact summary shown when the menu bar item is clicked.
struct MenuBarView: View {
    @Environment(ServicesStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.groups.isEmpty {
                Text("No local services running")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 22)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.groups) { group in
                            groupView(group)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 340)
                .scrollBounceBehavior(.basedOnSize)
            }

            Divider()
            footer
        }
        .frame(width: 300)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            HubMarkBadge(size: 18)
            Text(AppInfo.displayName)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(store.visibleServices.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func groupView(_ group: ServiceGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(group.title)
                .font(.system(size: 9.5, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)

            ForEach(group.services) { service in
                MenuBarServiceRow(service: service) { open(service) }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MenuBarActionButton(title: "Open Dashboard", symbol: "square.grid.2x2") {
                openDashboard()
            }
            MenuBarActionButton(title: "Quit Localhost HQ", symbol: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
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
private struct MenuBarServiceRow: View {
    let service: LocalService
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                StatusIndicator(category: service.category, diameter: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(service.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if !service.subtitle.isEmpty {
                        Text(service.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(":\(String(service.port))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovering ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
        .help(service.supportsBrowserOpen ? "Open in browser" : "Show in dashboard")
    }
}

private struct MenuBarActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovering ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }
}

#Preview("Menu bar") {
    MenuBarView()
        .environment(ServicesStore.preview(services: SampleData.all))
}

#Preview("Menu bar – empty") {
    MenuBarView()
        .environment(ServicesStore.preview(services: []))
}
