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

    /// `file` relative to the project's folder. Tries the paths as given first, then with
    /// symlinks resolved (file pickers may return `/private/var/...` for `/var/...`).
    public func relativePath(of file: String, in name: String, cwd: String) throws -> String {
        let root = projects[try index(of: name)].path
        let full = Self.absolutePath(file, cwd: cwd)
        let resolve = { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        for (r, f) in [(root, full), (resolve(root), resolve(full))] where f.hasPrefix(r + "/") {
            return String(f.dropFirst(r.count + 1))
        }
        throw FFError.fileOutsideProject(full)
    }

    public mutating func addFiles(_ name: String, _ files: [String], cwd: String) throws {
        let i = try index(of: name)
        for file in files {
            let full = Self.absolutePath(file, cwd: cwd)
            guard FileManager.default.fileExists(atPath: full) else { throw FFError.fileNotFound(full) }
            let rel = try relativePath(of: file, in: name, cwd: cwd)
            if !projects[i].keyFiles.contains(rel) { projects[i].keyFiles.append(rel) }
        }
    }

    /// Each file may be the stored relative path, or a path (absolute or relative to `cwd`) to the file.
    public mutating func removeFiles(_ name: String, _ files: [String], cwd: String) throws {
        let i = try index(of: name)
        for file in files {
            var rel = file
            if !projects[i].keyFiles.contains(file) { rel = try relativePath(of: file, in: name, cwd: cwd) }
            guard let j = projects[i].keyFiles.firstIndex(of: rel) else { throw FFError.notInList(rel) }
            projects[i].keyFiles.remove(at: j)
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
