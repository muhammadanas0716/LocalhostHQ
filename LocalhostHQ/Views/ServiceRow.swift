import SwiftUI

/// One service line.
///
/// Two lines, not four: identity and port on top, context below. Metrics sit on
/// the trailing edge so the eye can scan a column of ports down one side and a
/// column of costs down the other.
struct ServiceRow: View {
    let service: LocalService
    var isSelected: Bool = false
    var onSelect: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 11) {
                ServiceGlyph(
                    category: service.category,
                    symbolName: service.framework?.symbolName ?? "circle.dotted"
                )

                VStack(alignment: .leading, spacing: 2.5) {
                    Text(service.displayName)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(secondaryLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    PortBadge(port: service.port, isProminent: isSelected || isHovering)

                    if let metrics = metricsLine {
                        Text(metrics)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var backgroundFill: Color {
        if isSelected { return Theme.surfaceSelected }
        return isHovering ? Theme.surfaceHover : Theme.surface
    }

    /// `Next.js · main · ~/Code/dicee/apps/web`
    private var secondaryLine: String {
        var parts: [String] = []
        // Skip the framework when it already supplied the title.
        if let framework = service.framework, framework.displayName != service.displayName {
            parts.append(framework.displayName)
        }
        if let branch = service.git?.branchName { parts.append(branch) }
        if let directory = service.actionableDirectory { parts.append(Format.path(directory)) }
        // Falling back to the executable still tells the developer something.
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
    VStack(spacing: 4) {
        ServiceRow(service: SampleData.web)
        ServiceRow(service: SampleData.api, isSelected: true)
        ServiceRow(service: SampleData.postgres)
        ServiceRow(service: SampleData.jupyter)
        ServiceRow(service: SampleData.redis)
    }
    .padding(14)
    .frame(width: 600)
    .background(Theme.canvas)
    .preferredColorScheme(.dark)
}
