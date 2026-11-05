import AppKit
import FFCore
import SwiftUI

/// Our URL scheme: `frequentfinder://project/<UUID>` opens that project. Declared in scripts/make-app.sh.
let linkScheme = "frequentfinder"

/// UserDefaults key for the "Show in menu bar" setting.
let showInMenuBarKey = "showInMenuBar"

/// The app entry point: menu bar menu, project windows, the All Projects window, and Settings.
@main
struct FrequentFinderApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()
    @AppStorage(showInMenuBarKey) private var showInMenuBar = true

    var body: some Scene {
        MenuBarExtra("Frequent Finder", systemImage: "folder.badge.gearshape", isInserted: $showInMenuBar) {
            MenuContent().environment(model)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Project", for: String.self) { $name in
            ProjectWindow(name: name ?? "").environment(model)
        }
        .commands { NewProjectCommand(model: model) }
        .defaultSize(width: 440, height: 480)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        // Project links open here (ProjectWindow.openLink), never in the windows below.
        .handlesExternalEvents(matching: ["project"])

        Window("Frequent Finder", id: "all") {
            AllProjectsView().environment(model)
        }
        .defaultSize(width: 900, height: 600)
        // Reopen at launch if it was open when the app last quit. Our own flag, not system window
        // restoration, so it works whatever the "close windows when quitting" setting is.
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: allProjectsOpenKey) ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])

        Window("Frequent Finder Settings", id: "settings") {
            SettingsView().environment(model)
                .windowMinimizeBehavior(.disabled)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])
    }
}

/// Opening the app again (Finder, Spotlight) brings back a hidden menu bar icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set when the app starts quitting, so closing windows then is not mistaken for the user closing them.
    @MainActor static var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppDelegate.isTerminating = true
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: showInMenuBarKey)
        return true
    }
}

/// Replaces SwiftUI's automatic File > New Project Window (which opened an empty project window)
/// with New Project…, which opens Settings and adds a project as its + button does.
struct NewProjectCommand: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                model.pendingAddProject = true
                openWindow(id: "settings")
            }
            .keyboardShortcut("n")
        }
    }
}
