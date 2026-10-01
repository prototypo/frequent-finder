import AppKit
import FFCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Int?
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
                        ForEach(Array(model.config.projects.enumerated()), id: \.offset) { i, project in
                            Text(project.name).tag(i)
                        }
                    }
                    HStack {
                        iconButton("plus", "Add project") { addProject() }
                        iconButton("minus", "Remove project") { removeSelected() }.disabled(selected == nil)
                        iconButton("arrow.up", "Move up") { moveSelected(by: -1) }.disabled(selected == nil)
                        iconButton("arrow.down", "Move down") { moveSelected(by: 1) }.disabled(selected == nil)
                        Spacer()
                    }
                    .padding(4)
                }
                .frame(width: 200)
                if let project = selected {
                    ProjectEditor(project: project).id(selection)
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
        .frame(minWidth: 680, minHeight: 480)
    }

    private var selected: Project? {
        guard let i = selection, model.config.projects.indices.contains(i) else { return nil }
        return model.config.projects[i]
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add Project"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { try $0.add(path: url.path, cwd: "/") }
        if model.error == nil { selection = model.config.projects.count - 1 }
    }

    private func removeSelected() {
        guard let project = selected else { return }
        model.update { try $0.remove(project.name) }
        selection = nil
    }

    private func moveSelected(by offset: Int) {
        guard let project = selected else { return }
        model.update { try $0.move(project.name, by: offset) }
        selection = try? model.config.index(of: project.name)
    }
}

struct ProjectEditor: View {
    let project: Project
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
            Section("Key Files") {
                ForEach(project.keyFiles, id: \.self) { file in
                    HStack {
                        Text(file)
                        Spacer()
                        iconButton("minus.circle", "Remove \(file)") {
                            model.update { try $0.removeFiles(project.name, [file], cwd: "/") }
                        }
                    }
                }
                Button("Add Files…", action: addFiles)
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
        if name != project.name { model.update { try $0.rename(project.name, to: name) } }
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
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
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
