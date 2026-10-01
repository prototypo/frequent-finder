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
