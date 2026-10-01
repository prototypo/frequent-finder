# Frequent Finder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app plus an `ff` CLI that list the user's projects and give one-click access to each project's folder, terminal, git status, key files and URLs.

**Architecture:** One Swift package. `FFCore` (library) holds the config model, JSON load/save, all edit commands, git status, CLI argument handling and the `open` launcher. `ff` (CLI) and `FrequentFinder` (SwiftUI `MenuBarExtra` app) are thin layers over `FFCore`. Both read and write `~/.config/frequent-finder/projects.json`; the app watches that folder and reloads.

**Tech Stack:** Swift 6.4 toolchain (Swift 5 language mode), SwiftUI, AppKit (`NSOpenPanel`), ServiceManagement (`SMAppService`), Swift Testing (`import Testing`). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-01-frequent-finder-design.md`

## Global Constraints

- macOS only. Package platform: `.macOS(.v15)` (needed for `defaultLaunchBehavior` / `restorationBehavior`; this Mac runs macOS 27).
- No dependencies beyond the Swift toolchain and system frameworks. No ArgumentParser.
- Config file: `~/.config/frequent-finder/projects.json`; env var `FF_CONFIG` overrides it (used for manual testing).
- JSON keys: `terminal` (`"terminal"` | `"iterm"`), `projects[]` with `name`, `path`, `keyFiles`, `urls[]` (`url`, optional `label`). Missing `keyFiles`/`urls`/`terminal` decode to defaults.
- Project names are unique, compared case-insensitively.
- Saves are atomic (`Data.write(options: .atomic)`). A file that fails to parse is never overwritten by the app or the CLI.
- Terminal launch: `open -b com.apple.Terminal <path>` or `open -b com.googlecode.iterm2 <path>`. Bundle IDs, never app names (iTerm lives in `~/Applications` here).
- Git: `/usr/bin/git -C <path> status --porcelain=v2 --branch`, run off the main thread in the app.
- CLI: errors to stderr, exit 1; usage errors exit 2.
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0143cbkCiJDNhT95CkVu38aQ
  ```
- Do not stage the user's pre-existing working-tree changes (deleted Python files, `old-python/`, `README.md` edit) except where Task 7 says so for `README.md`. Use `git add <exact paths>`.

## Review Focus

1. `ff add .` and `~/code/x` → the stored path is absolute and expanded (tests: Task 2 `absolutePathExpandsAndJoins`, Task 4 `addListAndJSON`).
2. Files picked in `NSOpenPanel` may come back via a symlinked or `/private`-prefixed path → still accepted as inside the project (test: Task 2 `keyFilesThroughSymlinkAndPrivatePrefix`).
3. Folder names with spaces → work in CLI and storage (test: Task 4 `addListAndJSON` uses `my proj`).
4. Hand-broken `projects.json` → any command fails with a clear message and the file is byte-for-byte unchanged (test: Task 4 `brokenConfigIsNotOverwritten`; app side guarded in `AppModel.update`, Task 5).
5. Rename that only changes case (`proj` → `Proj`) is allowed; a different project with a case-variant name is rejected (test: Task 2 `duplicateNamesAreCaseInsensitive`).

---

## File Structure

```
Package.swift                         targets: FFCore, ff, FrequentFinder (path Sources/FFApp), FFCoreTests
Sources/FFCore/Errors.swift           FFError (all user-facing error messages)
Sources/FFCore/Config.swift           TerminalApp, ProjectURL, Project, Config, ConfigStore (load/save)
Sources/FFCore/Commands.swift         extension Config: add/remove/rename/setPath/move/addFiles/removeFiles/setURL/removeURL
Sources/FFCore/Process.swift          runProcess() helper (internal)
Sources/FFCore/Git.swift              GitStatus, Git.parse, Git.status
Sources/FFCore/CLI.swift              CLI.usage, CLI.run (argument parsing + dispatch)
Sources/FFCore/Launcher.swift         Launcher.open, Launcher.openTerminal
Sources/ff/main.swift                 CLI entry point
Sources/FFApp/FrequentFinderApp.swift @main, scenes
Sources/FFApp/AppModel.swift          observable state, file watcher, update/attempt, git refresh
Sources/FFApp/MenuPanel.swift         menu bar panel, ProjectRow, GitDot
Sources/FFApp/ProjectWindow.swift     per-project window, GitLine, KeyFileRow
Sources/FFApp/SettingsView.swift      settings window, ProjectEditor
Tests/FFCoreTests/Helpers.swift       makeTempDir()
Tests/FFCoreTests/ConfigTests.swift
Tests/FFCoreTests/CommandTests.swift
Tests/FFCoreTests/GitTests.swift
Tests/FFCoreTests/CLITests.swift
scripts/make-app.sh                   builds build/FrequentFinder.app, installs ff to ~/.local/bin
```

---

### Task 1: Package skeleton, config model and store

**Files:**
- Create: `Package.swift`, `Sources/FFCore/Errors.swift`, `Sources/FFCore/Config.swift`
- Create: `Tests/FFCoreTests/Helpers.swift`, `Tests/FFCoreTests/ConfigTests.swift`
- Modify: `.gitignore` (append two lines)

