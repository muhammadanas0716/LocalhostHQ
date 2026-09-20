import SwiftUI

enum DashboardWindow {
    static let identifier = "dashboard"
}

@main
struct LocalhostHQApp: App {
    /// Owned here so the menu bar and the dashboard observe the same state and
    /// share one refresh loop.
    @State private var store = ServicesStore()

    var body: some Scene {
        Window(AppInfo.displayName, id: DashboardWindow.identifier) {
            DashboardView()
                .environment(store)
                .frame(minWidth: 620, minHeight: 380)
                .task { store.startMonitoring() }
        }
        .defaultSize(width: 940, height: 600)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Now") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView().environment(store)
        } label: {
            MenuBarLabel(count: store.developerServiceCount)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(store)
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
