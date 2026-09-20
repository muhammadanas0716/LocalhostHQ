import AppKit
import SwiftUI

/// Blends the window chrome into the app's canvas.
///
/// SwiftUI has no API for the titlebar's own fill, so the hosting `NSWindow` is
/// configured directly: without this the toolbar sits as a visibly lighter
/// strip above a near-black window.
struct WindowChromeConfigurator: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The view has no window during `makeNSView`; defer until it is placed.
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Theme.chrome)
        // Transparent, but the title stays: it is how macOS identifies the
        // window in Mission Control and the Window menu.
        window.titlebarAppearsTransparent = true
    }
}

extension View {
    /// Applies the dark window chrome. Invisible; attach as a background.
    func themedWindowChrome() -> some View {
        background(WindowChromeConfigurator().frame(width: 0, height: 0))
    }
}
