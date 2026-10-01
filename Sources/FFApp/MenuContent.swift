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
                if FileManager.default.fileExists(atPath: project.path) {
                    let status = model.git[project.path]
                    Button {
                        openWindow(value: project.name)
                        bringToFront(title: project.name)
                    } label: {
                        Label(project.name, systemImage: GitSymbol.name(for: status))
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

    static func description(for status: GitStatus?) -> String {
        guard let status else { return "not a git repository" }
        return status.isDirty ? "\(status.changes) changed" : "clean"
    }
}
