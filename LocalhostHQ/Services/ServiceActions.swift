import AppKit
import Foundation
import OSLog

/// The safe, read-only actions Part 1 offers.
///
/// Kept out of the views so availability rules live with the model
/// (`LocalService.supportsBrowserOpen`) and the views only render them.
@MainActor
struct ServiceActions {
    /// `nonisolated` so the completion handler below, which runs off the main
    /// actor, can reach it.
    nonisolated private static let logger = Logger(subsystem: AppInfo.subsystem, category: "Actions")

    static func openInBrowser(_ service: LocalService) {
        guard let url = service.browserURL else { return }
        NSWorkspace.shared.open(url)
    }

    static func revealInFinder(_ service: LocalService) {
        guard let directory = service.actionableDirectory else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory)
    }

    /// Opens the user's terminal at the service's package directory.
    ///
    /// `NSWorkspace.open(_:withApplicationAt:)` hands the folder to the
    /// terminal as a document, which both Terminal.app and iTerm treat as
    /// "open a shell here".
    static func openInTerminal(_ service: LocalService) {
        guard let directory = service.actionableDirectory else { return }
        let folder = URL(fileURLWithPath: directory)

        guard let terminal = preferredTerminalApplication() else {
            NSWorkspace.shared.open(folder)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: configuration) { _, error in
            if let error {
                logger.error("Opening terminal failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Prefers iTerm when installed, since a developer who has it usually wants
    /// it; otherwise the system Terminal.
    private static func preferredTerminalApplication() -> URL? {
        let identifiers = ["com.googlecode.iterm2", "com.apple.Terminal"]
        for identifier in identifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        return nil
    }
}
