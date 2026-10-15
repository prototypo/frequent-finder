import Foundation

public enum CLI {
    public static let usage = """
    usage:
      ff list [--json]                      show all projects
      ff add <path> [--name "Name"]         add a project (name defaults to the folder name)
      ff add --name "Name"                  add a project with no folder (only repos, files, links)
      ff remove <name>
      ff rename <name> <new-name>
      ff activate <name>                    show the project in the menu again (the default)
      ff deactivate <name>                  hide the project from the menu
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
        case "list": output = try list(a, config: config, json: json)
        case "set-path": try runSetPath(a, config: &config, noFolder: noFolder, cwd: cwd)
        case "file": try runFile(a, config: &config, cwd: cwd)
        case "repo": output = try runRepo(a, config: &config, cwd: cwd)
        case "url": try runURL(a, config: &config, label: label)
        case "terminal": output = try runTerminal(a, config: &config)
        default: try runProject(command, a, config: &config, name: name, cwd: cwd)
        }

        if config != before { try store.save(config) }
        return output
    }

    /// Formats the project list as JSON, tab-separated lines, or a hint when empty.
    private static func list(_ a: [String], config: Config, json: Bool) throws -> String {
        try expect(a.isEmpty)
        if json {
            return String(decoding: try config.jsonData(), as: UTF8.self)
        } else if config.projects.isEmpty {
            return "No projects. Add one with: ff add <path>"
        }
        return config.projects.map { "\($0.name)\t\($0.path ?? "(no folder)")\($0.active ? "" : "\t(inactive)")" }
            .joined(separator: "\n")
    }

    /// Handles add, remove, rename, activate and deactivate; anything else is a usage error.
    private static func runProject(_ command: String, _ a: [String], config: inout Config, name: String?, cwd: String) throws {
        switch command {
        case "add":
            try expect(a.count == 1 || (a.isEmpty && name != nil))
            try config.add(path: a.first, name: name, cwd: cwd)
        case "remove":
            try expect(a.count == 1)
            try config.remove(a[0])
        case "rename":
            try expect(a.count == 2)
            try config.rename(a[0], to: a[1])
        case "activate", "deactivate":
            try expect(a.count == 1)
            try config.setActive(a[0], command == "activate")
        default:
            throw FFError.usage(usage)
        }
    }

    /// Sets a project's folder, or clears it with --none.
    private static func runSetPath(_ a: [String], config: inout Config, noFolder: Bool, cwd: String) throws {
        if noFolder {
            try expect(a.count == 1)
            try config.clearPath(a[0])
        } else {
            try expect(a.count == 2)
            try config.setPath(a[0], to: a[1], cwd: cwd)
        }
    }

    /// Adds or removes a project's key files.
    private static func runFile(_ a: [String], config: inout Config, cwd: String) throws {
        try expect(a.count >= 3)
        let files = Array(a.dropFirst(2))
        switch a[0] {
        case "add": try config.addFiles(a[1], files, cwd: cwd)
        case "remove": try config.removeFiles(a[1], files, cwd: cwd)
        default: throw FFError.usage(usage)
        }
    }

    /// Adds, removes or finds a project's repositories; only find produces output.
    private static func runRepo(_ a: [String], config: inout Config, cwd: String) throws -> String {
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
            return "Added \(added) \(added == 1 ? "repository" : "repositories")."
        default: throw FFError.usage(usage)
        }
        return ""
    }

    /// Adds or removes a project's link.
    private static func runURL(_ a: [String], config: inout Config, label: String?) throws {
        try expect(a.count == 3)
        switch a[0] {
        case "add": try config.setURL(a[1], url: a[2], label: label)
        case "remove": try config.removeURL(a[1], url: a[2])
        default: throw FFError.usage(usage)
        }
    }

    /// Sets the terminal app, or returns the current one when no value is given.
    private static func runTerminal(_ a: [String], config: inout Config) throws -> String {
        try expect(a.count <= 1)
        guard let value = a.first else { return config.terminal.rawValue }
        guard let terminal = TerminalApp(rawValue: value.lowercased()) else { throw FFError.usage(usage) }
        config.terminal = terminal
        return ""
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
