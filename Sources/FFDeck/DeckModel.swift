import AppKit
import FFCore
import Observation

/// One line of a card. `row` is its place in the card's one list of things to open; nil for plain text.
struct CardLine: Identifiable {
    let id: Int
    var line: NoteSection.Line
    var row: Int?
}

/// One heading of a card, from the owner's note or the AI's.
struct CardGroup: Identifiable {
    let id: Int
    var title: String
    var fromClaude: Bool
    var lines: [CardLine]
}

@MainActor @Observable
final class DeckModel {
    private(set) var cards: [ProjectCard] = []
    /// 0 is the Scheduled card. Card `n` is `cards[n - 1]`.
    private(set) var index = 0
    /// The chosen row of the middle card.
    var row = 0
    private(set) var git: [String: GitStatus] = [:]
    /// Pictures from the AI's vault, by card name.
    private(set) var art: [String: CGImage] = [:]
    /// The link to the Kanban board, by card name, for the cards that have a board.
    private(set) var boards: [String: String] = [:]
    var error: String?
    /// The id of a heading the middle card must scroll to; the card sets it back to nil.
    var anchor: String?
    @ObservationIgnored var hide: () -> Void = {}
    @ObservationIgnored let vaults = Vaults.standard
    @ObservationIgnored private var artStamps: [String: String] = [:]

    var count: Int { cards.count + 1 }
    var card: ProjectCard? { cards.indices.contains(index - 1) ? cards[index - 1] : nil }

    /// A card's sections: its folder and Kanban board, then the owner's note, then the AI's. True marks the AI's.
    private func sections(of card: ProjectCard?) -> [(NoteSection, Bool)] {
        guard let card else { return [] }
        let project = [card.property("path").map { Resource(label: "Project folder", target: $0) },
                       boards[card.name].map { Resource(label: "Kanban board", target: $0) }]
            .compactMap { $0 }.map { NoteSection.Line.resource($0, indent: 0) }
        return (project.isEmpty ? [] : [(NoteSection(title: "Project", lines: project), false)])
            + (card.human?.sections ?? []).map { ($0, false) } + (card.claude?.sections ?? []).map { ($0, true) }
    }

    func groups(of card: ProjectCard?) -> [CardGroup] {
        var row = 0
        return sections(of: card).enumerated().map { id, section in
            let lines = section.0.lines.enumerated().map { id, line in
                guard case .resource = line else { return CardLine(id: id, line: line, row: nil) }
                defer { row += 1 }
                return CardLine(id: id, line: line, row: row)
            }
            return CardGroup(id: id, title: section.0.title, fromClaude: section.1, lines: lines)
        }
    }

    /// The middle card's resources as one list, for the arrow keys.
    var rows: [Resource] { sections(of: card).flatMap(\.0.resources) }

    /// Makes the vaults on the first run, then loads the cards.
    func setUp() async {
        let vaults = vaults
        do {
            // A broken projects.json stops here, so the import is not lost for good.
            _ = try await Task.detached { try VaultSetup.run(vaults, config: ConfigStore().load()) }.value
        } catch {
            self.error = "\(error)"
        }
        reload()
    }

    /// Reads off the main thread: a Dropbox file can be online-only and slow.
    func reload() {
        let vaults = vaults
        Task {
            let (new, links) = await Task.detached {
                let cards = vaults.loadCards()
                // A broken or missing project list only means no card finds its board by name.
                return (cards, Kanban.links(for: cards, config: (try? ConfigStore().load()) ?? Config(), boards: Kanban.boardProjects()))
            }.value
            if new != cards || links != boards {
                let name = card?.name
                cards = new
                boards = links
                if let name, let i = new.firstIndex(where: { $0.name == name }) {
                    index = i + 1
                } else {
                    index = min(index, new.count)
                }
                row = min(row, max(rows.count - 1, 0))
            }
            loadArt()
            refreshGit()
        }
    }

    /// Moves round the ring.
    func step(_ by: Int) {
        error = nil
        index = ((index + by) % count + count) % count
        row = 0
        refreshGit()
    }

    func move(_ by: Int) {
        guard !rows.isEmpty else { return }
        row = min(max(row + by, 0), rows.count - 1)
    }

    /// A click on a side card brings it to the middle.
    func tap(_ i: Int) {
        if i != index { step(i - index) }
    }

    /// Opens the chosen row of the middle card.
    func activate() {
        error = nil
        guard rows.indices.contains(row) else { return }
        let resource = rows[row]
        let fromClaude = groups(of: card).first { $0.lines.contains { $0.row == row } }?.fromClaude ?? false
        open {
            switch resource.kind {
            case .repo: try Launcher.openTerminal(at: resource.location, app: (try? ConfigStore().load())?.terminal ?? .terminal)
            case .note: try Launcher.open(Vaults.obsidianURL(vault: vault(fromClaude), file: resource.location))
            default: try Launcher.open(resource.location)
            }
        }
    }

    func vault(_ fromClaude: Bool) -> URL { fromClaude ? vaults.claude : vaults.human }

    /// Opens a card's note in Obsidian: the owner's note when there is one, else the AI's.
    /// The Scheduled card has no note yet, so it opens the AI's vault, where `Scheduled/` is.
    func edit(_ card: ProjectCard?) {
        open {
            guard let card else { return try Launcher.open(Vaults.obsidianURL(vault: vaults.claude)) }
            try Launcher.open(Vaults.obsidianURL(vault: card.human != nil ? vaults.human : vaults.claude, file: "Projects/\(card.name)"))
        }
    }

    /// A link inside a card's text.
    func openLink(_ url: URL) {
        // "#id" is a heading on this card, not something to open.
        if url.scheme == nil, let id = url.fragment {
            anchor = id
            return
        }
        open { try Launcher.open(url.absoluteString) }
    }

    /// The overlay hides only when the thing did open; else the reason shows.
    private func open(_ action: () throws -> Void) {
        do {
            try action()
            hide()
        } catch {
            self.error = "\(error)"
        }
    }

    private func refreshGit() {
        for repo in rows where repo.kind == .repo {
            Task { git[repo.location] = await Task.detached { Git.status(at: repo.location) }.value }
        }
    }

    /// Decodes a card's picture again only when the file is new or changed.
    private func loadArt() {
        for card in cards {
            let url = vaults.background(for: card.name)
            let changed = url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            let stamp = url.map { "\($0.path) \(changed ?? .distantPast)" } ?? ""
            guard artStamps[card.name] != stamp else { continue }
            artStamps[card.name] = stamp
            guard let url else {
                art[card.name] = nil
                continue
            }
            Task { art[card.name] = await Task.detached { await decodeArt(url) }.value }
        }
    }
}
