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
