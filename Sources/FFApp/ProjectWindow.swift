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
        WithNotes(project: p) { form(p) }
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

    private func form(_ p: Project) -> some View {
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
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}

/// A form on top and the project's notes filling the space below it. The form shrinks to fit
/// its rows, and scrolls when they need more room than the notes leave.
struct WithNotes<Content: View>: View {
    let project: Project
    @ViewBuilder let content: Content
    /// Height of the form's rows; nil until measured.
    @State private var formHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { g in
                    g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom
                } action: { _, height in formHeight = height }
                .frame(maxHeight: formHeight)
                .layoutPriority(1)
            Divider()
            NotesEditor(project: project)
        }
    }
}

/// The project's notes, shown as basic Markdown, with an Edit button to type them as plain text.
/// Every change is saved at once.
struct NotesEditor: View {
    let project: Project
    @Environment(AppModel.self) private var model
    @State private var notes = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Notes").font(.headline)
                Spacer()
                Button(editing ? "Done" : "Edit") {
                    editing.toggle()
                    focused = editing
                }
            }
            if editing {
                TextEditor(text: $notes)
                    .focused($focused)
                    .onChange(of: notes) { _, text in
                        if text != (project.notes ?? "") { model.update { try $0.setNotes(project.name, text) } }
                    }
            } else if notes.isEmpty {
                Text("No notes. Click Edit to add some; Markdown is supported.").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView { MarkdownText(text: notes).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            notes = project.notes ?? ""
            editing = notes.isEmpty
        }
    }
}

/// Text shown as basic Markdown: headings, lists, and inline styles and links.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                row(NoteLine(line))
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func row(_ line: NoteLine) -> some View {
        switch line {
        case .heading(let level, let text):
            Text(inline(text)).font(level == 1 ? .title2 : level == 2 ? .title3 : .headline)
        case .item(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline) {
                Text(marker)
                Text(inline(text))
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .text(let text):
            Text(inline(text.isEmpty ? " " : text))
        }
    }

    /// Bold, italic, code and links; the text unchanged if it is not valid Markdown.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
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
