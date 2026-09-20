import SwiftUI

/// One service line, now actionable.
///
/// Controls appear on hover or selection rather than permanently, so a dense
/// list stays readable: five buttons on every row would drown the information
/// they sit beside.
struct ServiceRow: View {
    let service: LocalService
    var isSelected: Bool = false
    var onSelect: () -> Void = {}

    @Environment(AppEnvironment.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var isHovering = false

    private var state: ServiceRuntimeState { app.lifecycle.state(for: service.key) }
    private var operation: ServiceOperation? { app.controller.operation(for: service.key) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 11) {
                ServiceGlyph(
                    category: service.category,
                    symbolName: service.framework?.symbolName ?? "circle.dotted",
                    statusColor: statusColor
                )

                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 6) {
                        Text(service.displayName)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let badge = stateBadge {
                            StatePill(text: badge.text, color: badge.color)
                        }
                    }

                    Text(secondaryLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 10)

                if showsControls {
                    ServiceRowControls(service: service)
                        .transition(.opacity)
                } else {
                    VStack(alignment: .trailing, spacing: 3) {
                        PortBadge(port: service.port, isProminent: isSelected)
                        if let metrics = metricsLine {
                            Text(metrics)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    private var showsControls: Bool {
        (isHovering || isSelected) && !state.isTerminated
    }

    private var statusColor: Color {
        switch state {
        case .running: Theme.running
        case .stopping, .restarting, .starting: Theme.warning
        case .stopped(.unexpected, _), .failed: Theme.danger
        case .stopped(.requested, _): Theme.textTertiary
        case .unknown: Theme.textTertiary
        }
    }

    private var stateBadge: (text: String, color: Color)? {
        if let operation { return (operation.kind.label, Theme.warning) }
        switch state {
        case .running: return nil
        case .stopped(.unexpected, _): return ("Exited", Theme.danger)
        case .stopped(.requested, _): return ("Stopped", Theme.textTertiary)
        case .failed: return ("Failed", Theme.danger)
        case .starting: return ("Starting…", Theme.warning)
        case .restarting: return ("Restarting…", Theme.warning)
        case .stopping: return ("Stopping…", Theme.warning)
        case .unknown: return nil
        }
    }

    private var backgroundFill: Color {
        if isSelected { return Theme.surfaceSelected }
        return isHovering ? Theme.surfaceHover : Theme.surface
    }

    private var borderColor: Color {
        if isSelected { return Theme.accent.opacity(0.45) }
        if case .stopped(.unexpected, _) = state { return Theme.danger.opacity(0.35) }
        if case .failed = state { return Theme.danger.opacity(0.35) }
        return .clear
    }

    /// `Next.js · main · ~/Code/dicee/apps/web`
    private var secondaryLine: String {
        var parts: [String] = []
        if let framework = service.framework, framework.displayName != service.displayName {
            parts.append(framework.displayName)
        }
        if let branch = service.git?.branchName { parts.append(branch) }
        if let directory = service.actionableDirectory { parts.append(Format.path(directory)) }
        if parts.isEmpty { parts.append(service.process.name) }
        return parts.joined(separator: " · ")
    }

    private var metricsLine: String? {
        var parts: [String] = []
        if let cpu = service.metrics?.cpuPercent { parts.append(Format.cpu(cpu)) }
        if let memory = service.metrics?.residentMemoryBytes { parts.append(Format.memory(memory)) }
        if let uptime = service.uptime { parts.append(Format.uptime(uptime)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var accessibilityDescription: String {
        "\(service.displayName), port \(service.port), \(state.label), \(secondaryLine)"
    }
}

/// Compact control cluster: the two common actions, then an overflow menu that
/// holds everything destructive.
private struct ServiceRowControls: View {
    let service: LocalService
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openWindow) private var openWindow

    private var isBusy: Bool { app.controller.isBusy(service.key) }

    var body: some View {
        HStack(spacing: 4) {
            if service.capabilities.canOpenInBrowser {
                IconButton(symbol: "safari", help: "Open in browser") {
                    ServiceActions.openInBrowser(service)
                }
            }

            IconButton(symbol: "text.alignleft", help: "View logs") {
                openWindow(id: LogWindow.identifier, value: service.key)
            }

            if service.capabilities.canRestart {
                IconButton(symbol: "arrow.clockwise", help: "Restart", isDisabled: isBusy) {
                    Task { await app.controller.restart(service) }
                }
            }

            Menu {
                ServiceContextMenu(service: service)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .foregroundStyle(Theme.textSecondary)
        }
        .fixedSize()
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var isDisabled: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering && !isDisabled ? Theme.surfaceSelected : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
        .help(help)
    }

    private var foreground: Color {
        if isDisabled { return Theme.textTertiary.opacity(0.5) }
        if isDestructive { return Theme.danger }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }
}

/// Small state chip shown beside a service name.
struct StatePill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.15))
            )
    }
}

#Preview("Rows") {
    VStack(spacing: 4) {
        ServiceRow(service: SampleData.web)
        ServiceRow(service: SampleData.api, isSelected: true)
        ServiceRow(service: SampleData.postgres)
    }
    .padding(14)
    .frame(width: 640)
    .background(Theme.canvas)
    .environment(AppEnvironment.preview(services: SampleData.all))
    .preferredColorScheme(.dark)
}
