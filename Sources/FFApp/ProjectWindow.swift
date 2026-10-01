import FFCore
import SwiftUI

struct ProjectWindow: View {
    let name: String
    @Environment(AppModel.self) private var model

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
                    Button("Open in \(model.config.terminal.displayName)") {
                        model.attempt { try Launcher.openTerminal(at: p.path, app: model.config.terminal) }
                    }
                }
            }
            if !p.keyFiles.isEmpty {
                Section("Key Files and Folders") {
                    ForEach(p.keyFiles, id: \.self) { KeyFileRow(project: p, file: $0) }
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
    }
}

struct GitLine: View {
    let status: GitStatus?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: GitSymbol.name(for: status))
                .foregroundStyle(GitSymbol.color(for: status))
                .accessibilityHidden(true)
            if let status { Text(status.branch) }
            Text(GitSymbol.description(for: status)).foregroundStyle(.secondary)
        }
    }
}

struct KeyFileRow: View {
    let project: Project
    let file: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let full = project.fullPath(of: file)
        let exists = FileManager.default.fileExists(atPath: full)
        HStack {
            KeyFileIcon(path: full)
            Button(project.displayName(of: file)) { model.attempt { try Launcher.open(full) } }
                .help((full as NSString).abbreviatingWithTildeInPath)
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

/// A folder or document symbol for a key file. Missing items show the document symbol.
struct KeyFileIcon: View {
    let path: String

    var body: some View {
        var isDir: ObjCBool = false
        let folder = FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        return Image(systemName: folder ? "folder" : "doc")
            .foregroundStyle(.secondary)
            .frame(width: 16)
            .accessibilityLabel(folder ? "Folder" : "File")
    }
}
