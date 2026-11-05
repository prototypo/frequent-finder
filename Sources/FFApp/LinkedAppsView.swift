import AppKit
import FFCore
import SwiftUI

extension LinkedApp {
    /// Where the app is installed; nil when macOS cannot find it.
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
}

/// Settings list of apps that get an "Open in" button on every project.
/// Drop an app from Finder or the Dock here, or use Add App….
struct LinkedAppsView: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false

    var body: some View {
        // Not LabeledContent: in a Form its label became every button's accessibility name.
        VStack(alignment: .leading, spacing: 6) {
            Text("Linked Apps").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.config.linkedApps, id: \.bundleID, content: row)
                Button("Add App…", action: chooseApp)
                Text("Drop an app here. Each project then gets an Open in button for it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2).opacity(targeted ? 1 : 0))
            .dropDestination(for: URL.self) { urls, _ in add(urls) } isTargeted: { targeted = $0 }
        }
    }

    private func row(_ app: LinkedApp) -> some View {
        HStack {
            if let url = app.appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            Text(app.name)
            if app.appURL == nil { Text("Not installed").foregroundStyle(.secondary) }
            Spacer()
            Button { model.update { $0.linkedApps.remove(bundleID: app.bundleID) } } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove \(app.name)")
                .accessibilityLabel("Remove \(app.name)")
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Link"
        if panel.runModal() == .OK, let url = panel.url { _ = add([url]) }
    }

    private func add(_ urls: [URL]) -> Bool {
        let apps = urls.filter(\.isFileURL)
        guard !apps.isEmpty else { return false }
        model.update { config in
            for url in apps { try config.linkedApps.add(LinkedApp(appAt: url), selfBundleID: Bundle.main.bundleIdentifier) }
        }
        return model.error == nil
    }
}

/// One "Open in <app>" button per installed linked app; nothing when there are none.
struct OpenInButtons: View {
    let project: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        let apps = model.config.linkedApps.filter { $0.appURL != nil }
        if !apps.isEmpty {
            HStack {
                ForEach(apps, id: \.bundleID) { app in
                    Button("Open in \(app.name)") { model.attempt { try app.open(project) } }
                }
            }
        }
    }
}
