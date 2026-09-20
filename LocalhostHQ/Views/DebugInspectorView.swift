import SwiftUI

/// Raw discovery output for one service.
///
/// Makes misdetections diagnosable — the framework ranking in particular shows
/// *why* a label was chosen. Hidden behind a toggle in Settings.
struct DebugInspectorView: View {
    let service: LocalService
    let ranking: [FrameworkDetection]
    var controlRoot: ControlRoot?
    var launchDescriptor: LaunchDescriptor?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(Theme.border)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Debug")

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(lines, id: \.0) { label, value in
                        HStack(alignment: .top, spacing: 8) {
                            Text(label)
                                .frame(width: 92, alignment: .leading)
                                .foregroundStyle(Theme.textTertiary)
                            Text(value)
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }
                }
            }

            if let controlRoot {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Control root")
                    VStack(alignment: .leading, spacing: 3) {
                        debugLine("PID", String(controlRoot.pid))
                        debugLine("Name", controlRoot.name)
                        debugLine("Reason", controlRoot.reason)
                        debugLine("Members", controlRoot.memberPIDs.map(String.init).joined(separator: ", "))
                    }
                }
            }

            if let launchDescriptor {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Launch descriptor")
                    VStack(alignment: .leading, spacing: 3) {
                        debugLine("Executable", launchDescriptor.executableURL.path)
                        debugLine("Arguments", launchDescriptor.arguments.joined(separator: " "))
                        debugLine("Directory", Format.path(launchDescriptor.workingDirectory.path))
                        debugLine("Confidence", launchDescriptor.confidence.label)
                        debugLine("Recovered from", launchDescriptor.recoveredFrom)
                    }
                }
            }

            if !ranking.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Framework ranking")

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ranking, id: \.framework.id) { detection in
                            HStack(spacing: 8) {
                                Text(detection.framework.displayName)
                                    .frame(width: 92, alignment: .leading)
                                    .foregroundStyle(Theme.textSecondary)

                                // Bar makes the margin between candidates
                                // visible at a glance.
                                GeometryReader { proxy in
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(Theme.accent.opacity(0.35))
                                        .frame(width: proxy.size.width * detection.confidence, height: 4)
                                        .frame(maxHeight: .infinity, alignment: .center)
                                }
                                .frame(height: 10)

                                Text(String(format: "%.2f", detection.confidence))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .font(.system(size: 10, design: .monospaced))
                        }
                    }
                }
            }
        }
    }

    private func debugLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .frame(width: 92, alignment: .leading)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
        }
        .font(.system(size: 10, design: .monospaced))
    }

    private var lines: [(String, String)] {
        [
            ("PID", String(service.pid)),
            ("Parent PID", service.process.parentPID.map(String.init) ?? "—"),
            ("Port", String(service.port)),
            ("Process", service.process.name),
            ("Origin", service.origin.rawValue),
            ("Bindings", service.listeningPort.bindingDescription),
            ("Family", service.listeningPort.familyDescription),
            ("Executable", service.process.executablePath ?? "—"),
            ("CWD", service.process.workingDirectory ?? "— (denied)"),
            ("Package root", service.project?.packageRoot ?? "—"),
            ("Repo root", service.project?.repositoryRoot ?? "—"),
            ("Manifest", service.project?.manifest?.kind.rawValue ?? "—"),
            ("Git branch", service.git?.branchName ?? "—"),
        ]
    }
}

#Preview {
    DebugInspectorView(
        service: SampleData.web,
        ranking: [
            FrameworkDetection(framework: .nextJS, confidence: 0.98),
            FrameworkDetection(framework: .node, confidence: 0.50),
        ]
    )
    .padding(16)
    .frame(width: 340)
    .background(Theme.canvas)
    .preferredColorScheme(.dark)
}
