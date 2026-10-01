import Foundation

/// Opens things with macOS `open`: folders in Finder, files in their default app, URLs in the browser.
public enum Launcher {
    public static func open(_ args: String...) throws {
        let result = runProcess("/usr/bin/open", args)
        guard result.status == 0 else {
            let detail = result.err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw FFError.launchFailed(detail.isEmpty ? args.joined(separator: " ") : detail)
        }
    }

    /// By bundle ID, so it works wherever the terminal app is installed.
    public static func openTerminal(at path: String, app: TerminalApp) throws {
        try open("-b", app.bundleID, path)
    }
}
