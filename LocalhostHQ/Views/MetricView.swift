import SwiftUI

/// A single labelled metric tile, used in the detail inspector's metrics row.
struct MetricView: View {
    let label: String
    let value: String
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.4)
            }
            .foregroundStyle(.tertiary)

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// A key/value line in the inspector's detail list.
struct DetailRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false
    var selectable: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(.tertiary)

            Group {
                if selectable {
                    Text(value).textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .font(.system(size: 12, design: monospaced ? .monospaced : .default))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack(spacing: 8) {
            MetricView(label: "CPU", value: "7.2%", symbol: "cpu")
            MetricView(label: "Memory", value: "428 MB", symbol: "memorychip")
            MetricView(label: "Uptime", value: "1h 42m", symbol: "clock")
        }
        DetailRow(label: "Process", value: "/opt/homebrew/bin/node", monospaced: true)
    }
    .padding(16)
    .frame(width: 320)
}
