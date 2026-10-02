import AppKit
import FFCore
import ServiceManagement
import SwiftUI

/// The Settings window: general options and the list of projects with their editor.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(showInMenuBarKey) private var showInMenuBar = true
    @State private var confirmingRemove = false
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

    /// The project list with reorder and delete support, and the add/remove button bar.
    private var projectList: some View {
        VStack(spacing: 0) {
            List(selection: selectionBinding) {
                ForEach(model.config.projects, id: \.name) { Text($0.name).tag($0.name) }
                    .onMove { from, to in
                        guard let i = from.first else { return }
                        let name = model.config.projects[i].name
                        model.update { try $0.move(name, to: to) }
                    }
            }
            .onDeleteCommand { if selected != nil { confirmingRemove = true } }
            Divider()
            HStack(spacing: 0) {
                listButton("plus", "Add Project…") { addProject() }
                Divider().frame(height: 16)
                listButton("minus", "Remove Project") { confirmingRemove = true }
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add Project"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { try $0.add(path: url.path, cwd: "/") }
        if model.error == nil { selection = model.config.projects.last?.name }
    }

    /// The small +/− buttons under a list, as in System Settings.
    private func listButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 20) }
            .buttonStyle(.borderless)
            .help(label)
            .accessibilityLabel(label)
    }
}

/// The settings form for one project: name, folder, key files, repositories, and links.
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

    var body: some View {
        Form {
            TextField("Name", text: $name)
                .focused($nameFocused)
                .onSubmit(rename)
                .onChange(of: nameFocused) { _, focused in if !focused { rename() } }
            pathRow
            keyFilesSection
            reposSection
            linksSection
        }
        .formStyle(.grouped)
        .onAppear { name = project.name }
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = project.path.map { URL(fileURLWithPath: $0) }
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { try $0.setPath(project.name, to: url.path, cwd: "/") }
    }

    private func clearPath() {
        model.update { try $0.clearPath(project.name) }
    }

    /// Lets the user pick git repository folders to add to the project.
    private func addRepos() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = project.path.map { URL(fileURLWithPath: $0) }
        panel.message = "Choose git repository folders. ⌘-click to choose several."
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        model.update { try $0.addRepos(project.name, panel.urls.map(\.path), cwd: "/") }
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files or folders. ⌘-click to choose several."
        panel.directoryURL = project.path.map { URL(fileURLWithPath: $0) }
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        model.update { try $0.addFiles(project.name, panel.urls.map(\.path), cwd: "/") }
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

/// A borderless SF Symbol button with a tooltip and an accessibility label.
private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol) }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
}
