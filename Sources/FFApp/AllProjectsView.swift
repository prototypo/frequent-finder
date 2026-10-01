import AppKit
import FFCore
import SwiftUI

/// UserDefaults key: true while the All Projects window is open, so it reopens at the next launch.
let allProjectsOpenKey = "allProjectsOpen"

/// The resizable All Projects window: projects on the left, the selected one's details on the right.
struct AllProjectsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("allProjectsSelection") private var selection: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(model.config.projects, id: \.name) { project in
                    let status = model.combinedGit(project)
                    Label {
                        Text(GitSymbol.menuTitle(project.name, status))
                    } icon: {
                        Image(systemName: GitSymbol.name(for: status)).foregroundStyle(GitSymbol.color(for: status))
                    }
                    .accessibilityLabel("\(project.name), \(GitSymbol.description(for: status))")
                    .tag(project.name)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let selection, model.project(named: selection) != nil {
                ProjectWindow(name: selection).id(selection)
            } else {
                Text("Select a project").foregroundStyle(.secondary)
                    .navigationTitle("Frequent Finder")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .background(WindowReader { window in
            model.allProjectsWindow = window
            // Saves and restores the window's size and place across runs.
            window.setFrameAutosaveName("AllProjects")
            UserDefaults.standard.set(true, forKey: allProjectsOpenKey)
            // A main window belongs in the Dock and ⌘-Tab while it is open.
            NSApp.setActivationPolicy(.regular)
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    // Quitting does not close windows, but guard anyway so the window still reopens next launch.
                    guard !AppDelegate.isTerminating else { return }
                    UserDefaults.standard.set(false, forKey: allProjectsOpenKey)
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        })
    }
}

/// Calls `onWindow` once with the NSWindow that hosts this view.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { ReaderView(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ReaderView: NSView {
        let onWindow: (NSWindow) -> Void
        private weak var seen: NSWindow?

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== seen else { return }
            seen = window
            onWindow(window)
        }
    }
}
