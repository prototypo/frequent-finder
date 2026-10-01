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
