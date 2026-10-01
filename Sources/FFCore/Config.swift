import Foundation

public enum TerminalApp: String, Codable, CaseIterable, Sendable {
    case terminal, iterm

    public var bundleID: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        }
    }

    public var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm: "iTerm"
        }
    }
}

public struct ProjectURL: Codable, Hashable, Sendable {
    public var url: String
    public var label: String?

    public init(url: String, label: String? = nil) {
        self.url = url
        self.label = label
    }

    /// Text to show: the label, or the URL when there is no label.
    public var title: String { label ?? url }
}

public struct Project: Codable, Hashable, Sendable {
    public var name: String
    /// Absolute path of the project's top-level folder.
    public var path: String
    /// Paths relative to `path`.
    public var keyFiles: [String]
    public var urls: [ProjectURL]

    public init(name: String, path: String, keyFiles: [String] = [], urls: [ProjectURL] = []) {
        self.name = name
        self.path = path
        self.keyFiles = keyFiles
        self.urls = urls
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        keyFiles = try c.decodeIfPresent([String].self, forKey: .keyFiles) ?? []
        urls = try c.decodeIfPresent([ProjectURL].self, forKey: .urls) ?? []
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var terminal: TerminalApp
    public var projects: [Project]

    public init(terminal: TerminalApp = .terminal, projects: [Project] = []) {
        self.terminal = terminal
        self.projects = projects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        terminal = try c.decodeIfPresent(TerminalApp.self, forKey: .terminal) ?? .terminal
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
    }

    /// The config as pretty-printed JSON, exactly as saved to disk.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    /// `$FF_CONFIG` if set, else `~/.config/frequent-finder/projects.json`.
    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["FF_CONFIG"] {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/frequent-finder/projects.json")
    }

    /// A missing file is an empty config. A file that cannot be parsed throws `FFError.badConfig`.
    public func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            throw FFError.badConfig("\(url.path): \(error.localizedDescription)")
        }
    }

    /// Writes atomically: a temp file in the same folder replaces the original.
    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.jsonData().write(to: url, options: .atomic)
    }

    /// Re-reads the file, applies `change`, and saves if anything changed. Reading first means
    /// edits made by others since our last read are kept, and a broken file is never overwritten.
    @discardableResult
    public func update(_ change: (inout Config) throws -> Void) throws -> Config {
        var config = try load()
        let before = config
        try change(&config)
        if config != before { try save(config) }
        return config
    }
}
