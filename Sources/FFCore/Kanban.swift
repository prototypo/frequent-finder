import Foundation

/// The link from a card to its Kanban board in OpenPMTools. OpenPMTools opens `openpmtools://project/<id>`
/// and matches a board to a project by the id the project has in the old project list (`Config`).
public enum Kanban {
    /// OpenPMTools' data file: `$PMT_CONFIG` if set, else `~/.config/openpmtools/boards.json`.
    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["PMT_CONFIG"] {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/openpmtools/boards.json")
    }

    /// The ids of the projects that have a board. Empty when the file is missing or cannot be read.
    public static func boardProjects(at url: URL = defaultURL) -> Set<UUID> {
        struct File: Decodable {
            struct Board: Decodable { let project: UUID }
            let boards: [Board]
        }
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return Set(file.boards.map(\.project))
    }

    /// The board link for each card that has a board, by card name.
    public static func links(for cards: [ProjectCard], config: Config, boards: Set<UUID>) -> [String: String] {
        var links: [String: String] = [:]
        for card in cards {
            if let id = card.projectID(in: config), boards.contains(id) { links[card.name] = "openpmtools://project/\(id.uuidString.lowercased())" }
        }
        return links
    }
}

extension ProjectCard {
    /// The project's id in the old project list: the note's `id` property, else the id of the project
    /// there that has this card's name. A renamed note needs the `id` property.
    public func projectID(in config: Config) -> UUID? {
        property("id").flatMap { UUID(uuidString: $0) }
            ?? config.projects.first { VaultSetup.fileName(for: $0.name).caseInsensitiveCompare(name) == .orderedSame }?.id
    }
}
