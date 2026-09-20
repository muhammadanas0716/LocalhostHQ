import SwiftUI

/// A single labelled metric tile, used in the detail inspector's metrics row.
struct MetricView: View {
    let label: String
    let value: String
    var symbol: String?
    var tint: Color = Theme.textSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
            }
            .foregroundStyle(Theme.textTertiary)

            Text(value)
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .themedCard(cornerRadius: 8)
    }
}

/// A key/value line in the inspector's detail list.
struct DetailRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 11.5, design: monospaced ? .monospaced : .default))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Groups detail rows under a heading.
struct DetailGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            VStack(alignment: .leading, spacing: 7) { content }
        }
    }
}

#Preview {
    VStack(spacing: 14) {
        HStack(spacing: 7) {
            MetricView(label: "CPU", value: "7.2%", symbol: "cpu")
            MetricView(label: "Memory", value: "428 MB", symbol: "memorychip")
            MetricView(label: "Uptime", value: "1h 42m", symbol: "clock")
        }
        DetailGroup(title: "Process") {
            DetailRow(label: "Executable", value: "/opt/homebrew/bin/node", monospaced: true)
            DetailRow(label: "PID", value: "4812", monospaced: true)
        }
    }
    .padding(16)
    .frame(width: 340)
    .background(Theme.canvas)
    .preferredColorScheme(.dark)
}
