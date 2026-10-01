import FFCore
import SwiftUI

@main
struct FrequentFinderApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Frequent Finder", systemImage: "folder.badge.gearshape") {
            MenuPanel().environment(model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Project", for: String.self) { $name in
            ProjectWindow(name: name ?? "").environment(model)
        }
        .defaultSize(width: 440, height: 480)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Frequent Finder Settings", id: "settings") {
            SettingsView().environment(model)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
