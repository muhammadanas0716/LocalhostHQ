import SwiftUI

/// The inspector shown alongside the dashboard for the selected service.
struct ServiceDetailView: View {
    let service: LocalService
    var frameworkRanking: [FrameworkDetection] = []

    @Environment(AppEnvironment.self) private var app
    @Environment(ServicesStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage("showsDebugInspector") private var showsDebugInspector = false

    @State private var processTree: ProcessNode?
    @State private var showsTree = false

    private var state: ServiceRuntimeState { app.lifecycle.state(for: service.key) }
    private var operation: ServiceOperation? { app.controller.operation(for: service.key) }
    private var events: [ServiceEvent] { app.lifecycle.events(for: service.key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                if let failure = failureBanner { failure }
                metrics
                details
                processTreeSection
                recentEvents
                if showsDebugInspector {
                    DebugInspectorView(
                        service: service,
                        ranking: frameworkRanking,
                        controlRoot: service.controlRoot,
                        launchDescriptor: service.launchDescriptor
                    )
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.canvas)
        .task(id: showsTree) {
            guard showsTree else { return }
            processTree = await store.processTree(for: service)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                ServiceGlyph(
                    category: service.category,
                    symbolName: service.framework?.symbolName ?? "circle.dotted",
                    size: 34,
                    showsStatusDot: false
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(service.category.friendlyLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            HStack(spacing: 6) {
                Circle().fill(stateColor).frame(width: 6, height: 6)
                Text(operation?.kind.label ?? state.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(stateColor)

                if service.process.isRestricted {
                    Text("· limited access")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .help("macOS denied inspection of this process, so some fields are unavailable.")
                }
            }

            addressLine
        }
    }

    private var stateColor: Color {
        switch state {
        case .running: Theme.running
        case .stopping, .restarting, .starting: Theme.warning
        case .stopped(.unexpected, _), .failed: Theme.danger
        default: Theme.textTertiary
        }
    }

    @ViewBuilder
    private var addressLine: some View {
        if let url = service.browserURL {
            Link(destination: url) {
                HStack(spacing: 5) {
                    Text(LocalhostURL.displayString(port: service.port, preferringTLS: url.scheme == "https") ?? url.absoluteString)
                        .font(.system(size: 12, design: .monospaced))
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        } else {
            Text("\(service.listeningPort.displayHost):\(String(service.port))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Failure

    @ViewBuilder
    private var failureBanner: (some View)? {
        let message: String? = switch state {
        case .failed(let text): text
        case .stopped(.unexpected, let info): unexpectedExitMessage(info)
        default: nil
        }

        if let message {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(state.label)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(Theme.danger)

                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let diagnosis = app.logs.existingStore(for: service.key)?.diagnosis {
                    Text(diagnosis.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 7) {
                    Button("View Logs") {
                        openWindow(id: LogWindow.identifier, value: service.key)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)

                    if service.capabilities.canRestart {
                        Button("Restart") { Task { await app.controller.restart(service) } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.danger.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.danger.opacity(0.3), lineWidth: 0.5)
                    }
            )
        }
    }

    private func unexpectedExitMessage(_ info: ExitInfo?) -> String {
        var parts: [String] = []
        if let code = info?.exitCode { parts.append("Exit code \(code)") }
        if let runtime = info?.runtime { parts.append("ran for \(Format.uptime(runtime))") }
        if let summary = info?.diagnosis?.summary { parts.append(summary) }
        return parts.isEmpty
            ? "The process disappeared without Localhost HQ asking it to stop."
            : parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if service.capabilities.canOpenInBrowser {
                    actionButton("Open", symbol: "safari", isProminent: true) {
                        ServiceActions.openInBrowser(service)
                    }
                }
                actionButton("Logs", symbol: "text.alignleft") {
                    openWindow(id: LogWindow.identifier, value: service.key)
                }
                if service.capabilities.canRestart {
                    actionButton("Restart", symbol: "arrow.clockwise", isDisabled: operation != nil) {
                        Task { await app.controller.restart(service) }
                    }
                }
                Spacer(minLength: 0)
            }

            // Destructive actions are separated from the common ones.
            if service.capabilities.canStop {
                Divider().overlay(Theme.border)
                HStack(spacing: 7) {
                    actionButton("Stop", symbol: "stop.fill", isDestructive: true, isDisabled: operation != nil) {
                        Task { await app.controller.stop(service) }
                    }
                    Spacer(minLength: 0)
                }
            } else if let restriction = service.capabilities.restriction {
                Text(restriction.explanation)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if service.capabilities.canRestart == false, service.capabilities.canStop {
                Text(restartUnavailableReason)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var restartUnavailableReason: String {
        guard let descriptor = service.launchDescriptor else {
            return "Restart is unavailable: Localhost HQ could not reconstruct how this service was started."
        }
        return "Restart is unavailable: the recovered command (\(descriptor.displayCommand)) is not reliable enough to rerun."
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        isProminent: Bool = false,
        isDestructive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .medium))
                Text(title).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(foreground(isProminent: isProminent, isDestructive: isDestructive, isDisabled: isDisabled))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isProminent ? Theme.accentMuted : (isDestructive ? Theme.danger.opacity(0.12) : Theme.surface))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                isProminent ? Theme.accent.opacity(0.3)
                                    : (isDestructive ? Theme.danger.opacity(0.3) : Theme.border),
                                lineWidth: 0.5
                            )
                    }
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func foreground(isProminent: Bool, isDestructive: Bool, isDisabled: Bool) -> Color {
        if isDisabled { return Theme.textTertiary.opacity(0.5) }
        if isDestructive { return Theme.danger }
        if isProminent { return Theme.accent }
        return Theme.textSecondary
    }

    // MARK: - Metrics

    private var metrics: some View {
        HStack(spacing: 7) {
            MetricView(label: "CPU", value: service.metrics?.cpuPercent.map(Format.cpuPrecise) ?? "—", symbol: "cpu", tint: Theme.textPrimary)
            MetricView(label: "Memory", value: service.metrics.map { Format.memory($0.residentMemoryBytes) } ?? "—", symbol: "memorychip", tint: Theme.textPrimary)
            MetricView(label: "Uptime", value: service.uptime.map(Format.uptime) ?? "—", symbol: "clock", tint: Theme.textPrimary)
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailGroup(title: "Service") {
                if let framework = service.framework {
                    DetailRow(label: "Framework", value: framework.displayName)
                    if let runtime = framework.runtime {
                        DetailRow(label: "Runtime", value: runtime.displayName)
                    }
                }
                DetailRow(label: "Port", value: String(service.port), monospaced: true)
                DetailRow(label: "Listening on", value: service.listeningPort.bindingDescription, monospaced: true)
            }

            if let project = service.project {
                DetailGroup(title: "Project") {
                    if let packageRoot = project.packageRoot {
                        DetailRow(label: "Package", value: Format.path(packageRoot), monospaced: true)
                    }
                    if let repositoryRoot = project.repositoryRoot, repositoryRoot != project.packageRoot {
                        DetailRow(label: "Repository", value: Format.path(repositoryRoot), monospaced: true)
                    }
                    if let git = service.git {
                        DetailRow(label: "Git branch", value: git.branchName, monospaced: true)
                    }
                }
            }

            DetailGroup(title: "Process") {
                DetailRow(label: "PID", value: String(service.pid), monospaced: true)
                if let parent = service.process.parentPID {
                    DetailRow(label: "Parent PID", value: String(parent), monospaced: true)
                }
                if let executable = service.process.executablePath {
                    DetailRow(label: "Executable", value: executable, monospaced: true)
                }
                if let command = service.process.commandLine {
                    DetailRow(label: "Command", value: command, monospaced: true)
                }
            }
        }
    }

    // MARK: - Process tree

    @ViewBuilder
    private var processTreeSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                showsTree.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showsTree ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    SectionLabel(text: "Process Tree")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsTree {
                if let processTree {
                    ProcessTreeView(
                        root: processTree,
                        controlRootPID: service.controlRoot?.pid,
                        controlledPIDs: Set(service.controlRoot?.memberPIDs ?? [])
                    )
                } else {
                    Text("Building tree…")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    // MARK: - Events

    @ViewBuilder
    private var recentEvents: some View {
        let recent = events.suffix(6).reversed()
        if !recent.isEmpty {
            DetailGroup(title: "Recent Events") {
                ForEach(Array(recent)) { event in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: event.kind.symbolName)
                            .font(.system(size: 9))
                            .foregroundStyle(event.kind.isProblem ? Theme.danger : Theme.textTertiary)
                            .frame(width: 12)

                        Text(Self.timeFormatter.string(from: event.timestamp))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)

                        Text(event.message)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

#Preview("Web service") {
    ServiceDetailView(service: SampleData.web)
        .frame(width: 340, height: 760)
        .environment(AppEnvironment.preview(services: SampleData.all))
        .environment(ServicesStore.preview(services: SampleData.all))
        .preferredColorScheme(.dark)
}
