import AppKit
import FFCore
import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    let store = ConfigStore()
    private(set) var config = Config()
    /// Set when projects.json cannot be read. Edits are blocked so the file is never overwritten.
    private(set) var loadError: String?
    /// The project selected in Settings, by name. Here so a project window can choose it.
    var settingsSelection: String?
    /// The last failed action, shown in the UI.
    var error: String?
    /// Git status by project path. Missing = not a git repo, or not checked yet.
    private(set) var git: [String: GitStatus] = [:]
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var timer: Timer?
    /// The All Projects window while it is open, so the menu can bring it to the front.
    @ObservationIgnored weak var allProjectsWindow: NSWindow?

    /// A menu cannot run code when it opens, so git status refreshes on load, every
    /// minute, and whenever one of our windows comes to the front.
    init() {
        reload()
        watch()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAllGit() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAllGit() }
        }
    }

    func reload() {
        do {
            config = try store.load()
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
        refreshAllGit()
    }

    /// The project folder and all its repos summed up, for the menu.
    func combinedGit(_ p: Project) -> GitStatus? {
        GitStatus.combine([p.path.flatMap { git[$0] }] + p.repos.map { git[p.fullPath(of: $0)] })
    }

    func project(named name: String) -> Project? {
        (try? config.index(of: name)).map { config.projects[$0] }
    }

    /// Applies a change to the latest file contents, saves it, and only then shows it.
    func update(_ change: (inout Config) throws -> Void) {
        do {
            config = try store.update(change)
            loadError = nil
            error = nil
        } catch FFError.badConfig(let detail) {
            loadError = "\(FFError.badConfig(detail))"
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

    func refreshAllGit() {
        refreshGit(config.projects.flatMap { p in [p.path].compactMap { $0 } + p.repos.map(p.fullPath(of:)) })
    }

    func refreshGit(_ paths: [String]) {
        Task.detached {
            let results = paths.map { ($0, Git.status(at: $0)) }
            await MainActor.run {
                for (path, status) in results { self.git[path] = status }
            }
        }
    }

    /// Watches the config folder so the display follows atomic saves (ours and the CLI's).
    // ponytail: display misses editors that write projects.json in place; harmless, since update() re-reads before saving.
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
