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
