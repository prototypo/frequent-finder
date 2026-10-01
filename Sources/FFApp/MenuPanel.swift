import AppKit
import FFCore
import SwiftUI

struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let loadError = model.loadError {
                Text(loadError).foregroundStyle(.red).padding()
            } else if model.config.projects.isEmpty {
                Text("No projects yet. Add one in Settings.").foregroundStyle(.secondary).padding()
            } else {
                ForEach(model.config.projects, id: \.name) { project in
                    ProjectRow(project: project) {
                        openWindow(value: project.name)
                        NSApp.activate()
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    openWindow(id: "settings")
                    NSApp.activate()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .accessibilityLabel("Settings")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .padding(.top, 4)
        .frame(width: 280)
        .onAppear { model.refreshGit(model.config.projects.map(\.path)) }
        // The panel's view stays alive between openings, so onAppear alone goes stale. Refresh whenever a window of ours gets focus.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refreshGit(model.config.projects.map(\.path))
        }
    }
}

struct ProjectRow: View {
    let project: Project
    let action: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: project.path)
        Button(action: action) {
            HStack {
                GitDot(status: model.git[project.path])
                Text(project.name)
                Spacer()
                if !exists {
                    Text("folder not found").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(exists ? 1 : 0.5)
    }
}

/// Green = clean, orange = dirty, grey = not a git repository.
struct GitDot: View {
    let status: GitStatus?

    var body: some View {
        Circle()
            .fill(status.map { $0.isDirty ? Color.orange : .green } ?? .gray)
            .frame(width: 8, height: 8)
            .accessibilityLabel(status.map { $0.isDirty ? "Git: dirty" : "Git: clean" } ?? "Not a git repository")
    }
}
