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

/// `to` uses SwiftUI List .onMove semantics: the index, in the list before the move, to insert in front of.
@Test func moveToListPosition() throws {
    var c = Config(projects: ["a", "b", "c"].map { Project(name: $0, path: "/" + $0) })
    try c.move("a", to: 3)
    #expect(c.projects.map(\.name) == ["b", "c", "a"])
    try c.move("a", to: 0)
    #expect(c.projects.map(\.name) == ["a", "b", "c"])
    try c.move("a", to: 2)
    #expect(c.projects.map(\.name) == ["b", "a", "c"])
    try c.move("c", to: 99)
    #expect(c.projects.map(\.name) == ["b", "a", "c"])
    try c.move("c", to: -4)
    #expect(c.projects.map(\.name) == ["c", "b", "a"])
}

@Test func keyFilesRelativeDedupedAndChecked() throws {
    let dir = try fixture()
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    try c.addFiles("proj", ["proj/docs/spec.md"], cwd: dir)
    try c.addFiles("proj", [dir + "/proj/docs/spec.md"], cwd: "/")   // same file, absolute: ignored
    #expect(c.projects[0].keyFiles == ["docs/spec.md"])
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

@Test func keyFilesMayBeFolders() throws {
    let dir = try fixture()
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    try c.addFiles("proj", [dir + "/proj/docs", dir + "/proj/docs/spec.md"], cwd: "/")
    #expect(c.projects[0].keyFiles == ["docs", "docs/spec.md"])
}

@Test func keyFilesOutsideProjectAreStoredAbsolute() throws {
    let dir = try fixture()
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    try c.addFiles("proj", ["outside.md", "other"], cwd: dir)
    try c.addFiles("proj", [dir + "/outside.md"], cwd: "/")         // same item again: ignored
    #expect(c.projects[0].keyFiles == [dir + "/outside.md", dir + "/other"])
    let p = c.projects[0]
    #expect(p.fullPath(of: "docs/spec.md") == dir + "/proj/docs/spec.md")
    #expect(p.fullPath(of: dir + "/outside.md") == dir + "/outside.md")
    try c.removeFiles("proj", ["outside.md"], cwd: dir)                // path relative to cwd
    try c.removeFiles("proj", [dir + "/other"], cwd: "/")              // stored path
    #expect(c.projects[0].keyFiles.isEmpty)
    #expect(throws: FFError.notInList(dir + "/outside.md")) { try c.removeFiles("proj", ["outside.md"], cwd: dir) }
}

@Test func keyFileDisplayNames() {
    let p = Project(name: "p", path: "/code/p")
    #expect(p.displayName(of: "docs/spec.md") == "docs/spec.md")
    #expect(p.displayName(of: "/Users/me/Documents/Accounting2026") == "(external)/Accounting2026")
    #expect(p.displayName(of: "/Users/me/Documents/Accounting2026/") == "(external)/Accounting2026")
}

/// Makes each path (relative to `root`) a fake git repo: a folder with a `.git` folder inside.
private func makeRepos(_ root: String, _ paths: [String]) throws {
    for p in paths {
        try FileManager.default.createDirectory(atPath: root + "/" + p + "/.git", withIntermediateDirectories: true)
    }
}

@Test func reposAddedRejectedAndRemoved() throws {
    let dir = try fixture()
    try makeRepos(dir, ["proj/a", "ext"])
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    try c.addRepos("proj", ["proj/a", "ext"], cwd: dir)
    try c.addRepos("proj", [dir + "/proj/a"], cwd: "/")              // same repo again: ignored
    #expect(c.projects[0].repos == ["a", dir + "/ext"])
    #expect(throws: FFError.notARepository(dir + "/proj/docs")) { try c.addRepos("proj", ["proj/docs"], cwd: dir) }
    #expect(throws: FFError.notARepository(dir + "/nope")) { try c.addRepos("proj", ["nope"], cwd: dir) }
    try c.removeRepos("proj", ["a", dir + "/ext"], cwd: "/")
    #expect(c.projects[0].repos.isEmpty)
    #expect(throws: FFError.notInList("a")) { try c.removeRepos("proj", ["a"], cwd: dir + "/proj") }
}

@Test func findReposSearchesThreeLevelsSkippingHiddenAndNested() throws {
    let dir = try fixture()
    try makeRepos(dir + "/proj", ["a", "group/b", "group/b/nested", "l1/l2/l3", "l1/l2/l3x/l4", ".hidden/c"])
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    #expect(try c.findRepos("proj") == 3)
    #expect(c.projects[0].repos == ["a", "group/b", "l1/l2/l3"])
    #expect(try c.findRepos("proj") == 0)                              // nothing new the second time
}

@Test func projectWithoutFolder() throws {
    let dir = try fixture()
    try makeRepos(dir, ["r1", "r2"])
    var c = Config()
    #expect(throws: FFError.emptyName) { try c.add(path: nil, cwd: dir) }
    try c.add(path: nil, name: "Pair", cwd: dir)
    #expect(c.projects[0].path == nil)
    try c.addRepos("Pair", ["r1", "r2"], cwd: dir)
    #expect(c.projects[0].repos == [dir + "/r1", dir + "/r2"])
    #expect(c.projects[0].displayName(of: dir + "/r1") == "r1")
    #expect(c.projects[0].fullPath(of: dir + "/r1") == dir + "/r1")
    #expect(throws: FFError.noFolder("Pair")) { try c.findRepos("Pair") }
}

@Test func clearPathMakesItemsAbsolute() throws {
    let dir = try fixture()
    try makeRepos(dir, ["proj/a"])
    var c = Config()
    try c.add(path: "proj", cwd: dir)
    try c.addFiles("proj", ["proj/docs/spec.md"], cwd: dir)
    try c.addRepos("proj", ["proj/a"], cwd: dir)
    try c.clearPath("proj")
    #expect(c.projects[0].path == nil)
    #expect(c.projects[0].keyFiles == [dir + "/proj/docs/spec.md"])
    #expect(c.projects[0].repos == [dir + "/proj/a"])
}

@Test func notesSetAndBlankCleared() throws {
    var c = Config(projects: [Project(name: "A", path: nil)])
    try c.setNotes("a", "Call Bob\nabout the API")
    #expect(c.projects[0].notes == "Call Bob\nabout the API")
    try c.setNotes("A", "  \n")
    #expect(c.projects[0].notes == nil)
    #expect(throws: FFError.self) { try c.setNotes("Z", "x") }
}
