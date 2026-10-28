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

@Test func repoCommands() throws {
    let env = try Env()
    for p in ["one/.git", "two/.git"] {
        try FileManager.default.createDirectory(atPath: env.dir + "/" + p, withIntermediateDirectories: true)
    }
    try env.ff("add", ".", "--name", "P")
    #expect(try env.ff("repo", "find", "P") == "Added 2 repositories.")
    try env.ff("repo", "remove", "P", "one")
    #expect(try env.store.load().projects[0].repos == ["two"])
    try env.ff("repo", "add", "P", "one")
    #expect(try env.store.load().projects[0].repos == ["two", "one"])
    #expect(throws: FFError.usage(CLI.usage)) { try env.ff("repo", "add", "P") }
}

@Test func projectWithoutFolderCommands() throws {
    let env = try Env()
    try env.ff("add", "--name", "Pair")
    try env.ff("add", ".", "--name", "Q")
    try env.ff("set-path", "Q", "--none")
    #expect(try env.ff("list") == "Pair\t(no folder)\nQ\t(no folder)")
    #expect(throws: FFError.noFolder("Pair")) { try env.ff("repo", "find", "Pair") }
}

@Test func activateAndDeactivate() throws {
    let env = try Env()
    try env.ff("add", ".", "--name", "P")
    #expect(try env.ff("list") == "P\t\(env.dir)")
    try env.ff("deactivate", "p")
    #expect(try env.ff("list") == "P\t\(env.dir)\t(inactive)")
    try env.ff("activate", "P")
    #expect(try env.store.load().projects[0].active)
}

@Test func notesCommands() throws {
    let env = try Env()
    try env.ff("add", "--name", "P")
    #expect(try env.ff("notes", "p") == "")
    try env.ff("notes", "P", "Ship it\nFriday")
    #expect(try env.ff("notes", "P") == "Ship it\nFriday")
    try env.ff("notes", "P", "--none")
    #expect(try env.ff("notes", "P") == "")
    #expect(throws: FFError.usage(CLI.usage)) { try env.ff("notes") }
    #expect(throws: FFError.usage(CLI.usage)) { try env.ff("notes", "P", "a", "b") }
    #expect(throws: FFError.usage(CLI.usage)) { try env.ff("notes", "P", "a", "--none") }
}
