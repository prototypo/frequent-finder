import AppKit
import FFCore
import SwiftUI

/// UserDefaults key for the "Show in menu bar" setting.
let showInMenuBarKey = "showInMenuBar"

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
        .defaultSize(width: 440, height: 480)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Frequent Finder", id: "all") {
            AllProjectsView().environment(model)
        }
        .defaultSize(width: 900, height: 600)
        // Reopen at launch if it was open when the app last quit. Our own flag, not system window
        // restoration, so it works whatever the "close windows when quitting" setting is.
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: allProjectsOpenKey) ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        Window("Frequent Finder Settings", id: "settings") {
            SettingsView().environment(model)
                .windowMinimizeBehavior(.disabled)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
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
