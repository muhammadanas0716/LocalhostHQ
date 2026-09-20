import SwiftUI

/// The main window: grouped services with a trailing inspector.
struct DashboardView: View {
    @Environment(ServicesStore.self) private var store
    @State private var selection: ServiceIdentifier?
    @State private var frameworkRanking: [FrameworkDetection] = []
    @AppStorage("showsDebugInspector") private var showsDebugInspector = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            content
        }
        .background(Theme.canvas)
        .themedWindowChrome()
        .navigationTitle(AppInfo.displayName)
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
        .inspector(isPresented: .constant(selectedService != nil)) {
            Group {
                if let service = selectedService {
                    ServiceDetailView(service: service, frameworkRanking: frameworkRanking)
                }
            }
            .inspectorColumnWidth(min: 290, ideal: 340, max: 430)
        }
        .task(id: selection) { await loadRanking() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Search

    private var searchBar: some View {
        @Bindable var store = store

        return HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            TextField("Search by project, framework, port or path", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)

            if !store.searchQuery.isEmpty {
                Button {
                    store.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .themedCard(cornerRadius: 8)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.groups.isEmpty {
            EmptyStateView(reason: emptyReason)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(store.groups) { group in
                        ProjectSection(group: group, selection: $selection)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
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
        return count == 1 ? "1 service running" : "\(count) services running"
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
        .frame(width: 940, height: 600)
}

#Preview("Empty") {
    DashboardView()
        .environment(ServicesStore.preview(services: []))
        .frame(width: 940, height: 600)
}
