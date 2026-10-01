import FFCore
import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    let store = ConfigStore()
    private(set) var config = Config()
    /// Set when projects.json cannot be read. Edits are blocked so the file is never overwritten.
    private(set) var loadError: String?
    /// The last failed action, shown in the UI.
    var error: String?
    /// Git status by project path. Missing = not a git repo, or not checked yet.
    private(set) var git: [String: GitStatus] = [:]
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    init() {
        reload()
        watch()
    }

    func reload() {
        do {
            config = try store.load()
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
    }

    func project(named name: String) -> Project? {
        (try? config.index(of: name)).map { config.projects[$0] }
    }

    /// Applies a change to a copy, saves it, and only then shows it.
    func update(_ change: (inout Config) throws -> Void) {
        guard loadError == nil else {
            error = "The config file cannot be read, so changes are turned off. Fix or delete it first."
            return
        }
        var copy = config
        do {
            try change(&copy)
            try store.save(copy)
            config = copy
            error = nil
        } catch {
            self.error = "\(error)"
        }
    }

    /// Runs an action that may fail (open a folder, a terminal...) and shows the error.
    func attempt(_ action: () throws -> Void) {
        do {
            try action()
            error = nil
        } catch {
            self.error = "\(error)"
        }
    }

    func refreshGit(_ paths: [String]) {
        Task.detached {
            let results = paths.map { ($0, Git.status(at: $0)) }
            await MainActor.run {
                for (path, status) in results { self.git[path] = status }
            }
        }
    }

    /// Watches the config folder. Atomic saves (ours and the CLI's) replace the file, which changes the folder.
    // ponytail: misses editors that write projects.json in place; watch the file itself too if that matters.
    private func watch() {
        let dir = store.url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
