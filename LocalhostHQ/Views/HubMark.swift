import AppKit
import SwiftUI

/// Proportions of the Localhost HQ mark, as fractions of the mark's radius.
/// These mirror `Tools/GenerateAppIcon.swift`; changing one means changing both.
enum HubMarkGeometry {
    static let hubRadius: CGFloat = 0.235
    static let satelliteRadius: CGFloat = 0.150
    static let orbit: CGFloat = 0.625
    static let connectorWidth: CGFloat = 0.098
    static let angles: [CGFloat] = [90, 210, 330]

    /// Satellite centres for a mark of the given radius around `center`.
    /// Negated sine because SwiftUI's y axis grows downward while the icon
    /// generator's CoreGraphics context grows upward.
    static func satellites(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        angles.map { degrees in
            let radians = degrees * .pi / 180
            return CGPoint(
                x: center.x + cos(radians) * radius * orbit,
                y: center.y - sin(radians) * radius * orbit
            )
        }
    }
}

/// The app mark, drawn rather than shipped as an image so it tints correctly in
/// both appearances and stays crisp at any size.
struct HubMark: View {
    var tint: Color = .white
    /// Connector and satellite opacity, relative to the hub.
    var secondaryOpacity: Double = 0.62

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let satellites = HubMarkGeometry.satellites(center: center, radius: radius)
            let hubRadius = radius * HubMarkGeometry.hubRadius
            let satelliteRadius = radius * HubMarkGeometry.satelliteRadius

            var connectors = Path()
            for satellite in satellites {
                let dx = satellite.x - center.x
                let dy = satellite.y - center.y
                let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
                let unitX = dx / length, unitY = dy / length
                let inner = hubRadius * 0.82
                let outer = length - satelliteRadius * 0.82
                connectors.move(to: CGPoint(x: center.x + unitX * inner, y: center.y + unitY * inner))
                connectors.addLine(to: CGPoint(x: center.x + unitX * outer, y: center.y + unitY * outer))
            }
            context.stroke(
                connectors,
                with: .color(tint.opacity(secondaryOpacity * 0.9)),
                style: StrokeStyle(lineWidth: radius * HubMarkGeometry.connectorWidth, lineCap: .round)
            )

            for satellite in satellites {
                let rect = CGRect(
                    x: satellite.x - satelliteRadius,
                    y: satellite.y - satelliteRadius,
                    width: satelliteRadius * 2,
                    height: satelliteRadius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(secondaryOpacity + 0.26)))
            }

            let hubRect = CGRect(
                x: center.x - hubRadius,
                y: center.y - hubRadius,
                width: hubRadius * 2,
                height: hubRadius * 2
            )
            context.fill(Path(ellipseIn: hubRect), with: .color(tint))
        }
    }
}

/// The mark on its indigo squircle, for in-app branding.
struct HubMarkBadge: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.506, green: 0.549, blue: 0.973), Color(red: 0.310, green: 0.275, blue: 0.898)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                HubMark(tint: .white)
                    .frame(width: size * 0.88, height: size * 0.88)
            }
            .frame(width: size, height: size)
    }
}

// MARK: - Menu bar rendering

extension HubMark {
    /// Renders the mark as a monochrome template image.
    ///
    /// The menu bar requires a template so macOS can invert it for light and
    /// dark menu bars; the coloured badge cannot be used there.
    @MainActor
    static func menuBarImage(size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let radius = size / 2
            let center = CGPoint(x: radius, y: radius)
            let satellites = HubMarkGeometry.satellites(center: center, radius: radius)
            let hubRadius = radius * HubMarkGeometry.hubRadius
            let satelliteRadius = radius * HubMarkGeometry.satelliteRadius

            context.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor)
            context.setLineWidth(radius * HubMarkGeometry.connectorWidth)
            context.setLineCap(.round)
            for satellite in satellites {
                let dx = satellite.x - center.x, dy = satellite.y - center.y
                let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
                let unitX = dx / length, unitY = dy / length
                context.move(to: CGPoint(x: center.x + unitX * hubRadius * 0.82, y: center.y + unitY * hubRadius * 0.82))
                context.addLine(to: CGPoint(
                    x: center.x + unitX * (length - satelliteRadius * 0.82),
                    y: center.y + unitY * (length - satelliteRadius * 0.82)
                ))
            }
            context.strokePath()

            context.setFillColor(NSColor.black.withAlphaComponent(0.88).cgColor)
            for satellite in satellites {
                context.addArc(center: satellite, radius: satelliteRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                context.fillPath()
            }

            context.setFillColor(NSColor.black.cgColor)
            context.addArc(center: center, radius: hubRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

#Preview("Mark") {
    HStack(spacing: 24) {
        HubMarkBadge(size: 64)
        HubMark(tint: .accentColor).frame(width: 44, height: 44)
        Image(nsImage: HubMark.menuBarImage(size: 18))
    }
    .padding(32)
}
