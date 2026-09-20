import SwiftUI

/// Shown when a graceful stop did not take effect.
///
/// Escalation to SIGKILL is never automatic: the choice is presented, with the
/// consequence spelled out, and Force Stop is styled as destructive.
struct ForceStopSheet: View {
    let prompt: ForceStopPrompt
    let onKeepWaiting: () -> Void
    let onForceStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.warning)
                Text("\(prompt.service.displayName) didn't stop")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("It was asked to shut down and hasn't exited after 5 seconds. \(processSummary) still running.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Force stopping ends it immediately. Unsaved work in that process is lost, and build caches can be left inconsistent.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Keep Waiting", action: onKeepWaiting)
                    .keyboardShortcut(.cancelAction)
                Button("Force Stop", role: .destructive, action: onForceStop)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.chrome)
    }

    private var processSummary: String {
        prompt.remainingPIDs.count == 1
            ? "PID \(prompt.remainingPIDs[0]) is"
            : "\(prompt.remainingPIDs.count) processes are"
    }
}

/// Explains who owns a blocked port, and offers to free it.
struct PortConflictSheet: View {
    let conflict: PortConflict
    let onCancel: () -> Void
    let onStopOwner: () -> Void
    let onInspect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.warning)
                Text("Port \(String(conflict.port)) is already in use")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Owned by")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .foregroundStyle(Theme.textTertiary)

                VStack(alignment: .leading, spacing: 5) {
                    Text(conflict.ownerDisplayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    ownerRow("Process", conflict.ownerName)
                    ownerRow("PID", String(conflict.ownerPID))
                    if let directory = conflict.ownerDirectory {
                        ownerRow("Directory", Format.path(directory))
                    }
                    if let uptime = conflict.uptime {
                        ownerRow("Started", "\(Format.uptime(uptime)) ago")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .themedCard()
            }

            if !conflict.isStoppable {
                Text("Localhost HQ can't stop this process — it belongs to macOS or another user.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let onInspect {
                    Button("Inspect", action: onInspect)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                if conflict.isStoppable {
                    Button("Stop Process", role: .destructive, action: onStopOwner)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.chrome)
    }

    private func ownerRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
        }
    }
}

/// Result of a project-wide restart or stop.
struct ProjectReportSheet: View {
    let report: ProjectOperationReport
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(report.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("\(report.succeededCount) succeeded · \(report.failedCount) failed")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(report.items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(item.succeeded ? Theme.running : Theme.danger)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textPrimary)
                            if let detail = item.detail {
                                Text(detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()

            HStack {
                Spacer()
                Button("Done", action: onDismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.chrome)
    }
}

#Preview("Port conflict") {
    PortConflictSheet(
        conflict: PortConflict(
            port: 3_000,
            ownerPID: 4_812,
            ownerName: "node",
            ownerService: nil,
            ownerIdentity: nil,
            ownerDirectory: "/Users/anas/Code/old-project",
            ownerStartedAt: Date().addingTimeInterval(-8_220),
            isStoppable: true
        ),
        onCancel: {}, onStopOwner: {}, onInspect: {}
    )
    .preferredColorScheme(.dark)
}

/// `PortConflict` is a value, not `Identifiable`; this wraps it for `.sheet(item:)`.
struct IdentifiedConflict: Identifiable {
    let conflict: PortConflict
    var id: Int { conflict.port }

    init(_ conflict: PortConflict) { self.conflict = conflict }
}
