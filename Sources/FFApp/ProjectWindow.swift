import FFCore
import SwiftUI

/// A window showing one project's folder, key files, repositories, and links.
struct ProjectWindow: View {
    let name: String
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let project = model.project(named: name) {
            details(project)
        } else {
            Text("Project '\(name)' not found.").padding().navigationTitle(name)
        }
    }

    /// Path, git status, and Finder/terminal buttons for the project's own folder.
    private func folderSection(_ path: String) -> some View {
        Section {
            LabeledContent("Path") { Text(path).textSelection(.enabled) }
            LabeledContent("Git") {
                HStack {
                    GitLine(status: model.git[path])
                    Button { model.refreshGit([path]) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Refresh")
                        .accessibilityLabel("Refresh git status")
                }
            }
            HStack {
                Button("Open in Finder") { model.attempt { try Launcher.open(path) } }
                Button("Open in \(model.config.terminal.displayName)") {
                    model.attempt { try Launcher.openTerminal(at: path, app: model.config.terminal) }
                }
            }
        }
    }

    /// The form for one project: folder, key files, repositories, links, and notes.
    private func details(_ p: Project) -> some View {
        Form {
            if let path = p.path {
                folderSection(path)
            }
            if !p.keyFiles.isEmpty {
                Section("Key Files and Folders") {
                    ForEach(p.keyFiles, id: \.self) { KeyFileRow(project: p, file: $0) }
                }
            }
            if !p.repos.isEmpty {
                Section("Git Repositories") {
                    ForEach(p.repos, id: \.self) { RepoRow(project: p, repo: $0) }
                }
            }
            if !p.urls.isEmpty {
                Section("Links") {
                    ForEach(p.urls, id: \.url) { LinkRow(link: $0) }
                }
            }
            NotesEditor(project: p)
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(p.name)
        .toolbar {
            Button {
                model.settingsSelection = p.name
                openWindow(id: "settings")
            } label: {
                Label("Project Settings…", systemImage: "gearshape")
            }
            .help("Open Settings for this project (⌘,)")
            .keyboardShortcut(",")
        }
    }
}

/// An editable Notes section. Every change is saved at once.
struct NotesEditor: View {
    let project: Project
    @Environment(AppModel.self) private var model
    @State private var notes = ""

    var body: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .onChange(of: notes) { _, text in
                    if text != (project.notes ?? "") { model.update { try $0.setNotes(project.name, text) } }
                }
        }
        .onAppear { notes = project.notes ?? "" }
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

/// One key file or folder: opens it on click, or reveals it in Finder.
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

/// One repository: status, name, branch, and buttons to open it in Finder or the terminal.
struct RepoRow: View {
    let project: Project
    let repo: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let full = project.fullPath(of: repo)
        let exists = FileManager.default.fileExists(atPath: full)
        let status = model.git[full]
        HStack {
            Image(systemName: GitSymbol.name(for: status))
                .foregroundStyle(GitSymbol.color(for: status))
                .accessibilityHidden(true)
            Text(project.displayName(of: repo))
                .help((full as NSString).abbreviatingWithTildeInPath)
            if let status { Text(status.branch).foregroundStyle(.secondary) }
            Spacer()
            Text(exists ? GitSymbol.description(for: status) : "folder not found").foregroundStyle(.secondary)
            Button { model.attempt { try Launcher.open(full) } } label: { Image(systemName: "folder") }
                .help("Open in Finder")
                .accessibilityLabel("Open \(repo) in Finder")
            Button { model.attempt { try Launcher.openTerminal(at: full, app: model.config.terminal) } } label: {
                Image(systemName: "terminal")
            }
            .help("Open in \(model.config.terminal.displayName)")
            .accessibilityLabel("Open \(repo) in \(model.config.terminal.displayName)")
        }
        .buttonStyle(.borderless)
        .disabled(!exists)
    }
}

/// One project link: a clickable title, or plain secondary text when the URL is invalid.
struct LinkRow: View {
    let link: ProjectURL

    var body: some View {
        if let url = URL(string: link.url) {
            Link(link.title, destination: url)
        } else {
            Text(link.title).foregroundStyle(.secondary)
        }
    }
}
