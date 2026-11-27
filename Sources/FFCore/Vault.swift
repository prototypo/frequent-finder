import Foundation

/// The two Obsidian vaults behind the Deck app: the owner's, and the AI's.
/// A project is `Projects/<Name>.md` in either vault, or in both.
public struct Vaults: Equatable, Sendable {
    public var human: URL
    public var claude: URL

    public init(human: URL, claude: URL) {
        self.human = human
        self.claude = claude
    }

    /// `$FF_HUMAN_VAULT` and `$FF_CLAUDE_VAULT` if set, else `FF Human` and `FF Claude` in Dropbox.
    public static var standard: Vaults {
        func url(_ variable: String, _ name: String) -> URL {
            let path = ProcessInfo.processInfo.environment[variable] ?? "~/Library/CloudStorage/Dropbox/\(name)"
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return Vaults(human: url("FF_HUMAN_VAULT", "FF Human"), claude: url("FF_CLAUDE_VAULT", "FF Claude"))
    }

    /// One card per project name, the two vaults merged, without completed projects.
    /// Sorted by the `order` property, then by name. Reads files, so call off the main thread.
    public func loadCards() -> [ProjectCard] {
        var cards: [String: ProjectCard] = [:]
        for (vault, isHuman) in [(human, true), (claude, false)] {
            let files = (try? FileManager.default.contentsOfDirectory(at: vault.appendingPathComponent("Projects"), includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "md" {
                let name = file.deletingPathExtension().lastPathComponent
                // A note that cannot be read (for example an online-only file with no network) still gets a card.
                let note = ProjectNote(markdown: (try? String(contentsOf: file, encoding: .utf8)) ?? "## Notes\nThis note could not be read.")
                var card = cards[name.lowercased()] ?? ProjectCard(name: name)
                if isHuman { card.human = note } else { card.claude = note }
                cards[name.lowercased()] = card
            }
        }
        func order(_ card: ProjectCard) -> Int { card.property("order").flatMap { Int($0) } ?? .max }
        return cards.values.filter { $0.property("status") != "completed" }.sorted {
            (order($0), "") != (order($1), "") ? order($0) < order($1) : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// The picture for a card: `Backgrounds/<name>.<png|jpg|jpeg|heic|webp>` in the AI's vault.
    public func background(for name: String) -> URL? {
        ["png", "jpg", "jpeg", "heic", "webp"]
            .map { claude.appendingPathComponent("Backgrounds/\(name).\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Where a picture named in a note is: a web address, a path on disk, or a file in the note's vault.
    /// Like Obsidian, a bare file name is found anywhere in the vault. Nil when the vault has no such file.
    /// Looks through the vault's folders, so call off the main thread.
    public static func pictureURL(_ target: String, in vault: URL) -> URL? {
        let resource = Resource(label: "", target: target)
        switch resource.kind {
        case .url: return URL(string: resource.location)
        case .file, .folder, .repo: return URL(fileURLWithPath: resource.location)
        case .other: return nil
        case .note:
            let direct = vault.appendingPathComponent(resource.location)
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            guard let files = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
            for case let file as URL in files where file.lastPathComponent == direct.lastPathComponent { return file }
            return nil
        }
    }

    /// A link that opens `file` (a path inside the vault, without `.md`) in Obsidian, or only the vault.
    /// The folder must already be open in Obsidian as a vault.
    public static func obsidianURL(vault: URL, file: String? = nil) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        func escape(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text }
        return "obsidian://open?vault=\(escape(vault.lastPathComponent))" + (file.map { "&file=\(escape($0))" } ?? "")
    }
}

/// Something a card can open.
public struct Resource: Hashable, Sendable {
    public enum Kind: Sendable { case url, repo, folder, file, note, other }

    public var label: String
    public var kind: Kind
    /// A web or other address (`url`, `other`), an absolute path (`repo`, `folder`, `file`),
    /// or a note's path inside its vault without `.md` (`note`).
    public var location: String

    /// The kind comes from the target: a web address, a path on disk (or `file://` address),
    /// another address such as `mailto:`, or else the name of a note in the same vault.
    public init(label: String, target: String) {
        var target = target.trimmingCharacters(in: .whitespaces)
        if target.hasPrefix("<"), target.hasSuffix(">") { target = String(target.dropFirst().dropLast()) }
        self.label = label.isEmpty ? target : label
        let scheme = target.prefixMatch(of: #/([A-Za-z][A-Za-z0-9+.\-]*):/#).map { $0.1.lowercased() }
        if let scheme, scheme != "file" {
            kind = scheme == "http" || scheme == "https" ? .url : .other
            location = target
            return
        }
        // ponytail: a raw path is percent-decoded too, so a file name with a literal "%20" in it cannot be linked.
        let decoded = scheme == nil ? target.removingPercentEncoding ?? target
            : URL(string: target)?.path ?? String(target.dropFirst("file://".count)).removingPercentEncoding ?? target
        let path = (decoded as NSString).expandingTildeInPath
        if path.hasPrefix("/") {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            kind = exists && isDirectory.boolValue ? (Git.isRepository(at: path) ? .repo : .folder) : .file
            location = path
        } else {
            kind = .note
            location = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
        }
    }

    /// A list item that is one link: `[label](target)`, `[[Note]]`, `[[Note|label]]`, or a bare web address.
    /// Text around the link stays in the label. Nil for an item with no link, with several links, with a picture,
    /// or with a link to a heading on the same card (`#id`).
    init?(item: String) {
        let links = item.matches(of: #/\[([^\]]*)\]\((<[^>]*>|[^)\s]*)\)/#)
        let notes = item.matches(of: #/\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]*))?\]\]/#)
        if links.count == 1, notes.isEmpty, let m = links.first, !item[..<m.range.lowerBound].hasSuffix("!"), !m.2.hasPrefix("#") {
            self.init(label: item.replacingCharacters(in: m.range, with: m.1), target: String(m.2))
        } else if notes.count == 1, links.isEmpty, let m = notes.first, !item[..<m.range.lowerBound].hasSuffix("!") {
            self.init(label: item.replacingCharacters(in: m.range, with: m.2 ?? m.1), target: String(m.1))
            kind = .note
            location = String(m.1)
        } else if item.wholeMatch(of: #/https?:\/\/\S+/#) != nil {
            self.init(label: item, target: item)
        } else {
            return nil
        }
    }
}

/// One `## Heading` of a project note, as the lines under it in the order written.
public struct NoteSection: Equatable, Sendable {
    public enum Line: Equatable, Sendable {
        /// A list item that is one link: something to open. `indent` is how deep the item is nested.
        case resource(Resource, indent: Int)
        /// Any other list item: its marker ("•", "1.", "☐" or "☑") and its Markdown text.
        case item(marker: String, text: String, indent: Int)
        /// `id` is from `### Heading {#id}`; a link to `#id` goes to the heading.
        case heading(level: Int, text: String, id: String? = nil)
        case quote(String)
        /// A line inside a ``` or ~~~ fence, kept as written.
        case code(String)
        case rule
        /// A table. Every cell is Markdown text. `align` has one entry per column of the line of dashes.
        case table(header: [String], align: [Align] = [], rows: [[String]])
        /// A line with `: definition` lines after it.
        case term(String)
        case definition(String)
        /// `[^id]: text`, the note for the mark `[^id]` in the text.
        case footnote(id: String, text: String)
        /// A picture on a line or in a list item of its own. See `Vaults.pictureURL` for the target.
        case image(alt: String, target: String, indent: Int)
        /// A line of Markdown text. Empty for a blank line between paragraphs.
        case text(String)
    }

    public enum Align: Sendable { case left, center, right }

    public var title: String
    public var lines: [Line]

    public init(title: String, lines: [Line] = []) {
        self.title = title
        self.lines = lines
    }

    public var resources: [Resource] {
        lines.compactMap { if case .resource(let resource, _) = $0 { resource } else { nil } }
    }

    /// Sorts raw note lines into `Line`s. An item is nested when it starts further right than the item
    /// before it, by any number of spaces or tabs, the way Obsidian shows it.
    static func parse(_ raw: [String]) -> [Line] {
        var lines: [Line] = []
        var levels: [Int] = []
        var fence: String?
        var next = 0
        while next < raw.count {
            let line = raw[next]
            next += 1
            let body = line.drop { $0 == " " || $0 == "\t" }
            if isFence(line, &fence) { continue }
            if fence != nil {
                lines.append(.code(line))
                continue
            }
            switch NoteLine(String(body)) {
            case .item(_, var marker, var text):
                let width = line.prefix(line.count - body.count).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                while let last = levels.last, last > width { levels.removeLast() }
                if levels.last != width { levels.append(width) }
                let indent = levels.count - 1
                if let box = text.prefixMatch(of: #/\[([ xX])\]\s+/#) {
                    marker = box.1 == " " ? "☐" : "☑"
                    text = String(text[box.range.upperBound...])
                }
                if let picture = picture(text) {
                    lines.append(.image(alt: picture.alt, target: picture.target, indent: indent))
                } else {
                    lines.append(Resource(item: text).map { .resource($0, indent: indent) } ?? .item(marker: marker, text: text, indent: indent))
                }
            case .heading(let level, let text):
                levels = []
                let id = text.firstMatch(of: #/\s*\{#([^}\s]+)\}\s*$/#)
                lines.append(.heading(level: level, text: id.map { String(text[..<$0.range.lowerBound]) } ?? text, id: id.map { String($0.1) }))
            case .text(let text):
                if text.isEmpty {
                    if lines.last != .text("") { lines.append(.text("")) }
                    continue
                }
                levels = []
                if let note = text.wholeMatch(of: #/\[\^([^\]\s]+)\]:\s*(.*)/#) {
                    lines.append(.footnote(id: String(note.1), text: String(note.2)))
                } else if text.hasPrefix(": ") {
                    // A definition: the line of text before it is its term.
                    if case .text(let term) = lines.last, !term.isEmpty { lines[lines.count - 1] = .term(term) }
                    lines.append(.definition(text.dropFirst(2).trimmingCharacters(in: .whitespaces)))
                } else if text.contains("|"), next < raw.count, raw[next].wholeMatch(of: #/\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*/#) != nil {
                    // A table: this line is its header, the next its line of dashes, then rows while lines have "|".
                    // A colon at an end of the dashes puts the column on that side; at both ends, in the middle.
                    let align: [Align] = cells(raw[next]).map { $0.hasSuffix(":") ? ($0.hasPrefix(":") ? .center : .right) : .left }
                    next += 1
                    var rows: [[String]] = []
                    while next < raw.count, raw[next].contains("|") {
                        rows.append(cells(raw[next]))
                        next += 1
                    }
                    lines.append(.table(header: cells(text), align: align, rows: rows))
                } else if let picture = picture(text) {
                    lines.append(.image(alt: picture.alt, target: picture.target, indent: 0))
                } else if text.hasPrefix(">") {
                    lines.append(.quote(text.dropFirst().trimmingCharacters(in: .whitespaces)))
                } else if text.wholeMatch(of: #/(-{3,}|\*{3,}|_{3,})/#) != nil {
                    lines.append(.rule)
                } else {
                    lines.append(.text(text))
                }
            }
        }
        while lines.first == .text("") { lines.removeFirst() }
        while lines.last == .text("") { lines.removeLast() }
        return lines
    }

    /// The cells of one table row. `\|` is a bar inside a cell, as Obsidian writes it.
    private static func cells(_ row: String) -> [String] {
        var row = row.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "\u{0}")
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.components(separatedBy: "|").map { $0.replacingOccurrences(of: "\u{0}", with: "|").trimmingCharacters(in: .whitespaces) }
    }

    /// Text that is only a picture: `![alt](target)`, or Obsidian's `![[file.png]]`. A size after `|` is dropped.
    /// `![[Some note]]` is not a picture.
    private static func picture(_ text: String) -> (alt: String, target: String)? {
        if let m = text.wholeMatch(of: #/!\[([^\]|]*)(?:\|[^\]]*)?\]\((<[^>]*>|[^)\s]*)(?:\s+"[^"]*")?\)/#) {
            return (String(m.1), String(m.2))
        }
        if let m = text.wholeMatch(of: #/!\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/#),
           ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"].contains((String(m.1) as NSString).pathExtension.lowercased()) {
            return ((String(m.1) as NSString).lastPathComponent, String(m.1))
        }
        return nil
    }
}

/// True when `line` opens or closes a code block. `fence` is the open block's marker: ``` or ~~~.
func isFence(_ line: String, _ fence: inout String?) -> Bool {
    let body = line.drop { $0 == " " || $0 == "\t" }
    if let open = fence {
        if body.hasPrefix(open) { fence = nil }
        return fence == nil
    }
    fence = ["```", "~~~"].first { body.hasPrefix($0) }
    return fence != nil
}

/// A project note: flat `key: value` properties between `---` lines, then sections.
public struct ProjectNote: Equatable, Sendable {
    public var properties: [String: String] = [:]
    /// Sections with nothing in them are left out. Lines before the first heading are a section with no title.
    public var sections: [NoteSection] = []

    public init(markdown: String) {
        var lines = markdown.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }[...]
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            for line in lines[1..<end] where !line.hasPrefix("#") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if value.count >= 2, let quote = value.first, quote == "\"" || quote == "'", value.last == quote {
                    value = String(value.dropFirst().dropLast())
                }
                if !value.isEmpty { properties[line[..<colon].trimmingCharacters(in: .whitespaces)] = value }
            }
            lines = lines[(end + 1)...]
        }
        var raw: [(title: String, lines: [String])] = [("", [])]
        var fence: String?
        for line in lines {
            if !isFence(line, &fence), fence == nil, line.hasPrefix("## ") {
                raw.append((line.dropFirst(3).trimmingCharacters(in: .whitespaces), []))
            } else {
                raw[raw.count - 1].lines.append(line)
            }
        }
        sections = raw.map { NoteSection(title: $0.title, lines: NoteSection.parse($0.lines)) }.filter { !$0.lines.isEmpty }
    }
}

/// What one card shows: the owner's note, the AI's note, or both.
public struct ProjectCard: Identifiable, Equatable, Sendable {
    /// The note's file name without `.md`.
    public var name: String
    public var human: ProjectNote?
    public var claude: ProjectNote?
    public var id: String { name }

    public init(name: String, human: ProjectNote? = nil, claude: ProjectNote? = nil) {
        self.name = name
        self.human = human
        self.claude = claude
    }

    /// The owner's value, else the AI's.
    public func property(_ key: String) -> String? { human?.properties[key] ?? claude?.properties[key] }
}

/// FNV-1a. The same on every run, unlike `Hasher`, so a name always draws the same picture.
public func stableHash(_ text: String) -> UInt64 {
    text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
}
