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
            ForEach(model.config.projects, id: \.name) { ProjectMenuItem(project: $0) }
        }
        Divider()
        Button("Open All Projects") {
            // Become a regular (Dock) app before activating: switching while already active leaves
            // the menu bar unchanged. The window also does this, for when it reopens at launch.
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "all")
            bringToFront { $0 === model.allProjectsWindow }
        }
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            bringToFront { $0.title == "Frequent Finder Settings" }
        }
        .keyboardShortcut(",")
        Button("Quit Frequent Finder") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// One project's menu item: opens its window, or a disabled item when its folder is missing.
struct ProjectMenuItem: View {
    let project: Project
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if project.path.map({ FileManager.default.fileExists(atPath: $0) }) ?? true {
            let status = model.combinedGit(project)
            Button {
                openWindow(value: project.name)
                bringToFront { $0.title == project.name }
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

/// Puts the window we just opened in front and asks for focus. macOS (cooperative activation)
/// refuses NSApp.activate() when the menu item was chosen with its key equivalent, which left the
/// window behind the frontmost app; orderFrontRegardless works without activation. In that case the
/// window is in front but takes keyboard focus only once clicked.
@MainActor private func bringToFront(_ isTarget: @escaping (NSWindow) -> Bool) {
    NSApp.activate()
    // The window gets its title on the next run-loop turn.
    DispatchQueue.main.async {
        guard let window = NSApp.windows.first(where: { $0.isVisible && isTarget($0) }) else { return }
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
