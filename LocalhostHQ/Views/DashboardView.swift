import SwiftUI

/// The main window: a grouped list of services with a trailing inspector.
struct DashboardView: View {
    @Environment(ServicesStore.self) private var store
    @State private var selection: ServiceIdentifier?
    @State private var frameworkRanking: [FrameworkDetection] = []
    @AppStorage("showsDebugInspector") private var showsDebugInspector = false

    var body: some View {
        @Bindable var store = store

        content
            .navigationTitle(AppInfo.displayName)
            .navigationSubtitle(subtitle)
            .searchable(text: $store.searchQuery, placement: .toolbar, prompt: "Search services")
            .toolbar { toolbarContent }
            .inspector(isPresented: .constant(selectedService != nil)) {
                if let service = selectedService {
                    ServiceDetailView(service: service, frameworkRanking: frameworkRanking)
                        .inspectorColumnWidth(min: 280, ideal: 330, max: 420)
                }
            }
            .task(id: selection) { await loadRanking() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.groups.isEmpty {
            EmptyStateView(reason: emptyReason)
        } else {
            List(selection: $selection) {
                ForEach(store.groups) { group in
                    ProjectSection(group: group, selection: $selection)
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
        }
    }

    private var selectedService: LocalService? {
        guard let selection else { return nil }
        // Look through all services, not just visible ones: a selected row must
        // not vanish from the inspector merely because the search narrowed.
        return store.services.first { $0.id == selection }
    }

    private var emptyReason: EmptyStateView.Reason {
        if store.scannerUnavailable { return .scannerUnavailable }
        if !store.searchQuery.isEmpty { return .noMatches(query: store.searchQuery) }
        return .noServices
    }

    private var subtitle: String {
        let count = store.visibleServices.count
        return count == 1 ? "1 service" : "\(count) services"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Binding(
                get: { store.showsSystemServices },
                set: { store.showsSystemServices = $0 }
            )) {
                Label("System Services", systemImage: "gearshape.2")
            }
            .help("Show services owned by macOS and installed apps")

            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            .help("Refresh now")
        }
    }

    private func loadRanking() async {
        guard showsDebugInspector, let service = selectedService else {
            frameworkRanking = []
            return
        }
        frameworkRanking = await store.frameworkRanking(for: service)
    }
}

#Preview("Dashboard") {
    DashboardView()
        .environment(ServicesStore.preview(services: SampleData.all))
        .frame(width: 900, height: 560)
}

#Preview("Empty") {
    DashboardView()
        .environment(ServicesStore.preview(services: []))
        .frame(width: 900, height: 560)
}
