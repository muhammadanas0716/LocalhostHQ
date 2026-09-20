import SwiftUI

/// The app's visual language.
///
/// Localhost HQ commits to a single near-black appearance rather than tracking
/// the system one. The palette sits darker than macOS's own dark mode so the
/// indigo accent and the running indicators carry the colour, and everything
/// else recedes.
enum Theme {

    // MARK: - Surfaces

    /// Window background. Near-black with a trace of blue, which reads as
    /// deeper than a neutral grey without the harshness of pure black.
    static let canvas = Color(red: 0.043, green: 0.043, blue: 0.055)
    /// Titlebar and footer chrome, a shade above the canvas.
    static let chrome = Color(red: 0.063, green: 0.063, blue: 0.078)
    /// Resting surface for rows and cards.
    static let surface = Color(red: 0.078, green: 0.078, blue: 0.094)
    /// Hover state.
    static let surfaceHover = Color(red: 0.110, green: 0.110, blue: 0.133)
    /// Selected state.
    static let surfaceSelected = Color(red: 0.145, green: 0.145, blue: 0.180)

    static let border = Color(red: 0.169, green: 0.169, blue: 0.204)
    static let borderStrong = Color(red: 0.231, green: 0.231, blue: 0.278)

    // MARK: - Text

    static let textPrimary = Color(red: 0.949, green: 0.949, blue: 0.965)
    static let textSecondary = Color(red: 0.612, green: 0.616, blue: 0.671)
    static let textTertiary = Color(red: 0.420, green: 0.424, blue: 0.478)

    // MARK: - Accents

    /// Brighter than the icon's indigo so it holds up against near-black.
    static let accent = Color(red: 0.514, green: 0.529, blue: 0.980)
    static let accentMuted = Color(red: 0.514, green: 0.529, blue: 0.980).opacity(0.14)

    static let running = Color(red: 0.239, green: 0.839, blue: 0.549)
    static let warning = Color(red: 0.984, green: 0.749, blue: 0.141)
    static let danger = Color(red: 0.984, green: 0.443, blue: 0.443)

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 9
    static let rowCornerRadius: CGFloat = 8
    static let chipCornerRadius: CGFloat = 7
}

// MARK: - Category colour

extension ServiceCategory {
    /// A distinct hue per kind of service. Gives the dashboard a friendly range
    /// of colour while still encoding what each row actually is.
    var accentColor: Color {
        switch self {
        case .web: Color(red: 0.545, green: 0.545, blue: 0.973)        // indigo
        case .api: Color(red: 0.310, green: 0.820, blue: 0.773)        // teal
        case .database: Color(red: 0.376, green: 0.647, blue: 0.980)   // blue
        case .cache: Color(red: 0.984, green: 0.443, blue: 0.522)      // rose
        case .notebook: Color(red: 0.984, green: 0.749, blue: 0.141)   // amber
        case .infrastructure: Color(red: 0.580, green: 0.639, blue: 0.722)
        case .generic: Color(red: 0.631, green: 0.635, blue: 0.690)
        }
    }

    var friendlyLabel: String {
        switch self {
        case .web: "Web"
        case .api: "API"
        case .database: "Database"
        case .cache: "Cache"
        case .notebook: "Notebook"
        case .infrastructure: "Infrastructure"
        case .generic: "Service"
        }
    }
}

// MARK: - Building blocks

/// Framework glyph on a tinted rounded chip, with the running dot tucked into
/// its corner so identity and status read as one element.
struct ServiceGlyph: View {
    let category: ServiceCategory
    var symbolName: String
    var size: CGFloat = 30
    var showsStatusDot: Bool = true
    /// Reflects runtime state, not just "discovered".
    var statusColor: Color = Theme.running

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.chipCornerRadius, style: .continuous)
            .fill(category.accentColor.opacity(0.16))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.chipCornerRadius, style: .continuous)
                    .strokeBorder(category.accentColor.opacity(0.22), lineWidth: 0.5)
            }
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(category.accentColor)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if showsStatusDot {
                    Circle()
                        .fill(statusColor)
                        .frame(width: size * 0.26, height: size * 0.26)
                        .overlay {
                            Circle().strokeBorder(Theme.surface, lineWidth: size * 0.065)
                        }
                        .offset(x: size * 0.10, y: size * 0.10)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Monospaced port badge.
struct PortBadge: View {
    let port: Int
    var isProminent: Bool = false

    var body: some View {
        Text(String(port))
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(isProminent ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isProminent ? Theme.accentMuted : Color.white.opacity(0.05))
            )
            .accessibilityLabel("port \(port)")
    }
}

/// Small uppercase section label.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Theme.textTertiary)
    }
}

extension View {
    /// Card treatment shared by rows, panels and the log-style surfaces.
    func themedCard(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 0.5)
                }
        )
    }
}
