import Foundation

/// Every edit the app and the CLI can make. Each one throws `FFError` and leaves
/// the caller's copy partly changed on error, so callers save only on success.
extension Config {
    /// Expands `~`, joins a relative path to `cwd`, and removes `.`/`..` and a trailing `/`.
    public static func absolutePath(_ path: String, cwd: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let full = expanded.hasPrefix("/") ? expanded : (cwd as NSString).appendingPathComponent(expanded)
        return URL(fileURLWithPath: full).standardizedFileURL.path
    }

    public static func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https": return !(url.host() ?? "").isEmpty
        case "file": return true
        default: return false
        }
    }

    public func index(of name: String) throws -> Int {
        guard let i = projects.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw FFError.noSuchProject(name)
        }
        return i
    }

    /// Throws if `name` is blank or used by a project other than the one at `owner`.
    private func checkName(_ name: String, owner: Int? = nil) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw FFError.emptyName }
        if let i = try? index(of: name), i != owner { throw FFError.duplicateName(name) }
    }

    private static func directory(_ path: String, cwd: String) throws -> String {
        let full = absolutePath(path, cwd: cwd)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else {
            throw FFError.notADirectory(full)
        }
        return full
    }

    public mutating func add(path: String, name: String? = nil, cwd: String) throws {
        let full = try Self.directory(path, cwd: cwd)
        let name = name ?? (full as NSString).lastPathComponent
        try checkName(name)
        projects.append(Project(name: name, path: full))
    }

    public mutating func remove(_ name: String) throws {
        projects.remove(at: try index(of: name))
    }

    public mutating func rename(_ name: String, to newName: String) throws {
        let i = try index(of: name)
        try checkName(newName, owner: i)
        projects[i].name = newName
    }

    public mutating func setPath(_ name: String, to path: String, cwd: String) throws {
        let i = try index(of: name)
        projects[i].path = try Self.directory(path, cwd: cwd)
    }

    /// Moves a project in front of the one at `destination`, counted before the move
    /// (SwiftUI List `.onMove` semantics). Out-of-range destinations stop at the ends.
    public mutating func move(_ name: String, to destination: Int) throws {
        let i = try index(of: name)
        let d = min(max(destination, 0), projects.count)
        projects.insert(projects.remove(at: i), at: d > i ? d - 1 : d)
    }

    /// How `file` is stored: relative to the project folder when inside it, else absolute.
    /// Tries the paths as given first, then with symlinks resolved (file pickers may
    /// return `/private/var/...` for `/var/...`).
    public func keyFilePath(of file: String, in name: String, cwd: String) throws -> String {
        let root = projects[try index(of: name)].path
        let full = Self.absolutePath(file, cwd: cwd)
        let resolve = { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        for (r, f) in [(root, full), (resolve(root), resolve(full))] where f.hasPrefix(r + "/") {
            return String(f.dropFirst(r.count + 1))
        }
        return full
    }

    public mutating func addFiles(_ name: String, _ files: [String], cwd: String) throws {
        try addItems(\.keyFiles, name, files, cwd: cwd) { full in
            guard FileManager.default.fileExists(atPath: full) else { throw FFError.fileNotFound(full) }
        }
    }

    /// Each file may be the stored path, or a path (absolute or relative to `cwd`) to the item.
    public mutating func removeFiles(_ name: String, _ files: [String], cwd: String) throws {
        try removeItems(\.keyFiles, name, files, cwd: cwd)
    }

    public mutating func addRepos(_ name: String, _ paths: [String], cwd: String) throws {
        try addItems(\.repos, name, paths, cwd: cwd) { full in
            guard Git.isRepository(at: full) else { throw FFError.notARepository(full) }
        }
    }

    public mutating func removeRepos(_ name: String, _ paths: [String], cwd: String) throws {
        try removeItems(\.repos, name, paths, cwd: cwd)
    }

    /// Adds every repository found under the project folder. Returns how many were new.
    @discardableResult
    public mutating func findRepos(_ name: String) throws -> Int {
        let i = try index(of: name)
        let before = projects[i].repos.count
        try addRepos(name, Git.findRepositories(under: projects[i].path), cwd: "/")
        return projects[i].repos.count - before
    }

    /// Adds paths to a project's list after `check` accepts each one's full path. Duplicates are ignored.
    private mutating func addItems(_ list: WritableKeyPath<Project, [String]>, _ name: String, _ paths: [String],
                                   cwd: String, check: (String) throws -> Void) throws {
        let i = try index(of: name)
        for path in paths {
            try check(Self.absolutePath(path, cwd: cwd))
            let key = try keyFilePath(of: path, in: name, cwd: cwd)
            if !projects[i][keyPath: list].contains(key) { projects[i][keyPath: list].append(key) }
        }
    }

    private mutating func removeItems(_ list: WritableKeyPath<Project, [String]>, _ name: String, _ paths: [String],
                                      cwd: String) throws {
        let i = try index(of: name)
        for path in paths {
            var key = path
            if !projects[i][keyPath: list].contains(path) { key = try keyFilePath(of: path, in: name, cwd: cwd) }
            guard let j = projects[i][keyPath: list].firstIndex(of: key) else { throw FFError.notInList(key) }
            projects[i][keyPath: list].remove(at: j)
        }
    }

    /// Replaces the URL at `replacing`, or the entry with the same URL, or appends. A blank label is stored as nil.
    public mutating func setURL(_ name: String, url: String, label: String? = nil, replacing index: Int? = nil) throws {
        let i = try self.index(of: name)
        guard Self.isValidURL(url) else { throw FFError.badURL(url) }
        let label = label.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let entry = ProjectURL(url: url, label: label)
        if let j = index {
            guard projects[i].urls.indices.contains(j) else { throw FFError.notInList("link \(j)") }
            projects[i].urls[j] = entry
        } else if let j = projects[i].urls.firstIndex(where: { $0.url == url }) {
            projects[i].urls[j] = entry
        } else {
            projects[i].urls.append(entry)
        }
    }

    public mutating func removeURL(_ name: String, url: String) throws {
        let i = try index(of: name)
        guard let j = projects[i].urls.firstIndex(where: { $0.url == url }) else { throw FFError.notInList(url) }
        projects[i].urls.remove(at: j)
    }
}
