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
        VStack(spacing: 16) {
            icon

            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 340)
            }

            if case .noServices = reason {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Self.examples, id: \.command) { example in
                        HStack(spacing: 9) {
                            Text(example.command)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: 204, alignment: .leading)

                            Text(example.label)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .themedCard()
                .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    private static let examples: [(command: String, label: String)] = [
        ("npm run dev", "Next.js, Vite, anything Node"),
        ("uvicorn main:app --reload", "FastAPI"),
        ("python manage.py runserver", "Django"),
        ("cargo run", "Rust"),
    ]

    @ViewBuilder
    private var icon: some View {
        switch reason {
        case .noServices:
            HubMark(tint: Theme.accent, secondaryOpacity: 0.5)
                .frame(width: 46, height: 46)
                .opacity(0.8)
        case .noMatches:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)
        case .scannerUnavailable:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.warning)
        }
    }

    private var title: String {
        switch reason {
        case .noServices: "Nothing running yet"
        case .noMatches: "No matches"
        case .scannerUnavailable: "Can't scan ports"
        }
    }

    private var message: String {
        switch reason {
        case .noServices:
            "Start a development server and it'll show up here on its own — no setup needed."
        case .noMatches(let query):
            "Nothing matches “\(query)”. Try a project name, framework, port or path."
        case .scannerUnavailable:
            "/usr/sbin/lsof is missing or isn't executable, so listening ports can't be enumerated."
        }
    }
}

#Preview("Empty") {
    EmptyStateView(reason: .noServices)
        .frame(width: 640, height: 480)
        .preferredColorScheme(.dark)
}

#Preview("No matches") {
    EmptyStateView(reason: .noMatches(query: "rails"))
        .frame(width: 640, height: 480)
        .preferredColorScheme(.dark)
}
