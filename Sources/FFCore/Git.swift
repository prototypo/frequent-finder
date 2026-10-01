import Foundation

public struct GitStatus: Equatable, Sendable {
    public let branch: String
    /// Number of changed, staged or untracked entries.
    public let changes: Int
    /// Commits not yet pushed to / pulled from the upstream branch. 0 when there is no upstream.
    /// `behind` is only as fresh as the last `git fetch`.
    public var ahead: Int = 0
    public var behind: Int = 0
    public var isDirty: Bool { changes > 0 }

    /// "↑2 ↓1", "↑2", or "" when in sync.
    public var syncSummary: String {
        [ahead > 0 ? "↑\(ahead)" : nil, behind > 0 ? "↓\(behind)" : nil].compactMap { $0 }.joined(separator: " ")
    }
}

public enum Git {
    /// Parses `git status --porcelain=v2 --branch` output.
    public static func parse(_ porcelain: String) -> GitStatus {
        var branch = "unknown"
        var changes = 0
        var ahead = 0
        var behind = 0
        for line in porcelain.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                branch = String(line.dropFirst("# branch.head ".count))
                if branch == "(detached)" { branch = "detached" }
            } else if line.hasPrefix("# branch.ab ") {
                // "# branch.ab +<ahead> -<behind>"
                let parts = line.split(separator: " ")
                if parts.count == 4 {
                    ahead = Int(parts[2].dropFirst()) ?? 0
                    behind = Int(parts[3].dropFirst()) ?? 0
                }
            } else if !line.hasPrefix("#") {
                changes += 1
            }
        }
        return GitStatus(branch: branch, changes: changes, ahead: ahead, behind: behind)
    }

    /// Blocks while git runs; call off the main thread. `nil` = not a git repository (or git failed).
    public static func status(at path: String) -> GitStatus? {
        let result = runProcess("/usr/bin/git", ["-C", path, "status", "--porcelain=v2", "--branch"])
        return result.status == 0 ? parse(result.out) : nil
    }
}
