import SwiftUI

/// One service line.
///
/// Two lines, not four: the identity and port on top, everything else on a
/// single secondary line. Metrics sit on the trailing edge so the eye can scan
/// a column of ports down one side and a column of costs down the other.
struct ServiceRow: View {
    let service: LocalService
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            StatusIndicator(category: service.category)

            Image(systemName: service.framework?.symbolName ?? "circle.dotted")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(secondaryLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(":\(String(service.port))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))

                if let metrics = metricsLine {
                    Text(metrics)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// `Next.js · main · ~/Code/dicee/apps/web`
    private var secondaryLine: String {
        var parts: [String] = []
        if let framework = service.framework { parts.append(framework.displayName) }
        if let branch = service.git?.branchName { parts.append(branch) }
        if let directory = service.actionableDirectory { parts.append(Format.path(directory)) }
        if parts.isEmpty { parts.append(service.process.name) }
        return parts.joined(separator: " · ")
    }

    /// `7% · 428 MB · 1h 42m`, omitting whatever the kernel would not give us.
    private var metricsLine: String? {
        var parts: [String] = []
        if let cpu = service.metrics?.cpuPercent { parts.append(Format.cpu(cpu)) }
        if let memory = service.metrics?.residentMemoryBytes { parts.append(Format.memory(memory)) }
        if let uptime = service.uptime { parts.append(Format.uptime(uptime)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var accessibilityDescription: String {
        "\(service.displayName), port \(service.port), \(secondaryLine)"
    }
}

#Preview("Rows") {
    VStack(spacing: 0) {
        ServiceRow(service: SampleData.web)
        ServiceRow(service: SampleData.api, isSelected: true)
            .background(.selection, in: RoundedRectangle(cornerRadius: 6))
        ServiceRow(service: SampleData.postgres)
        ServiceRow(service: SampleData.jupyter)
    }
    .padding(12)
    .frame(width: 560)
}
