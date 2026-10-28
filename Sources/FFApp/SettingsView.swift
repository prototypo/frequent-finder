import AppKit
import FFCore
import ServiceManagement
import SwiftUI

/// The Settings window: general options and the list of projects with their editor.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(showInMenuBarKey) private var showInMenuBar = true
    @State private var confirmingRemove = false
    @State private var showInactive = false
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading) {
            if let loadError = model.loadError {
                Text(loadError).foregroundStyle(.red)
            }
            generalSettings
            HStack(alignment: .top) {
                projectList
                if let project = selected {
                    ProjectEditor(project: project, selection: selectionBinding).id(project.name)
                } else {
                    Text("Select a project").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(width: 700, height: 560)
        .onAppear(perform: addProjectIfRequested)
        .onChange(of: model.pendingAddProject) { addProjectIfRequested() }
        .confirmationDialog(
            "Remove “\(selected?.name ?? "")”?",
            isPresented: $confirmingRemove,
            presenting: selected
        ) { project in
            Button("Remove", role: .destructive) {
                model.update { try $0.remove(project.name) }
                selection = nil
            }
        } message: { _ in
            Text("Its key files and links are removed from Frequent Finder. Nothing on disk is changed.")
        }
    }

    /// Terminal choice, menu bar visibility, and open-at-login settings.
    private var generalSettings: some View {
        Form {
            Picker("Terminal", selection: Binding(
                get: { model.config.terminal },
                set: { terminal in model.update { $0.terminal = terminal } }
            )) {
                ForEach(TerminalApp.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle("Show in menu bar", isOn: $showInMenuBar)
                .help("When hidden, open Frequent Finder again from Finder or Spotlight to show it.")
            Toggle("Open at login", isOn: Binding(
                get: { openAtLogin },
                set: { on in
                    model.attempt {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    }
                    openAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))
        }
    }

    /// The project list with reorder and delete support, a collapsible list of inactive
    /// projects, and the add/remove button bar.
    private var projectList: some View {
        VStack(spacing: 0) {
            List(selection: selectionBinding) {
                ForEach(model.activeProjects, id: \.name) { Text($0.name).tag($0.name) }
                    .onMove { from, to in
                        // Indices count active projects only; move() counts them all.
                        let active = model.activeProjects
                        guard let i = from.first, let last = active.last else { return }
                        let all = model.config.projects.map(\.name)
                        let dest = to < active.count ? all.firstIndex(of: active[to].name)! : all.firstIndex(of: last.name)! + 1
                        model.update { try $0.move(active[i].name, to: dest) }
                    }
                let inactive = model.config.projects.filter { !$0.active }
                if !inactive.isEmpty {
                    DisclosureGroup("Inactive (\(inactive.count))", isExpanded: $showInactive) {
                        ForEach(inactive, id: \.name) { Text($0.name).foregroundStyle(.secondary).tag($0.name) }
                    }
                }
            }
            .onDeleteCommand { if selected != nil { confirmingRemove = true } }
            Divider()
            HStack(spacing: 0) {
                iconButton("plus", "Add Project…", size: CGSize(width: 24, height: 20)) { addProject() }
                Divider().frame(height: 16)
                iconButton("minus", "Remove Project", size: CGSize(width: 24, height: 20)) { confirmingRemove = true }
                    .disabled(selected == nil)
                Spacer()
            }
            .padding(2)
        }
        .frame(width: 200)
        .border(.separator)
    }

    /// Selected project, by name, so it survives reordering.
    private var selection: String? {
        get { model.settingsSelection }
        nonmutating set { model.settingsSelection = newValue }
    }

    private var selectionBinding: Binding<String?> {
        Binding(get: { model.settingsSelection }, set: { model.settingsSelection = $0 })
    }

    private var selected: Project? {
        selection.flatMap { model.project(named: $0) }
    }

    private func addProjectIfRequested() {
        guard model.pendingAddProject else { return }
        model.pendingAddProject = false
        // Let the window finish appearing before the folder panel opens.
        DispatchQueue.main.async { addProject() }
    }

    private func addProject() {
        guard let path = choosePaths(prompt: "Add Project").first else { return }
        model.update { try $0.add(path: path, cwd: "/") }
        if model.error == nil { selection = model.config.projects.last?.name }
    }
}

/// The settings form for one project: name, folder, key files, repositories, links, and notes.
/// Dropping a git repository folder adds it as a repository, other files and folders as key files,
/// and web URLs as links.
struct ProjectEditor: View {
    let project: Project
    @Binding var selection: String?
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var newURL = ""
    @State private var newLabel = ""
    /// Result of the last "Find Repositories", e.g. "Added 4 repositories."
    @State private var findResult: String?
    /// Index of the link being edited; nil = adding a new one.
    @State private var editing: Int?
    /// True while something is dragged over the form.
    @State private var dropTargeted = false

    var body: some View {
        WithNotes(project: project) { form }
        .onAppear { name = project.name }
        .dropDestination(for: URL.self, action: drop) { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).allowsHitTesting(false)
            }
        }
    }

    private var form: some View {
        Form {
            TextField("Name", text: $name)
                .focused($nameFocused)
                .onSubmit(rename)
                .onChange(of: nameFocused) { _, focused in if !focused { rename() } }
            pathRow
            Toggle("Active", isOn: Binding(
                get: { project.active },
                set: { on in model.update { try $0.setActive(project.name, on) } }
            ))
            .help("Inactive projects are hidden from the menu and All Projects.")
            keyFilesSection
            reposSection
            linksSection
        }
        .formStyle(.grouped)
    }


    /// The project's folder path with Choose and Clear buttons.
    private var pathRow: some View {
        LabeledContent("Path") {
            HStack {
                Text(project.path ?? "No folder").lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(project.path == nil ? .secondary : .primary)
                Button("Choose…", action: choosePath)
                if project.path != nil {
                    Button("Clear", action: clearPath)
                        .help("Make this a project with no folder. Its files and repos stay listed.")
                }
            }
        }
    }

    /// Lists the project's key files and folders with remove buttons and an add button.
    private var keyFilesSection: some View {
        Section("Key Files and Folders") {
            ForEach(project.keyFiles, id: \.self) { file in
                keyFileRow(file)
            }
            Button("Add Files or Folders…", action: addFiles)
        }
    }

    /// Lists the project's git repositories with remove buttons, plus add and find controls.
    private var reposSection: some View {
        Section("Git Repositories") {
            ForEach(project.repos, id: \.self) { repo in
                repoRow(repo)
            }
            HStack {
                Button("Add Repositories…", action: addRepos)
                Button("Find Repositories", action: findRepos)
                    .disabled(project.path == nil)
                    .help("Adds every git repository up to 3 folder levels below the project.")
                if let findResult { Text(findResult).foregroundStyle(.secondary) }
            }
        }
    }

    /// Lists the project's links with edit/remove buttons and the add/edit link form.
    private var linksSection: some View {
        Section("Links") {
            ForEach(Array(project.urls.enumerated()), id: \.offset) { i, link in
                linkRow(i, link)
            }
            TextField("URL", text: $newURL)
            TextField("Label (optional)", text: $newLabel)
            HStack {
                Button(editing == nil ? "Add Link" : "Save Link", action: saveLink)
                    .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
                if editing != nil { Button("Cancel", action: clearLink) }
            }
        }
    }

    /// One key file or folder: icon, name, and a remove button.
    private func keyFileRow(_ file: String) -> some View {
        HStack {
            KeyFileIcon(path: project.fullPath(of: file))
            Text(project.displayName(of: file))
                .help((project.fullPath(of: file) as NSString).abbreviatingWithTildeInPath)
            Spacer()
            iconButton("minus.circle", "Remove \(file)") {
                model.update { try $0.removeFiles(project.name, [file], cwd: "/") }
            }
        }
    }

    /// One git repository: name and a remove button.
    private func repoRow(_ repo: String) -> some View {
        HStack {
            Text(project.displayName(of: repo))
                .help((project.fullPath(of: repo) as NSString).abbreviatingWithTildeInPath)
            Spacer()
            iconButton("minus.circle", "Remove \(repo)") {
                model.update { try $0.removeRepos(project.name, [repo], cwd: "/") }
            }
        }
    }

    /// One link: title, URL when labelled, and edit and remove buttons.
    private func linkRow(_ i: Int, _ link: ProjectURL) -> some View {
        HStack {
            Text(link.title)
            if link.label != nil { Text(link.url).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            iconButton("pencil", "Edit \(link.title)") {
                editing = i
                newURL = link.url
                newLabel = link.label ?? ""
            }
            iconButton("minus.circle", "Remove \(link.title)") {
                model.update { try $0.removeURL(project.name, url: link.url) }
                clearLink()
            }
        }
    }

    private func rename() {
        guard name != project.name else { return }
        model.update { try $0.rename(project.name, to: name) }
        if model.error == nil { selection = name }
    }

    private func choosePath() {
        guard let path = choosePaths(prompt: "Choose", startAt: project.path).first else { return }
        model.update { try $0.setPath(project.name, to: path, cwd: "/") }
    }

    private func clearPath() {
        model.update { try $0.clearPath(project.name) }
    }

    /// Lets the user pick git repository folders to add to the project.
    private func addRepos() {
        let paths = choosePaths(prompt: "Add", multiple: true, startAt: project.path,
                                message: "Choose git repository folders. ⌘-click to choose several.")
        guard !paths.isEmpty else { return }
        model.update { try $0.addRepos(project.name, paths, cwd: "/") }
    }

    private func findRepos() {
        var added = 0
        model.update { added = try $0.findRepos(project.name) }
        if model.error == nil {
            findResult = added == 0 ? "No new repositories found." : "Added \(added) \(added == 1 ? "repository" : "repositories")."
        }
    }

    /// Lets the user pick files or folders to add as key files of the project.
    private func addFiles() {
        let paths = choosePaths(prompt: "Add", files: true, multiple: true, startAt: project.path,
                                message: "Choose files or folders. ⌘-click to choose several.")
        guard !paths.isEmpty else { return }
        model.update { try $0.addFiles(project.name, paths, cwd: "/") }
    }

    /// Adds dropped git repository folders as repositories, other files and folders as key files,
    /// and web URLs as links.
    private func drop(_ urls: [URL], _: CGPoint) -> Bool {
        let paths = urls.filter(\.isFileURL).map(\.path)
        let repos = paths.filter(Git.isRepository(at:))
        let files = paths.filter { !Git.isRepository(at: $0) }
        let links = urls.filter { !$0.isFileURL }.map(\.absoluteString)
        model.update { config in
            if !repos.isEmpty { try config.addRepos(project.name, repos, cwd: "/") }
            if !files.isEmpty { try config.addFiles(project.name, files, cwd: "/") }
            for link in links { try config.setURL(project.name, url: link) }
        }
        return model.error == nil
    }

    private func saveLink() {
        let url = newURL.trimmingCharacters(in: .whitespaces)
        model.update { try $0.setURL(project.name, url: url, label: newLabel, replacing: editing) }
        if model.error == nil { clearLink() }
    }

    private func clearLink() {
        editing = nil
        newURL = ""
        newLabel = ""
    }
}

/// Runs a folder-choosing open panel (files too if `files`) and returns the chosen paths, empty if cancelled.
@MainActor
private func choosePaths(prompt: String, files: Bool = false, multiple: Bool = false,
                         startAt: String? = nil, message: String? = nil) -> [String] {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = files
    panel.allowsMultipleSelection = multiple
    panel.directoryURL = startAt.map { URL(fileURLWithPath: $0) }
    if let message { panel.message = message }
    panel.prompt = prompt
    guard panel.runModal() == .OK else { return [] }
    return panel.urls.map(\.path)
}

/// A borderless SF Symbol button with a tooltip and an accessibility label, optionally fixed to `size`.
private func iconButton(_ symbol: String, _ label: String, size: CGSize? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).frame(width: size?.width, height: size?.height) }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
}
