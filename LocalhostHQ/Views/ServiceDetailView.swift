import SwiftUI

/// The inspector shown alongside the dashboard for the selected service.
struct ServiceDetailView: View {
    let service: LocalService
    var frameworkRanking: [FrameworkDetection] = []
    @AppStorage("showsDebugInspector") private var showsDebugInspector = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: service.framework?.symbolName ?? "circle.dotted")
                    .font(.system(size: 15))
                    .foregroundStyle(.tint)

                Text(service.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                StatusIndicator(category: service.category, diameter: 6)
                Text("Running")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if service.process.isRestricted {
                    Text("· limited access")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .help("macOS denied inspection of this process, so some fields are unavailable.")
                }
            }

            if let url = service.browserURL {
                Link(destination: url) {
                    Text(LocalhostURL.displayString(port: service.port, preferringTLS: url.scheme == "https") ?? url.absoluteString)
                        .font(.system(size: 12, design: .monospaced))
                }
                .buttonStyle(.link)
            } else {
                Text("\(service.listeningPort.displayHost):\(String(service.port))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            if service.supportsBrowserOpen {
                Button {
                    ServiceActions.openInBrowser(service)
                } label: {
                    Label("Open", systemImage: "safari")
                }
            }
            if service.actionableDirectory != nil {
                Button {
                    ServiceActions.revealInFinder(service)
                } label: {
                    Label("Finder", systemImage: "folder")
                }
                Button {
                    ServiceActions.openInTerminal(service)
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Metrics

    private var metrics: some View {
        HStack(spacing: 8) {
            MetricView(
                label: "CPU",
                value: service.metrics?.cpuPercent.map(Format.cpuPrecise) ?? "—",
                symbol: "cpu"
            )
            MetricView(
                label: "Memory",
                value: service.metrics.map { Format.memory($0.residentMemoryBytes) } ?? "—",
                symbol: "memorychip"
            )
            MetricView(
                label: "Uptime",
                value: service.uptime.map(Format.uptime) ?? "—",
                symbol: "clock"
            )
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let framework = service.framework {
                DetailRow(
                    label: "Framework",
                    value: [framework.displayName, framework.runtime?.displayName]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
            }

            DetailRow(label: "PID", value: String(service.pid), monospaced: true)

            if let project = service.project {
                if let packageRoot = project.packageRoot {
                    DetailRow(label: "Project", value: Format.path(packageRoot), monospaced: true)
                }
                if let repositoryRoot = project.repositoryRoot, repositoryRoot != project.packageRoot {
                    DetailRow(label: "Repository", value: Format.path(repositoryRoot), monospaced: true)
                }
                if project.workingDirectory != project.packageRoot {
                    DetailRow(label: "Working Directory", value: Format.path(project.workingDirectory), monospaced: true)
                }
                if let declaredName = project.manifest?.declaredName {
                    DetailRow(label: "Package", value: declaredName, monospaced: true)
                }
            } else if let cwd = service.process.workingDirectory {
                DetailRow(label: "Working Directory", value: Format.path(cwd), monospaced: true)
            }

            if let git = service.git {
                DetailRow(label: "Git", value: git.branchName, monospaced: true)
            }

            DetailRow(label: "Listening On", value: service.listeningPort.bindingDescription, monospaced: true)

            if let executable = service.process.executablePath {
                DetailRow(label: "Executable", value: executable, monospaced: true)
            }
            if let command = service.process.commandLine {
                DetailRow(label: "Command", value: command, monospaced: true)
            }
        }
    }
}

#Preview("Detail") {
    ServiceDetailView(service: SampleData.web)
        .frame(width: 320, height: 620)
}

#Preview("Infrastructure") {
    ServiceDetailView(service: SampleData.postgres)
        .frame(width: 320, height: 620)
}
