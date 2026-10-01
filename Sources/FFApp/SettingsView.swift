import AppKit
import FFCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(showInMenuBarKey) private var showInMenuBar = true
    /// Selected project, by name, so it survives reordering.
    @State private var selection: String?
    @State private var confirmingRemove = false
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading) {
            if let loadError = model.loadError {
                Text(loadError).foregroundStyle(.red)
            }
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
            HStack(alignment: .top) {
                VStack(spacing: 0) {
                    List(selection: $selection) {
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
                if let project = selected {
                    ProjectEditor(project: project, selection: $selection).id(project.name)
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

    private var selected: Project? {
        selection.flatMap { model.project(named: $0) }
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

struct ProjectEditor: View {
    let project: Project
    @Binding var selection: String?
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var newURL = ""
    @State private var newLabel = ""
    /// Index of the link being edited; nil = adding a new one.
    @State private var editing: Int?

    var body: some View {
        Form {
            TextField("Name", text: $name)
                .focused($nameFocused)
                .onSubmit(rename)
                .onChange(of: nameFocused) { _, focused in if !focused { rename() } }
            LabeledContent("Path") {
                HStack {
                    Text(project.path).lineLimit(1).truncationMode(.middle)
                    Button("Choose…", action: choosePath)
                }
            }
            Section("Key Files and Folders") {
                ForEach(project.keyFiles, id: \.self) { file in
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
                Button("Add Files or Folders…", action: addFiles)
            }
            Section("Links") {
                ForEach(Array(project.urls.enumerated()), id: \.offset) { i, link in
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
                TextField("URL", text: $newURL)
                TextField("Label (optional)", text: $newLabel)
                HStack {
                    Button(editing == nil ? "Add Link" : "Save Link", action: saveLink)
                        .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing != nil { Button("Cancel", action: clearLink) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { name = project.name }
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
        panel.directoryURL = URL(fileURLWithPath: project.path)
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { try $0.setPath(project.name, to: url.path, cwd: "/") }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files or folders. ⌘-click to choose several."
        panel.directoryURL = URL(fileURLWithPath: project.path)
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
