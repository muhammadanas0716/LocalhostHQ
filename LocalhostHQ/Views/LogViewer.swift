import SwiftUI

/// Live log viewer for one service.
///
/// Rendering is `LazyVStack` inside a `ScrollView` so only visible lines are
/// built; with a 10,000-line buffer a plain `VStack` would construct every row
/// on every append.
struct LogViewer: View {
    let serviceKey: ServiceKey
    let serviceName: String
    let port: Int
    /// Present while the service is running, enabling restart-to-capture.
    let service: LocalService?

    @Environment(AppEnvironment.self) private var app
    @State private var query = ""
    @State private var levelFilter: LevelFilter = .all
    @State private var isFollowing = true
    @State private var wrapsLines = true

    private enum LevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case errors = "Errors"
        case warnings = "Warnings"
        var id: String { rawValue }

        var levels: Set<LogLevel>? {
            switch self {
            case .all: nil
            case .errors: [.error]
            case .warnings: [.warning]
            }
        }
    }

    private var store: LogStore { app.logs.store(for: serviceKey) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            controls
            Divider().overlay(Theme.border)
            content
        }
        .background(Theme.canvas)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(serviceName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            PortBadge(port: port)

            if store.source.isLive {
                StatePill(text: "Live", color: Theme.running)
            }

            Spacer()

            if store.droppedCount > 0 {
                Text("\(store.droppedCount) earlier lines dropped")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .help("The buffer keeps the most recent \(LogBuffer.defaultCapacity) lines.")
            }

            Button("Clear") { store.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .disabled(store.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Filter logs", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .themedCard(cornerRadius: 6)
            .frame(maxWidth: 260)

            Picker("", selection: $levelFilter) {
                ForEach(LevelFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)

            Spacer()

            Toggle("Follow", isOn: $isFollowing)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Toggle("Wrap", isOn: $wrapsLines)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let entries = store.filtered(query: query, levels: levelFilter.levels)

        if !store.source.isLive && store.isEmpty {
            unavailableState
        } else if entries.isEmpty {
            Text(store.isEmpty ? "No output yet." : "No lines match this filter.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            LogLineView(entry: entry, wraps: wrapsLines)
                                .id(entry.id)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: entries.last?.id) { _, newValue in
                    // Auto-scroll only while following; a user who scrolled up
                    // to read something must not be yanked back down.
                    guard isFollowing, let newValue else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newValue, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// The honest answer when the process was not started by Localhost HQ.
    private var unavailableState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 6) {
                Text("Live logs aren't available")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("This service was started outside Localhost HQ. macOS doesn't let one app read another's output after the fact — restart it here to capture logs.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 380)
            }

            if let service, service.capabilities.canRestart {
                Button {
                    Task { await app.controller.restart(service) }
                } label: {
                    Label("Restart and Capture Logs", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.controller.isBusy(service.key))
            } else if let service, let restriction = service.capabilities.restriction {
                Text(restriction.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

/// One log line. Errors and warnings get a coloured rail rather than coloured
/// text, which keeps the log readable instead of turning it into a terminal
/// light show.
private struct LogLineView: View {
    let entry: LogEntry
    let wraps: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(railColor)
                .frame(width: 2)

            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textTertiary.opacity(0.8))

            if entry.stream == .stderr {
                Text("err")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.warning.opacity(0.9))
            }

            Text(entry.message)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(messageColor)
                .lineLimit(wraps ? nil : 1)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1.5)
        .background(isHovering ? Theme.surfaceHover.opacity(0.6) : .clear)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Copy Line") { ServiceActions.copyToPasteboard(entry.message) }
        }
    }

    private var railColor: Color {
        switch entry.level {
        case .error: Theme.danger
        case .warning: Theme.warning
        default: .clear
        }
    }

    private var messageColor: Color {
        switch entry.level {
        case .error: Theme.danger.opacity(0.95)
        case .warning: Theme.textPrimary
        default: Theme.textSecondary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

/// Standalone log window.
struct LogWindowView: View {
    let serviceKey: ServiceKey?
    @Environment(AppEnvironment.self) private var app
    @Environment(ServicesStore.self) private var store

    var body: some View {
        if let serviceKey {
            let service = store.services.first { $0.key == serviceKey }
                ?? app.lifecycle.lastKnown[serviceKey]
            LogViewer(
                serviceKey: serviceKey,
                serviceName: service?.displayName ?? "Service",
                port: serviceKey.port,
                service: store.services.first { $0.key == serviceKey }
            )
        } else {
            Text("No service selected")
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
        }
    }
}