**Interfaces:**
- Produces:
  - `public enum FFError: Error, Equatable, CustomStringConvertible, LocalizedError` with cases `usage(String)`, `badConfig(String)`, `noSuchProject(String)`, `duplicateName(String)`, `emptyName`, `notADirectory(String)`, `fileNotFound(String)`, `fileOutsideProject(String)`, `notInList(String)`, `badURL(String)`, `launchFailed(String)`
  - `public enum TerminalApp: String, Codable, CaseIterable { case terminal, iterm }` with `bundleID: String`, `displayName: String`
  - `public struct ProjectURL: Codable, Hashable { var url: String; var label: String?; var title: String }`
  - `public struct Project: Codable, Hashable { var name: String; var path: String; var keyFiles: [String]; var urls: [ProjectURL] }`
  - `public struct Config: Codable, Equatable { var terminal: TerminalApp; var projects: [Project]; func jsonData() throws -> Data }`
  - `public struct ConfigStore { let url: URL; init(url: URL = ConfigStore.defaultURL); static var defaultURL: URL; func load() throws -> Config; func save(_: Config) throws }`
  - Test helper `func makeTempDir() throws -> String`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FrequentFinder",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "FFCore"),
        .testTarget(name: "FFCoreTests", dependencies: ["FFCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Append build folders to `.gitignore`**

```bash
printf '\n# Swift\n.build/\nbuild/\n' >> .gitignore
```

- [ ] **Step 3: Write the failing tests**

`Tests/FFCoreTests/Helpers.swift`:

```swift
import Foundation

/// A new empty directory under the system temp folder.
func makeTempDir() throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}
```

`Tests/FFCoreTests/ConfigTests.swift`:

```swift
import Foundation
import Testing
@testable import FFCore

private func tempStore() throws -> ConfigStore {
    ConfigStore(url: URL(fileURLWithPath: try makeTempDir() + "/sub/projects.json"))
}

@Test func missingFileIsEmptyConfig() throws {
    #expect(try tempStore().load() == Config())
}

@Test func roundTrip() throws {
    let store = try tempStore()
    let config = Config(terminal: .iterm, projects: [
        Project(name: "A", path: "/a", keyFiles: ["x.md"], urls: [ProjectURL(url: "https://a.com", label: "A site")]),
        Project(name: "B", path: "/b"),
    ])
    try store.save(config)
    #expect(try store.load() == config)
}

@Test func missingKeysGetDefaults() throws {
    let store = try tempStore()
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"projects":[{"name":"A","path":"/a"}]}"#.utf8).write(to: store.url)
    #expect(try store.load() == Config(terminal: .terminal, projects: [Project(name: "A", path: "/a")]))
}

@Test func brokenFileThrowsBadConfig() throws {
    let store = try tempStore()
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: store.url)
    #expect {
        try store.load()
    } throws: { error in
        if case FFError.badConfig = error { return true }
        return false
    }
}

@Test func terminalBundleIDs() {
    #expect(TerminalApp.terminal.bundleID == "com.apple.Terminal")
    #expect(TerminalApp.iterm.bundleID == "com.googlecode.iterm2")
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift test`
Expected: build fails with errors like `cannot find 'ConfigStore' in scope`.

- [ ] **Step 5: Write `Sources/FFCore/Errors.swift`**

```swift
import Foundation

public enum FFError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case usage(String)
    case badConfig(String)
    case noSuchProject(String)
    case duplicateName(String)
    case emptyName
    case notADirectory(String)
    case fileNotFound(String)
    case fileOutsideProject(String)
    case notInList(String)
    case badURL(String)
    case launchFailed(String)

    public var description: String {
        switch self {
        case .usage(let text): text
        case .badConfig(let detail): "Cannot read config file \(detail). Fix or delete it; it was not changed."
        case .noSuchProject(let name): "No project named '\(name)'."
        case .duplicateName(let name): "A project named '\(name)' already exists."
        case .emptyName: "Project name cannot be empty."
        case .notADirectory(let path): "Not a directory: \(path)"
        case .fileNotFound(let path): "File not found: \(path)"
        case .fileOutsideProject(let path): "File is not inside the project folder: \(path)"
        case .notInList(let item): "Not in the list: \(item)"
        case .badURL(let url): "Not a valid http, https or file URL: \(url)"
        case .launchFailed(let detail): "Could not open: \(detail)"
        }
    }

    public var errorDescription: String? { description }
}
```

- [ ] **Step 6: Write `Sources/FFCore/Config.swift`**

```swift
import Foundation

public enum TerminalApp: String, Codable, CaseIterable, Sendable {
    case terminal, iterm

    public var bundleID: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        }
    }

    public var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm: "iTerm"
        }
    }
}

public struct ProjectURL: Codable, Hashable, Sendable {
    public var url: String
    public var label: String?

    public init(url: String, label: String? = nil) {
        self.url = url
        self.label = label
    }

    /// Text to show: the label, or the URL when there is no label.
    public var title: String { label ?? url }
}

public struct Project: Codable, Hashable, Sendable {
    public var name: String
    /// Absolute path of the project's top-level folder.
    public var path: String
    /// Paths relative to `path`.
    public var keyFiles: [String]
    public var urls: [ProjectURL]

    public init(name: String, path: String, keyFiles: [String] = [], urls: [ProjectURL] = []) {
        self.name = name
        self.path = path
        self.keyFiles = keyFiles
        self.urls = urls
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        keyFiles = try c.decodeIfPresent([String].self, forKey: .keyFiles) ?? []
        urls = try c.decodeIfPresent([ProjectURL].self, forKey: .urls) ?? []
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var terminal: TerminalApp
    public var projects: [Project]

    public init(terminal: TerminalApp = .terminal, projects: [Project] = []) {
        self.terminal = terminal
        self.projects = projects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        terminal = try c.decodeIfPresent(TerminalApp.self, forKey: .terminal) ?? .terminal
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
    }

    /// The config as pretty-printed JSON, exactly as saved to disk.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    /// `$FF_CONFIG` if set, else `~/.config/frequent-finder/projects.json`.
    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["FF_CONFIG"] {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/frequent-finder/projects.json")
    }

    /// A missing file is an empty config. A file that cannot be parsed throws `FFError.badConfig`.
    public func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            throw FFError.badConfig("\(url.path): \(error.localizedDescription)")
        }
    }

    /// Writes atomically: a temp file in the same folder replaces the original.
    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.jsonData().write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test`
Expected: all 5 tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift .gitignore Sources/FFCore Tests/FFCoreTests
git commit -m "Add FFCore config model and store

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0143cbkCiJDNhT95CkVu38aQ"
```

---

### Task 2: Edit commands on Config

**Files:**
- Create: `Sources/FFCore/Commands.swift`
- Test: `Tests/FFCoreTests/CommandTests.swift`

**Interfaces:**
- Consumes: `Config`, `Project`, `ProjectURL`, `FFError` from Task 1; `makeTempDir()`.
- Produces (all on `extension Config`, all `public`):
  - `static func absolutePath(_ path: String, cwd: String) -> String`
  - `static func isValidURL(_ string: String) -> Bool`
  - `func index(of name: String) throws -> Int`
  - `mutating func add(path: String, name: String? = nil, cwd: String) throws`
  - `mutating func remove(_ name: String) throws`
  - `mutating func rename(_ name: String, to newName: String) throws`
  - `mutating func setPath(_ name: String, to path: String, cwd: String) throws`
  - `mutating func move(_ name: String, by offset: Int) throws`
  - `func relativePath(of file: String, in name: String, cwd: String) throws -> String`
  - `mutating func addFiles(_ name: String, _ files: [String], cwd: String) throws`
  - `mutating func removeFiles(_ name: String, _ files: [String], cwd: String) throws`
  - `mutating func setURL(_ name: String, url: String, label: String? = nil, replacing index: Int? = nil) throws`
  - `mutating func removeURL(_ name: String, url: String) throws`

- [ ] **Step 1: Write the failing tests**

`Tests/FFCoreTests/CommandTests.swift`:

```swift
import Foundation
import Testing
@testable import FFCore

/// Layout: <dir>/proj/docs/spec.md, <dir>/other/, <dir>/outside.md
private func fixture() throws -> String {
    let dir = try makeTempDir()
    let fm = FileManager.default
    try fm.createDirectory(atPath: dir + "/proj/docs", withIntermediateDirectories: true)
    try fm.createDirectory(atPath: dir + "/other", withIntermediateDirectories: true)
    fm.createFile(atPath: dir + "/proj/docs/spec.md", contents: nil)
    fm.createFile(atPath: dir + "/outside.md", contents: nil)
    return dir
}

@Test func absolutePathExpandsAndJoins() {
    #expect(Config.absolutePath("~/x", cwd: "/") == NSHomeDirectory() + "/x")
    #expect(Config.absolutePath("a/../b", cwd: "/base") == "/base/b")
    #expect(Config.absolutePath(".", cwd: "/base/dir") == "/base/dir")
    #expect(Config.absolutePath("/abs/", cwd: "/base") == "/abs")
}

@Test func addUsesFolderNameAndAbsolutePath() throws {
    let dir = try fixture()
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    #expect(c.projects == [Project(name: "proj", path: dir + "/proj")])
}

@Test func addRejectsMissingDirectoryAndFiles() throws {
    let dir = try fixture()
    var c = Config()
    #expect(throws: FFError.notADirectory(dir + "/nope")) { try c.add(path: "nope", cwd: dir) }
    #expect(throws: FFError.notADirectory(dir + "/outside.md")) { try c.add(path: "outside.md", cwd: dir) }
    #expect(throws: FFError.emptyName) { try c.add(path: "proj", name: "  ", cwd: dir) }
}

@Test func duplicateNamesAreCaseInsensitive() throws {
    let dir = try fixture()
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    #expect(throws: FFError.duplicateName("PROJ")) { try c.add(path: "other", name: "PROJ", cwd: dir) }
    try c.rename("proj", to: "Proj")             // case-only change of the same project is fine
    #expect(c.projects[0].name == "Proj")
    try c.add(path: "other", cwd: dir)
    #expect(throws: FFError.duplicateName("proj")) { try c.rename("other", to: "proj") }
    #expect(throws: FFError.emptyName) { try c.rename("other", to: "") }
}

@Test func removeSetPathAndUnknownName() throws {
    let dir = try fixture()
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    try c.setPath("proj", to: dir + "/other", cwd: "/")
    #expect(c.projects[0].path == dir + "/other")
    #expect(throws: FFError.noSuchProject("nope")) { try c.remove("nope") }
    try c.remove("PROJ")
    #expect(c.projects.isEmpty)
}

@Test func moveClampsToEnds() throws {
    var c = Config(projects: ["a", "b", "c"].map { Project(name: $0, path: "/" + $0) })
    try c.move("c", by: -1)
    #expect(c.projects.map(\.name) == ["a", "c", "b"])
    try c.move("a", by: -5)
    #expect(c.projects.map(\.name) == ["a", "c", "b"])
    try c.move("a", by: 9)
    #expect(c.projects.map(\.name) == ["c", "b", "a"])
}

@Test func keyFilesRelativeDedupedAndChecked() throws {
    let dir = try fixture()
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    try c.addFiles("proj", ["proj/docs/spec.md"], cwd: dir)
    try c.addFiles("proj", [dir + "/proj/docs/spec.md"], cwd: "/")   // same file, absolute: ignored
    #expect(c.projects[0].keyFiles == ["docs/spec.md"])
    #expect(throws: FFError.fileOutsideProject(dir + "/outside.md")) { try c.addFiles("proj", ["outside.md"], cwd: dir) }
    #expect(throws: FFError.fileNotFound(dir + "/proj/missing.md")) { try c.addFiles("proj", ["proj/missing.md"], cwd: dir) }
    try c.removeFiles("proj", ["docs/spec.md"], cwd: "/")             // stored relative path works from anywhere
    #expect(c.projects[0].keyFiles.isEmpty)
    try c.addFiles("proj", ["proj/docs/spec.md"], cwd: dir)
    try c.removeFiles("proj", ["proj/docs/spec.md"], cwd: dir)        // path relative to cwd works too
    #expect(c.projects[0].keyFiles.isEmpty)
    #expect(throws: FFError.notInList("docs/spec.md")) { try c.removeFiles("proj", ["docs/spec.md"], cwd: dir + "/proj") }
}

@Test func keyFilesThroughSymlinkAndPrivatePrefix() throws {
    let dir = try fixture()
    try FileManager.default.createSymbolicLink(atPath: dir + "/link", withDestinationPath: dir + "/proj")
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    try c.addFiles("proj", [dir + "/link/docs/spec.md"], cwd: "/")
    #expect(c.projects[0].keyFiles == ["docs/spec.md"])
    // Temp dirs live under /var, which is a symlink to /private/var. NSOpenPanel may return either form.
    if dir.hasPrefix("/var/") {
        try c.removeFiles("proj", ["docs/spec.md"], cwd: "/")
        try c.addFiles("proj", ["/private" + dir + "/proj/docs/spec.md"], cwd: "/")
        #expect(c.projects[0].keyFiles == ["docs/spec.md"])
    }
}

@Test func urlsValidatedAddedReplacedRemoved() throws {
    var c = Config(projects: [Project(name: "p", path: "/p")])
    for bad in ["not a url", "ftp://x.com", "https://", "mailto:a@b.com"] {
        #expect(throws: FFError.badURL(bad)) { try c.setURL("p", url: bad) }
    }
    try c.setURL("p", url: "https://a.com", label: "A")
    try c.setURL("p", url: "file:///tmp/x", label: "  ")              // blank label stored as nil
    try c.setURL("p", url: "https://a.com", label: "A2")               // same URL again: label updated, no duplicate
    #expect(c.projects[0].urls == [ProjectURL(url: "https://a.com", label: "A2"), ProjectURL(url: "file:///tmp/x")])
    try c.setURL("p", url: "https://b.com", replacing: 0)
    #expect(c.projects[0].urls.first == ProjectURL(url: "https://b.com"))
    #expect(throws: FFError.notInList("https://zzz.com")) { try c.removeURL("p", url: "https://zzz.com") }
    try c.removeURL("p", url: "https://b.com")
    #expect(c.projects[0].urls == [ProjectURL(url: "file:///tmp/x")])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: build fails with `value of type 'Config' has no member 'add'` (and similar).

- [ ] **Step 3: Write `Sources/FFCore/Commands.swift`**

```swift
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

    /// Moves a project up (negative) or down (positive), stopping at the ends.
    public mutating func move(_ name: String, by offset: Int) throws {
        let i = try index(of: name)
        let j = min(max(i + offset, 0), projects.count - 1)
        projects.insert(projects.remove(at: i), at: j)
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass (5 from Task 1 + 9 here).

- [ ] **Step 5: Commit**

```bash
git add Sources/FFCore/Commands.swift Tests/FFCoreTests/CommandTests.swift
git commit -m "Add project edit commands

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0143cbkCiJDNhT95CkVu38aQ"
```

---

### Task 3: Git status

**Files:**
- Create: `Sources/FFCore/Process.swift`, `Sources/FFCore/Git.swift`
- Test: `Tests/FFCoreTests/GitTests.swift`

**Interfaces:**
- Consumes: `makeTempDir()`.
- Produces:
  - `func runProcess(_ executable: String, _ args: [String]) -> (status: Int32, out: String, err: String)` (internal; used by Task 5's `Launcher` and by tests via `@testable`)
  - `public struct GitStatus: Equatable, Sendable { let branch: String; let changes: Int; var isDirty: Bool }`
  - `public enum Git { static func parse(_ porcelain: String) -> GitStatus; static func status(at path: String) -> GitStatus? }` — `nil` means not a git repo (or git failed).

- [ ] **Step 1: Write the failing tests**

`Tests/FFCoreTests/GitTests.swift`:

```swift
import Foundation
import Testing
@testable import FFCore

@Test func parsesBranchAndCountsChanges() {
    let out = """
    # branch.oid 1234abcd
    # branch.head feature/x
    # branch.upstream origin/feature/x
    1 .M N... 100644 100644 100644 aaaa bbbb README.md
    ? new.txt
    """
    #expect(Git.parse(out) == GitStatus(branch: "feature/x", changes: 2))
    #expect(Git.parse(out).isDirty)
    #expect(Git.parse("# branch.oid (initial)\n# branch.head (detached)\n") == GitStatus(branch: "detached", changes: 0))
}

@Test func realRepoCleanThenDirty() throws {
    let dir = try makeTempDir()
    #expect(Git.status(at: dir) == nil)
    #expect(runProcess("/usr/bin/git", ["-C", dir, "init", "-q", "-b", "main"]).status == 0)
    #expect(Git.status(at: dir) == GitStatus(branch: "main", changes: 0))
    FileManager.default.createFile(atPath: dir + "/a.txt", contents: nil)
    #expect(Git.status(at: dir) == GitStatus(branch: "main", changes: 1))
}

@Test func missingFolderIsNotARepo() {
    #expect(Git.status(at: "/no/such/folder") == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: build fails with `cannot find 'Git' in scope`.

- [ ] **Step 3: Write `Sources/FFCore/Process.swift`**

```swift
import Foundation

/// Runs a program, waits for it, and returns its exit status, stdout and stderr.
/// A program that cannot start returns status -1 with the reason in `err`.
func runProcess(_ executable: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do { try process.run() } catch { return (-1, "", error.localizedDescription) }
    // ponytail: reads stdout then stderr; blocks if stderr alone fills the 64 KB pipe buffer. Fine for git/open; read both concurrently if reused for chatty tools.
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self))
}
```

- [ ] **Step 4: Write `Sources/FFCore/Git.swift`**

```swift
import Foundation

public struct GitStatus: Equatable, Sendable {
    public let branch: String
    /// Number of changed, staged or untracked entries.
    public let changes: Int
    public var isDirty: Bool { changes > 0 }
}

public enum Git {
    /// Parses `git status --porcelain=v2 --branch` output.
    public static func parse(_ porcelain: String) -> GitStatus {
        var branch = "unknown"
        var changes = 0
        for line in porcelain.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                branch = String(line.dropFirst("# branch.head ".count))
                if branch == "(detached)" { branch = "detached" }
            } else if !line.hasPrefix("#") {
                changes += 1
            }
        }
        return GitStatus(branch: branch, changes: changes)
    }

    /// Blocks while git runs; call off the main thread. `nil` = not a git repository (or git failed).
    public static func status(at path: String) -> GitStatus? {
        let result = runProcess("/usr/bin/git", ["-C", path, "status", "--porcelain=v2", "--branch"])
        return result.status == 0 ? parse(result.out) : nil
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/FFCore/Process.swift Sources/FFCore/Git.swift Tests/FFCoreTests/GitTests.swift
git commit -m "Add git status reader

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0143cbkCiJDNhT95CkVu38aQ"
```

---

### Task 4: `ff` CLI

**Files:**
- Create: `Sources/FFCore/CLI.swift`, `Sources/ff/main.swift`
- Modify: `Package.swift` (add the `ff` target)
- Test: `Tests/FFCoreTests/CLITests.swift`

**Interfaces:**
- Consumes: `ConfigStore`, `Config` commands from Task 2, `FFError`.
- Produces:
  - `public enum CLI { static let usage: String; static func run(_ argv: [String], store: ConfigStore, cwd: String) throws -> String }` — returns text for stdout (may be empty); saves only when the config changed; throws `FFError.usage(CLI.usage)` for bad arguments.
  - Executable `ff`.

- [ ] **Step 1: Write the failing tests**

`Tests/FFCoreTests/CLITests.swift`:

```swift
import Foundation
import Testing
@testable import FFCore

private struct Env {
    let dir: String
    let store: ConfigStore

    init() throws {
        dir = try makeTempDir()
        store = ConfigStore(url: URL(fileURLWithPath: dir + "/cfg/projects.json"))
    }

    @discardableResult
    func ff(_ args: String...) throws -> String {
        try CLI.run(args, store: store, cwd: dir)
    }
}

@Test func addListAndJSON() throws {
    let env = try Env()
    try FileManager.default.createDirectory(atPath: env.dir + "/my proj", withIntermediateDirectories: true)
    #expect(try env.ff("list") == "No projects. Add one with: ff add <path>")
    try env.ff("add", "my proj")
    try env.ff("add", ".", "--name", "Root")
    #expect(try env.ff("list") == "my proj\t\(env.dir)/my proj\nRoot\t\(env.dir)")
    #expect(try env.ff("list", "--json").contains(#""name" : "Root""#))
}

@Test func usageErrors() throws {
    let env = try Env()
    for args in [[], ["bogus"], ["add"], ["add", "x", "--name"], ["terminal", "kitty"], ["file", "add", "p"], ["url", "zap", "p", "u"]] {
        #expect(throws: FFError.usage(CLI.usage)) { try CLI.run(args, store: env.store, cwd: env.dir) }
    }
    #expect(try env.ff("help") == CLI.usage)
}

@Test func terminalGetAndSet() throws {
    let env = try Env()
    #expect(try env.ff("terminal") == "terminal")
    try env.ff("terminal", "iTerm")
    #expect(try env.ff("terminal") == "iterm")
}

@Test func brokenConfigIsNotOverwritten() throws {
    let env = try Env()
    try FileManager.default.createDirectory(at: env.store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: env.store.url)
    #expect { try env.ff("add", ".") } throws: { error in
        if case FFError.badConfig = error { return true }
        return false
    }
    #expect(try String(contentsOf: env.store.url, encoding: .utf8) == "{ not json")
}

@Test func readOnlyCommandsDoNotCreateFile() throws {
    let env = try Env()
    try env.ff("list")
    try env.ff("terminal")
    #expect(!FileManager.default.fileExists(atPath: env.store.url.path))
}

@Test func renameRemoveFileAndURLCommands() throws {
    let env = try Env()
    try env.ff("add", ".", "--name", "P")
    FileManager.default.createFile(atPath: env.dir + "/README.md", contents: nil)
    try env.ff("file", "add", "P", "README.md")
    try env.ff("url", "add", "P", "https://example.com", "--label", "Site")
    var p = try env.store.load().projects[0]
    #expect(p.keyFiles == ["README.md"])
    #expect(p.urls == [ProjectURL(url: "https://example.com", label: "Site")])
    try env.ff("file", "remove", "P", "README.md")
    try env.ff("url", "remove", "P", "https://example.com")
    try env.ff("rename", "P", "Q")
    p = try env.store.load().projects[0]
    #expect(p.name == "Q" && p.keyFiles.isEmpty && p.urls.isEmpty)
    try env.ff("remove", "q")
    #expect(try env.store.load().projects.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: build fails with `cannot find 'CLI' in scope`.

- [ ] **Step 3: Write `Sources/FFCore/CLI.swift`**

```swift
import Foundation

public enum CLI {
    public static let usage = """
    usage:
      ff list [--json]                      show all projects
      ff add <path> [--name "Name"]         add a project (name defaults to the folder name)
      ff remove <name>
      ff rename <name> <new-name>
      ff set-path <name> <path>
      ff file add <name> <file>...          add key files (inside the project folder)
      ff file remove <name> <file>...
      ff url add <name> <url> [--label "Label"]
      ff url remove <name> <url>
      ff terminal [terminal|iterm]          show or set the terminal app
      ff help

    Config file: ~/.config/frequent-finder/projects.json (override with FF_CONFIG)
    """

    /// Runs one command. Returns text for stdout. Saves only if the config changed.
    public static func run(_ argv: [String], store: ConfigStore, cwd: String) throws -> String {
        var args = argv
        let json = takeFlag("--json", from: &args)
        let name = try takeOption("--name", from: &args)
        let label = try takeOption("--label", from: &args)
        guard let command = args.first else { throw FFError.usage(usage) }
        let a = Array(args.dropFirst())
        if ["help", "--help", "-h"].contains(command) { return usage }

        var config = try store.load()
        let before = config
        var output = ""

        switch command {
        case "list":
            try expect(a.isEmpty)
            if json {
                output = String(decoding: try config.jsonData(), as: UTF8.self)
            } else if config.projects.isEmpty {
                output = "No projects. Add one with: ff add <path>"
            } else {
                output = config.projects.map { "\($0.name)\t\($0.path)" }.joined(separator: "\n")
            }
        case "add":
            try expect(a.count == 1)
            try config.add(path: a[0], name: name, cwd: cwd)
        case "remove":
            try expect(a.count == 1)
            try config.remove(a[0])
        case "rename":
            try expect(a.count == 2)
            try config.rename(a[0], to: a[1])
        case "set-path":
            try expect(a.count == 2)
            try config.setPath(a[0], to: a[1], cwd: cwd)
        case "file":
            try expect(a.count >= 3)
            let files = Array(a.dropFirst(2))
            switch a[0] {
            case "add": try config.addFiles(a[1], files, cwd: cwd)
            case "remove": try config.removeFiles(a[1], files, cwd: cwd)
            default: throw FFError.usage(usage)
            }
        case "url":
            try expect(a.count == 3)
            switch a[0] {
            case "add": try config.setURL(a[1], url: a[2], label: label)
            case "remove": try config.removeURL(a[1], url: a[2])
            default: throw FFError.usage(usage)
            }
        case "terminal":
            try expect(a.count <= 1)
            if let value = a.first {
                guard let terminal = TerminalApp(rawValue: value.lowercased()) else { throw FFError.usage(usage) }
                config.terminal = terminal
            } else {
                output = config.terminal.rawValue
            }
        default:
            throw FFError.usage(usage)
        }

        if config != before { try store.save(config) }
        return output
    }

    private static func expect(_ ok: Bool) throws {
        if !ok { throw FFError.usage(usage) }
    }

    private static func takeFlag(_ flag: String, from args: inout [String]) -> Bool {
        guard let i = args.firstIndex(of: flag) else { return false }
        args.remove(at: i)
        return true
    }

    private static func takeOption(_ flag: String, from args: inout [String]) throws -> String? {
        guard let i = args.firstIndex(of: flag) else { return nil }
        guard i + 1 < args.count else { throw FFError.usage(usage) }
        let value = args[i + 1]
        args.removeSubrange(i...i + 1)
        return value
    }
}
```

- [ ] **Step 4: Write `Sources/ff/main.swift`**

```swift
import FFCore
import Foundation

do {
    let output = try CLI.run(
        Array(CommandLine.arguments.dropFirst()),
        store: ConfigStore(),
        cwd: FileManager.default.currentDirectoryPath
    )
    if !output.isEmpty { print(output) }
} catch FFError.usage(let text) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("ff: \(error)\n".utf8))
    exit(1)
}
```

- [ ] **Step 5: Add the `ff` target to `Package.swift`**

Replace the `targets:` array with:

```swift
    targets: [
        .target(name: "FFCore"),
        .executableTarget(name: "ff", dependencies: ["FFCore"]),
        .testTarget(name: "FFCoreTests", dependencies: ["FFCore"]),
    ],
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 7: Smoke-test the real binary**

```bash
export FF_CONFIG="$(mktemp -d)/projects.json"
swift run ff add . --name FF && swift run ff list && swift run ff file add FF README.md && swift run ff list --json
swift run ff nope; echo "exit=$?"
swift run ff remove nope; echo "exit=$?"
unset FF_CONFIG
```

Expected: list shows `FF<TAB><repo path>`; JSON shows `"keyFiles" : [ "README.md" ]`; `ff nope` prints usage and `exit=2`; `ff remove nope` prints `ff: No project named 'nope'.` and `exit=1`.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/FFCore/CLI.swift Sources/ff/main.swift Tests/FFCoreTests/CLITests.swift
git commit -m "Add ff command-line tool

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0143cbkCiJDNhT95CkVu38aQ"
```

---

### Task 5: Menu bar app — panel and project window

**Files:**
- Create: `Sources/FFCore/Launcher.swift`
- Create: `Sources/FFApp/FrequentFinderApp.swift`, `Sources/FFApp/AppModel.swift`, `Sources/FFApp/MenuPanel.swift`, `Sources/FFApp/ProjectWindow.swift`
- Create: `Sources/FFApp/SettingsView.swift` (placeholder view so the `settings` window compiles; Task 6 replaces it)
- Create: `scripts/make-app.sh`
- Modify: `Package.swift` (add the app target)

**Interfaces:**
- Consumes: everything in FFCore; `runProcess` (internal, same module).
- Produces:
  - `public enum Launcher { static func open(_ args: String...) throws; static func openTerminal(at path: String, app: TerminalApp) throws }`
  - `@MainActor @Observable final class AppModel` with `store`, `config`, `loadError: String?`, `error: String?`, `git: [String: GitStatus]` (keyed by project path), `project(named:) -> Project?`, `update(_ change: (inout Config) throws -> Void)`, `attempt(_ action: () throws -> Void)`, `refreshGit(_ paths: [String])`
  - Views: `GitDot(status: GitStatus?)` in `MenuPanel.swift`, also used by `GitLine` in `ProjectWindow.swift`
  - Window ids: settings window `id: "settings"`; project windows `WindowGroup(for: String.self)` keyed by project name.

No automated tests: this task is UI glue. `Launcher` is two lines over `runProcess`. Verification is the manual checklist in Step 9.

- [ ] **Step 1: Write `Sources/FFCore/Launcher.swift`**

```swift
import Foundation

/// Opens things with macOS `open`: folders in Finder, files in their default app, URLs in the browser.
public enum Launcher {
    public static func open(_ args: String...) throws {
        let result = runProcess("/usr/bin/open", args)
        guard result.status == 0 else {
            let detail = result.err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw FFError.launchFailed(detail.isEmpty ? args.joined(separator: " ") : detail)
        }
    }

    /// By bundle ID, so it works wherever the terminal app is installed.
    public static func openTerminal(at path: String, app: TerminalApp) throws {
        try open("-b", app.bundleID, path)
    }
}
```

- [ ] **Step 2: Add the app target to `Package.swift`**

Replace the `targets:` array with:

```swift
    targets: [
        .target(name: "FFCore"),
        .executableTarget(name: "ff", dependencies: ["FFCore"]),
        .executableTarget(name: "FrequentFinder", dependencies: ["FFCore"], path: "Sources/FFApp"),
        .testTarget(name: "FFCoreTests", dependencies: ["FFCore"]),
    ],
```

- [ ] **Step 3: Write `Sources/FFApp/AppModel.swift`**

```swift
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
```

- [ ] **Step 4: Write `Sources/FFApp/FrequentFinderApp.swift`**

```swift
import FFCore
import SwiftUI

@main
struct FrequentFinderApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Frequent Finder", systemImage: "folder.badge.gearshape") {
            MenuPanel().environment(model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Project", for: String.self) { $name in
            ProjectWindow(name: name ?? "").environment(model)
        }
        .defaultSize(width: 440, height: 480)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Frequent Finder Settings", id: "settings") {
            SettingsView().environment(model)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
```

- [ ] **Step 5: Write `Sources/FFApp/MenuPanel.swift`**

```swift
import AppKit
import FFCore
import SwiftUI

struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let loadError = model.loadError {
                Text(loadError).foregroundStyle(.red).padding()
            } else if model.config.projects.isEmpty {
                Text("No projects yet. Add one in Settings.").foregroundStyle(.secondary).padding()
            } else {
                ForEach(model.config.projects, id: \.name) { project in
                    ProjectRow(project: project) {
                        openWindow(value: project.name)
                        NSApp.activate()
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    openWindow(id: "settings")
                    NSApp.activate()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .accessibilityLabel("Settings")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .padding(.top, 4)
        .frame(width: 280)
        .onAppear { model.refreshGit(model.config.projects.map(\.path)) }
    }
}

struct ProjectRow: View {
    let project: Project
    let action: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: project.path)
        Button(action: action) {
            HStack {
                GitDot(status: model.git[project.path])
                Text(project.name)
                Spacer()
                if !exists {
                    Text("folder not found").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(exists ? 1 : 0.5)
    }
}

/// Green = clean, orange = dirty, grey = not a git repository.
struct GitDot: View {
    let status: GitStatus?

    var body: some View {
        Circle()
            .fill(status.map { $0.isDirty ? Color.orange : .green } ?? .gray)
            .frame(width: 8, height: 8)
            .accessibilityLabel(status.map { $0.isDirty ? "Git: dirty" : "Git: clean" } ?? "Not a git repository")
    }
}
```

- [ ] **Step 6: Write `Sources/FFApp/ProjectWindow.swift`**

```swift
import FFCore
import SwiftUI

struct ProjectWindow: View {
    let name: String
    @Environment(AppModel.self) private var model
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        if let project = model.project(named: name) {
            details(project)
        } else {
            Text("Project '\(name)' not found.").padding().navigationTitle(name)
        }
    }

    private func details(_ p: Project) -> some View {
        Form {
            Section {
                LabeledContent("Path") { Text(p.path).textSelection(.enabled) }
                LabeledContent("Git") {
                    HStack {
                        GitLine(status: model.git[p.path])
                        Button { model.refreshGit([p.path]) } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                            .help("Refresh")
                            .accessibilityLabel("Refresh git status")
                    }
                }
                HStack {
                    Button("Open in Finder") { model.attempt { try Launcher.open(p.path) } }
                    Button("Open \(model.config.terminal.displayName)") {
                        model.attempt { try Launcher.openTerminal(at: p.path, app: model.config.terminal) }
                    }
                }
            }
            if !p.keyFiles.isEmpty {
                Section("Key Files") {
                    ForEach(p.keyFiles, id: \.self) { KeyFileRow(root: p.path, file: $0) }
                }
            }
            if !p.urls.isEmpty {
                Section("Links") {
                    ForEach(p.urls, id: \.url) { link in
                        if let url = URL(string: link.url) {
                            Link(link.title, destination: url)
                        } else {
                            Text(link.title).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(p.name)
        .onAppear { model.refreshGit([p.path]) }
        .onChange(of: activeState) { _, state in
            if state == .key { model.refreshGit([p.path]) }
        }
    }
}

struct GitLine: View {
    let status: GitStatus?

    var body: some View {
        HStack(spacing: 6) {
            GitDot(status: status)
            if let status {
                Text(status.branch)
                Text(status.isDirty ? "\(status.changes) changed" : "clean").foregroundStyle(.secondary)
            } else {
                Text("Not a git repository").foregroundStyle(.secondary)
            }
        }
    }
}

struct KeyFileRow: View {
    let root: String
    let file: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let full = (root as NSString).appendingPathComponent(file)
        let exists = FileManager.default.fileExists(atPath: full)
        HStack {
            Button(file) { model.attempt { try Launcher.open(full) } }
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
```

- [ ] **Step 7: Write the placeholder `Sources/FFApp/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Text("Settings coming in the next task.").padding()
    }
}
```

- [ ] **Step 8: Write `scripts/make-app.sh` and make it executable**

```bash
#!/bin/bash
# Builds build/FrequentFinder.app and installs ff to ~/.local/bin.
# --install also copies the app to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP=build/FrequentFinder.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/FrequentFinder" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>org.hyland-wood.FrequentFinder</string>
    <key>CFBundleName</key><string>Frequent Finder</string>
    <key>CFBundleExecutable</key><string>FrequentFinder</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

mkdir -p "$HOME/.local/bin"
cp "$BIN/ff" "$HOME/.local/bin/ff"
echo "Built $APP; installed ff to ~/.local/bin/ff"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/FrequentFinder.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/FrequentFinder.app"
fi
```

```bash
chmod +x scripts/make-app.sh
```

- [ ] **Step 9: Build and check by hand**

```bash
swift test && scripts/make-app.sh
~/.local/bin/ff add . --name "Frequent Finder"
~/.local/bin/ff file add "Frequent Finder" README.md Package.swift
~/.local/bin/ff url add "Frequent Finder" https://github.com --label GitHub
open build/FrequentFinder.app
```

Check each, and fix before committing:
- [ ] Menu bar icon appears; no Dock icon.
- [ ] Click icon: panel drops down, shows "Frequent Finder" with an orange dot (repo is dirty).
- [ ] Click the row: project window opens in front. Branch `main`, "N changed".
- [ ] Open in Finder works. Open Terminal opens Terminal at the repo.
- [ ] `~/.local/bin/ff terminal iterm`, then Open iTerm opens iTerm at the repo.
- [ ] Key files: README.md opens; magnifier reveals it in Finder.
- [ ] GitHub link opens in the browser.
- [ ] `~/.local/bin/ff add ~/Documents --name Docs` while the app runs: Docs row appears without restart, grey dot.
- [ ] Gear opens the placeholder Settings window. Quit quits.
- [ ] Write `{ broken` into `~/.config/frequent-finder/projects.json` (after copying the real file aside): panel shows the error. Restore the file: list comes back.

- [ ] **Step 10: Commit**

```bash
git add Package.swift Sources/FFCore/Launcher.swift Sources/FFApp scripts/make-app.sh
git commit -m "Add menu bar app with project window

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0143cbkCiJDNhT95CkVu38aQ"
```

---

### Task 6: Settings window

**Files:**
- Modify: `Sources/FFApp/SettingsView.swift` (replace the placeholder entirely)

**Interfaces:**
- Consumes: `AppModel.update`, `AppModel.attempt`, `AppModel.config`, `AppModel.error`, `AppModel.loadError` (Task 5); `Config.add/remove/rename/setPath/move/addFiles/removeFiles/setURL/removeURL/index(of:)` (Task 2); `TerminalApp.allCases/displayName` (Task 1).
- Produces: `SettingsView`, `ProjectEditor`.

No automated tests: all logic it calls is tested in Task 2. Verification is the manual checklist in Step 3.

- [ ] **Step 1: Replace `Sources/FFApp/SettingsView.swift`**

```swift
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
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Check by hand**

```bash
scripts/make-app.sh && open build/FrequentFinder.app
```

From the menu bar panel, click the gear. Check each, and fix before committing:
- [ ] Terminal picker shows the current value; changing it updates `~/.local/bin/ff terminal`.
- [ ] Open at login toggle turns on; it shows in System Settings → General → Login Items. Turn it off again.
- [ ] `+` opens a folder picker; the new project appears selected.
- [ ] Rename: type a new name, press Return; panel list updates. Rename to an existing name (other case) shows the red duplicate error.
- [ ] Choose… changes the path.
- [ ] Add Files…: picker opens inside the project folder; pick 2+ files with ⌘-click; both appear as relative paths. Pick a file outside the project: red error, nothing added.
- [ ] Remove a key file with the minus button.
- [ ] Add a link with and without a label; `not a url` shows the red error. Edit a link with the pencil, Save; Cancel clears the fields. Remove a link.
- [ ] Up/down arrows reorder; the menu bar panel order matches.
- [ ] `−` removes the selected project.
- [ ] `ff rename` from the terminal while Settings is open: list updates.

- [ ] **Step 4: Commit**

```bash
git add Sources/FFApp/SettingsView.swift
git commit -m "Add settings window

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0143cbkCiJDNhT95CkVu38aQ"
```

---

### Task 7: README

**Files:**
- Modify: `README.md` (replace entirely; this also captures the user's earlier one-line edit)

**Interfaces:** none.

- [ ] **Step 1: Replace `README.md`**

````markdown
# frequent-finder

A macOS menu bar utility to keep track of current projects and their files.

- Click the menu bar icon to see your projects, each with a git status dot
  (green = clean, orange = dirty, grey = not a git repo).
- Click a project to open its window: open the folder in Finder, open Terminal or
  iTerm there, see the branch, open key files and links.
- Settings (gear icon) edits projects, the terminal choice, and Open at login.
- The `ff` command does the same from the command line.

## Build and install

Needs macOS 15 or later and Xcode (or the Swift toolchain).

```bash
scripts/make-app.sh            # builds build/FrequentFinder.app and installs ~/.local/bin/ff
scripts/make-app.sh --install  # also copies the app to /Applications
```

Make sure `~/.local/bin` is on your `PATH`.

## Command line

```
ff list [--json]
ff add <path> [--name "Name"]
ff remove <name>
ff rename <name> <new-name>
ff set-path <name> <path>
ff file add <name> <file>...
ff file remove <name> <file>...
ff url add <name> <url> [--label "Label"]
ff url remove <name> <url>
ff terminal [terminal|iterm]
```

Project names are not case-sensitive. Errors exit with code 1, usage errors with code 2.

## Config file

`~/.config/frequent-finder/projects.json` (set `FF_CONFIG` to use another file).
The app reloads it when it changes.

```json
{
  "projects" : [
    {
      "keyFiles" : [ "README.md" ],
      "name" : "Frequent Finder",
      "path" : "/Users/me/code/frequent-finder",
      "urls" : [ { "label" : "GitHub", "url" : "https://github.com/me/frequent-finder" } ]
    }
  ],
  "terminal" : "iterm"
}
```

`keyFiles` are relative to `path`. `label` is optional. `terminal` is `terminal` or `iterm`.

## Development

```bash
swift test
```

The old Python/Qt attempt is in `old-python/` and is not used.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Document the macOS app and ff CLI

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0143cbkCiJDNhT95CkVu38aQ"
```
