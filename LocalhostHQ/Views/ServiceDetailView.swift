import SwiftUI

/// The inspector shown alongside the dashboard for the selected service.
struct ServiceDetailView: View {
    let service: LocalService
    var frameworkRanking: [FrameworkDetection] = []
    @AppStorage("showsDebugInspector") private var showsDebugInspector = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                metrics
                details
                if showsDebugInspector {
                    DebugInspectorView(service: service, ranking: frameworkRanking)
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.canvas)
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
                Circle()
                    .fill(Theme.running)
                    .frame(width: 6, height: 6)
                Text("Running")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.running)

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

    @ViewBuilder
    private var addressLine: some View {
        if let url = service.browserURL {
            Link(destination: url) {
                HStack(spacing: 5) {
                    Text(LocalhostURL.displayString(port: service.port, preferringTLS: url.scheme == "https") ?? url.absoluteString)
                        .font(.system(size: 12, design: .monospaced))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
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

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 7) {
            if service.supportsBrowserOpen {
                actionButton("Open", symbol: "safari", isProminent: true) {
                    ServiceActions.openInBrowser(service)
                }
            }
            if service.actionableDirectory != nil {
                actionButton("Finder", symbol: "folder") {
                    ServiceActions.revealInFinder(service)
                }
                actionButton("Terminal", symbol: "terminal") {
                    ServiceActions.openInTerminal(service)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .medium))
                Text(title).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isProminent ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isProminent ? Theme.accentMuted : Theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isProminent ? Theme.accent.opacity(0.3) : Theme.border, lineWidth: 0.5)
                    }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metrics

    private var metrics: some View {
        HStack(spacing: 7) {
            MetricView(
                label: "CPU",
                value: service.metrics?.cpuPercent.map(Format.cpuPrecise) ?? "—",
                symbol: "cpu",
                tint: Theme.textPrimary
            )
            MetricView(
                label: "Memory",
                value: service.metrics.map { Format.memory($0.residentMemoryBytes) } ?? "—",
                symbol: "memorychip",
                tint: Theme.textPrimary
            )
            MetricView(
                label: "Uptime",
                value: service.uptime.map(Format.uptime) ?? "—",
                symbol: "clock",
                tint: Theme.textPrimary
            )
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
                    if project.workingDirectory != project.packageRoot {
                        DetailRow(label: "Working dir", value: Format.path(project.workingDirectory), monospaced: true)
                    }
                    if let declaredName = project.manifest?.declaredName {
                        DetailRow(label: "Manifest name", value: declaredName, monospaced: true)
                    }
                    if let git = service.git {
                        DetailRow(label: "Git branch", value: git.branchName, monospaced: true)
                    }
                }
            } else if let cwd = service.process.workingDirectory {
                DetailGroup(title: "Project") {
                    DetailRow(label: "Working dir", value: Format.path(cwd), monospaced: true)
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
}

#Preview("Web service") {
    ServiceDetailView(service: SampleData.web)
        .frame(width: 340, height: 680)
        .preferredColorScheme(.dark)
}

#Preview("Infrastructure") {
    ServiceDetailView(service: SampleData.postgres)
        .frame(width: 340, height: 680)
        .preferredColorScheme(.dark)
}
