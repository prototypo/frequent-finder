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

@Test func parsesAheadBehind() {
    let out = "# branch.head main\n# branch.upstream origin/main\n# branch.ab +2 -1\n"
    let s = Git.parse(out)
    #expect(s == GitStatus(branch: "main", changes: 0, ahead: 2, behind: 1))
    #expect(s.syncSummary == "↑2 ↓1")
    #expect(GitStatus(branch: "main", changes: 0, ahead: 3).syncSummary == "↑3")
    #expect(GitStatus(branch: "main", changes: 0).syncSummary == "")
}

@Test func realCloneCountsUnpushedCommits() throws {
    let dir = try makeTempDir()
    let git = { (args: [String]) in
        runProcess("/usr/bin/git", ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args).status
    }
    #expect(git(["init", "-q", "-b", "main", dir + "/origin"]) == 0)
    #expect(git(["-C", dir + "/origin", "commit", "-q", "--allow-empty", "-m", "one"]) == 0)
    #expect(git(["clone", "-q", dir + "/origin", dir + "/clone"]) == 0)
    #expect(git(["-C", dir + "/clone", "commit", "-q", "--allow-empty", "-m", "two"]) == 0)
    #expect(Git.status(at: dir + "/clone") == GitStatus(branch: "main", changes: 0, ahead: 1, behind: 0))
}
