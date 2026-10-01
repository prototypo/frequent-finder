import Foundation

public enum CLI {
    public static let usage = """
    usage:
      ff list [--json]                      show all projects
      ff add <path> [--name "Name"]         add a project (name defaults to the folder name)
      ff add --name "Name"                  add a project with no folder (only repos, files, links)
      ff remove <name>
      ff rename <name> <new-name>
      ff set-path <name> <path>
      ff set-path <name> --none             remove the project's folder
      ff file add <name> <file>...          add key files or folders (any location)
      ff file remove <name> <file>...
      ff repo add <name> <path>...          add git repositories with their own status
      ff repo remove <name> <path>...
      ff repo find <name>                   add every repository up to 3 levels below the project
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
        let noFolder = takeFlag("--none", from: &args)
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
                output = config.projects.map { "\($0.name)\t\($0.path ?? "(no folder)")" }.joined(separator: "\n")
            }
        case "add":
            try expect(a.count == 1 || (a.isEmpty && name != nil))
            try config.add(path: a.first, name: name, cwd: cwd)
        case "remove":
            try expect(a.count == 1)
            try config.remove(a[0])
        case "rename":
            try expect(a.count == 2)
            try config.rename(a[0], to: a[1])
        case "set-path":
            if noFolder {
                try expect(a.count == 1)
                try config.clearPath(a[0])
            } else {
                try expect(a.count == 2)
                try config.setPath(a[0], to: a[1], cwd: cwd)
            }
        case "file":
            try expect(a.count >= 3)
            let files = Array(a.dropFirst(2))
            switch a[0] {
            case "add": try config.addFiles(a[1], files, cwd: cwd)
            case "remove": try config.removeFiles(a[1], files, cwd: cwd)
            default: throw FFError.usage(usage)
            }
        case "repo":
            try expect(a.count >= 2)
            let paths = Array(a.dropFirst(2))
            switch a[0] {
            case "add":
                try expect(!paths.isEmpty)
                try config.addRepos(a[1], paths, cwd: cwd)
            case "remove":
                try expect(!paths.isEmpty)
                try config.removeRepos(a[1], paths, cwd: cwd)
            case "find":
                try expect(paths.isEmpty)
                let added = try config.findRepos(a[1])
                output = "Added \(added) \(added == 1 ? "repository" : "repositories")."
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
