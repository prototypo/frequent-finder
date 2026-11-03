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
    let loaded = try store.load()
    #expect(loaded == Config(terminal: .terminal, projects: [Project(id: loaded.projects[0].id, name: "A", path: "/a")]))
}

@Test func missingIDsAreAddedAndSavedOnce() throws {
    let store = try tempStore()
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"projects":[{"name":"A","path":"/a"},{"name":"B"}],"terminal":"iterm"}"#.utf8).write(to: store.url)
    let first = try store.load()
    let second = try store.load()
    #expect(first == second)                                   // ids stable after the one-time save
    #expect(Set(first.projects.map(\.id)).count == 2)
    #expect(first.terminal == .iterm && first.projects.map(\.name) == ["A", "B"] && first.projects[0].path == "/a")
}

@Test func loadWithAllIDsDoesNotWrite() throws {
    let store = try tempStore()
    try store.save(Config(projects: [Project(name: "A", path: "/a")]))
    let before = try FileManager.default.attributesOfItem(atPath: store.url.path)[.modificationDate] as! Date
    Thread.sleep(forTimeInterval: 1.1)
    _ = try store.load()
    let after = try FileManager.default.attributesOfItem(atPath: store.url.path)[.modificationDate] as! Date
    #expect(before == after)
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

@Test func updateAppliesChangeOnTopOfLatestFile() throws {
    let store = try tempStore()
    let a = Project(name: "A", path: "/a"), b = Project(name: "B", path: "/b")
    try store.save(Config(projects: [a]))
    // Someone else (ff, an editor) changes the file after the app last read it.
    try store.save(Config(projects: [a, b]))
    let result = try store.update { $0.terminal = .iterm }
    let expected = Config(terminal: .iterm, projects: [a, b])
    #expect(result == expected)
    #expect(try store.load() == expected)
}

@Test func updateLeavesBrokenFileUntouched() throws {
    let store = try tempStore()
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: store.url)
    #expect(throws: FFError.self) { try store.update { $0.terminal = .iterm } }
    #expect(try String(contentsOf: store.url, encoding: .utf8) == "{ not json")
}
