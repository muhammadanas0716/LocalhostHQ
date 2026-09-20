import SwiftUI

enum DashboardWindow {
    static let identifier = "dashboard"
}

enum LogWindow {
    static let identifier = "logs"
}

@main
struct LocalhostHQApp: App {
    /// Owned here so the menu bar, dashboard and log windows all observe the
    /// same state and share one refresh loop.
    @State private var environment = AppEnvironment()

    var body: some Scene {
        Window(AppInfo.displayName, id: DashboardWindow.identifier) {
            DashboardView()
                .environment(environment)
                .environment(environment.services)
                .frame(minWidth: 680, minHeight: 420)
                .task { environment.start() }
        }
        .defaultSize(width: 1_020, height: 660)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Now") {
                    Task { await environment.services.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        WindowGroup(id: LogWindow.identifier, for: ServiceKey.self) { $key in
            LogWindowView(serviceKey: key)
                .environment(environment)
                .environment(environment.services)
                .frame(minWidth: 520, minHeight: 320)
        }
        .defaultSize(width: 860, height: 540)

        MenuBarExtra {
            MenuBarView()
                .environment(environment)
                .environment(environment.services)
        } label: {
            MenuBarLabel(count: environment.services.developerServiceCount)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(environment)
                .environment(environment.services)
        }
    }
}

/// Menu bar label: the app mark plus a live count of the developer's services.
private struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: HubMark.menuBarImage(size: 16))
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .accessibilityLabel("\(AppInfo.displayName), \(count) services")
    }
}

extension ServiceKey: Codable {
    private enum CodingKeys: String, CodingKey { case kind, path, port }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        port = try container.decode(Int.self, forKey: .port)
        anchor = switch kind {
        case "package": .package(path)
        case "directory": .directory(path)
        case "executable": .executable(path)
        default: .port
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(port, forKey: .port)
        switch anchor {
        case .package(let path):
            try container.encode("package", forKey: .kind)
            try container.encode(path, forKey: .path)
        case .directory(let path):
            try container.encode("directory", forKey: .kind)
            try container.encode(path, forKey: .path)
        case .executable(let path):
            try container.encode("executable", forKey: .kind)
            try container.encode(path, forKey: .path)
        case .port:
            try container.encode("port", forKey: .kind)
        }
    }
}
