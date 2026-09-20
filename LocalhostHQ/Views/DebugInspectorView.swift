import SwiftUI

/// Raw discovery output for one service.
///
/// Makes misdetections diagnosable — the framework ranking in particular shows
/// *why* a label was chosen. Hidden behind a toggle in Settings.
struct DebugInspectorView: View {
    let service: LocalService
    let ranking: [FrameworkDetection]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Debug")
                .font(.system(size: 9.5, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.0) { label, value in
                    HStack(alignment: .top, spacing: 6) {
                        Text(label)
                            .frame(width: 94, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                }
            }

            if !ranking.isEmpty {
                Text("Framework ranking")
                    .font(.system(size: 9.5, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)

                ForEach(ranking, id: \.framework.id) { detection in
                    HStack(spacing: 6) {
                        Text(detection.framework.displayName)
                            .frame(width: 94, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", detection.confidence))
                            .foregroundStyle(.primary)
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                }
            }
        }
    }

    private var lines: [(String, String)] {
        var rows: [(String, String)] = [
            ("PID", String(service.pid)),
            ("Port", String(service.port)),
            ("Process", service.process.name),
            ("Origin", service.origin.rawValue),
            ("Bindings", service.listeningPort.bindingDescription),
            ("Family", service.listeningPort.familyDescription),
        ]
        rows.append(("Executable", service.process.executablePath ?? "—"))
        rows.append(("CWD", service.process.workingDirectory ?? "— (denied)"))
        rows.append(("Package root", service.project?.packageRoot ?? "—"))
        rows.append(("Repo root", service.project?.repositoryRoot ?? "—"))
        rows.append(("Manifest", service.project?.manifest?.kind.rawValue ?? "—"))
        rows.append(("Git branch", service.git?.branchName ?? "—"))
        rows.append(("Parent PID", service.process.parentPID.map(String.init) ?? "—"))
        return rows
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
    .frame(width: 320)
}
