import SwiftUI

/// The running dot. A soft halo keeps it legible against both list backgrounds
/// without resorting to a saturated block of colour.
struct StatusIndicator: View {
    var category: ServiceCategory
    var diameter: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .stroke(color.opacity(0.28), lineWidth: diameter * 0.55)
            }
            .accessibilityHidden(true)
    }

    /// Infrastructure reads as steady blue, the developer's own servers as
    /// green: the colour carries the same information as the section heading.
    private var color: Color {
        switch category {
        case .database, .cache, .infrastructure: .blue
        default: .green
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        StatusIndicator(category: .web)
        StatusIndicator(category: .database)
        StatusIndicator(category: .generic, diameter: 10)
    }
    .padding(24)
}
