import AppKit
import FFCore
import SwiftUI

/// The menu bar menu. HIG: a menu bar extra shows a menu, not a popover.
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.loadError != nil {
            Text("Config File Has an Error — See Settings")
        } else if model.config.projects.isEmpty {
            Text("No Projects")
        } else {
            ForEach(model.config.projects, id: \.name) { project in
                if project.path.map({ FileManager.default.fileExists(atPath: $0) }) ?? true {
                    let status = model.combinedGit(project)
                    Button {
                        openWindow(value: project.name)
                        bringToFront(title: project.name)
                    } label: {
                        Label(GitSymbol.menuTitle(project.name, status), systemImage: GitSymbol.name(for: status))
                    }
                    .accessibilityLabel("\(project.name), \(GitSymbol.description(for: status))")
                } else {
                    Button {} label: { Label("\(project.name) — Folder Not Found", systemImage: "questionmark.folder") }
                        .disabled(true)
                }
            }
        }
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            bringToFront(title: "Frequent Finder Settings")
        }
        .keyboardShortcut(",")
        Button("Quit Frequent Finder") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Puts the window we just opened in front and asks for focus. macOS (cooperative activation)
/// refuses NSApp.activate() when the menu item was chosen with its key equivalent, which left the
/// window behind the frontmost app; orderFrontRegardless works without activation. In that case the
/// window is in front but takes keyboard focus only once clicked.
@MainActor private func bringToFront(title: String) {
    NSApp.activate()
    // The window gets its title on the next run-loop turn.
    DispatchQueue.main.async {
        guard let window = NSApp.windows.first(where: { $0.title == title && $0.isVisible }) else { return }
        window.orderFrontRegardless()
        window.makeKey()
    }
}

/// Git state as a symbol plus words, so it never relies on colour alone.
enum GitSymbol {
    static func name(for status: GitStatus?) -> String {
        guard let status else { return "circle.dashed" }
        return status.isDirty ? "pencil.circle" : "checkmark.circle"
    }

    static func color(for status: GitStatus?) -> Color {
        guard let status else { return .secondary }
        return status.isDirty ? .orange : .green
    }

    /// "clean", "3 changed, 2 to push, 1 to pull", ...
    static func description(for status: GitStatus?) -> String {
        guard let status else { return "not a git repository" }
        var parts = [status.isDirty ? "\(status.changes) changed" : "clean"]
        if status.ahead > 0 { parts.append("\(status.ahead) to push") }
        if status.behind > 0 { parts.append("\(status.behind) to pull") }
        return parts.joined(separator: ", ")
    }

    /// Project name plus "↑2 ↓1" when out of sync with its upstream.
    static func menuTitle(_ name: String, _ status: GitStatus?) -> String {
        guard let summary = status?.syncSummary, !summary.isEmpty else { return name }
        return "\(name)  \(summary)"
    }
}
