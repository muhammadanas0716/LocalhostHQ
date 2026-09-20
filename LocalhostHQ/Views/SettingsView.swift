import SwiftUI

struct SettingsView: View {
    @Environment(ServicesStore.self) private var store
    @AppStorage("showsDebugInspector") private var showsDebugInspector = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section(
                title: "Discovery",
                footer: "Localhost HQ refreshes every 2 seconds. Project, framework and Git details are cached per process, so a refresh costs one lsof call and a few syscalls."
            ) {
                settingToggle(
                    "Show system and app services",
                    detail: "Includes macOS daemons and installed apps that listen on a port.",
                    isOn: Binding(
                        get: { store.showsSystemServices },
                        set: { store.showsSystemServices = $0 }
                    )
                )
            }

            section(title: "Developer", footer: nil) {
                settingToggle(
                    "Show debug inspector",
                    detail: "Adds raw discovery output and framework confidence scores to the detail panel.",
                    isOn: $showsDebugInspector
                )
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.canvas)
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(
        title: String,
        footer: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .themedCard()

            if let footer {
                Text(footer)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview(services: SampleData.all))
        .environment(ServicesStore.preview(services: SampleData.all))
}
