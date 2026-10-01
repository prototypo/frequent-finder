import FFCore
import SwiftUI

struct ProjectWindow: View {
    let name: String
    @Environment(AppModel.self) private var model
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        if let project = model.project(named: name) {
            details(project)
        } else {
            Text("Project '\(name)' not found.").padding().navigationTitle(name)
        }
    }

    private func details(_ p: Project) -> some View {
        Form {
            Section {
                LabeledContent("Path") { Text(p.path).textSelection(.enabled) }
                LabeledContent("Git") {
                    HStack {
                        GitLine(status: model.git[p.path])
                        Button { model.refreshGit([p.path]) } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                            .help("Refresh")
                            .accessibilityLabel("Refresh git status")
                    }
                }
                HStack {
                    Button("Open in Finder") { model.attempt { try Launcher.open(p.path) } }
                    Button("Open \(model.config.terminal.displayName)") {
                        model.attempt { try Launcher.openTerminal(at: p.path, app: model.config.terminal) }
                    }
                }
            }
            if !p.keyFiles.isEmpty {
                Section("Key Files") {
                    ForEach(p.keyFiles, id: \.self) { KeyFileRow(root: p.path, file: $0) }
                }
            }
            if !p.urls.isEmpty {
                Section("Links") {
                    ForEach(p.urls, id: \.url) { link in
                        if let url = URL(string: link.url) {
                            Link(link.title, destination: url)
                        } else {
                            Text(link.title).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(p.name)
        .onAppear { model.refreshGit([p.path]) }
        .onChange(of: activeState) { _, state in
            if state == .key { model.refreshGit([p.path]) }
        }
    }
}

struct GitLine: View {
    let status: GitStatus?

    var body: some View {
        HStack(spacing: 6) {
            GitDot(status: status)
            if let status {
                Text(status.branch)
                Text(status.isDirty ? "\(status.changes) changed" : "clean").foregroundStyle(.secondary)
            } else {
                Text("Not a git repository").foregroundStyle(.secondary)
            }
        }
    }
}

struct KeyFileRow: View {
    let root: String
    let file: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let full = (root as NSString).appendingPathComponent(file)
        let exists = FileManager.default.fileExists(atPath: full)
        HStack {
            Button(file) { model.attempt { try Launcher.open(full) } }
                .buttonStyle(.link)
                .disabled(!exists)
            Spacer()
            Button { model.attempt { try Launcher.open("-R", full) } } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Show in Finder")
                .accessibilityLabel("Show \(file) in Finder")
                .disabled(!exists)
        }
    }
}
