import SwiftUI

/// Shown when discovery found nothing, or when a search matched nothing.
struct EmptyStateView: View {
    enum Reason {
        case noServices
        case noMatches(query: String)
        /// `lsof` is missing, so discovery cannot run at all.
        case scannerUnavailable
    }

    let reason: Reason

    var body: some View {
        VStack(spacing: 14) {
            icon

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if case .noServices = reason {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(["npm run dev", "python app.py", "cargo run"], id: \.self) { command in
                        Text(command)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var icon: some View {
        switch reason {
        case .noServices:
            HubMark(tint: .secondary, secondaryOpacity: 0.5)
                .frame(width: 44, height: 44)
                .opacity(0.65)
        case .noMatches:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
        case .scannerUnavailable:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch reason {
        case .noServices: "No local services found."
        case .noMatches: "No matching services"
        case .scannerUnavailable: "Cannot scan ports"
        }
    }

    private var message: String {
        switch reason {
        case .noServices:
            "Start a development server and it will automatically appear here."
        case .noMatches(let query):
            "Nothing matches “\(query)”. Search by project, framework, port or path."
        case .scannerUnavailable:
            "/usr/sbin/lsof is missing or not executable, so listening ports cannot be enumerated."
        }
    }
}

#Preview("Empty") {
    EmptyStateView(reason: .noServices).frame(width: 560, height: 420)
}

#Preview("No matches") {
    EmptyStateView(reason: .noMatches(query: "rails")).frame(width: 560, height: 420)
}
