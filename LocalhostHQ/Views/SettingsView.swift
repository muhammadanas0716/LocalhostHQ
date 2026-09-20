import SwiftUI

struct SettingsView: View {
    @Environment(ServicesStore.self) private var store
    @AppStorage("showsDebugInspector") private var showsDebugInspector = false

    var body: some View {
        Form {
            Section {
                Toggle("Show system and app services", isOn: Binding(
                    get: { store.showsSystemServices },
                    set: { store.showsSystemServices = $0 }
                ))
                .help("Includes macOS daemons and installed applications that listen on a port.")
            } header: {
                Text("Discovery")
            } footer: {
                Text("Localhost HQ refreshes every 2 seconds. Project, framework and Git details are cached per process.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Developer") {
                Toggle("Show debug inspector", isOn: $showsDebugInspector)
                    .help("Adds raw discovery output and the framework confidence ranking to the detail panel.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView()
        .environment(ServicesStore.preview(services: SampleData.all))
}
