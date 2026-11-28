import Foundation

/// First-run setup of the two vaults. Run by the app, which is the owner's tool; an AI session never runs it.
public enum VaultSetup {
    /// Makes each vault that does not exist yet, with its rule files. When it made the owner's vault,
    /// it also writes one note per project in `config`. Returns the names of the notes it wrote.
    /// A vault's parent folder must exist, so a Mac without Dropbox does not get a stray folder.
    /// Existing vaults and files are never changed.
    @discardableResult
    public static func run(_ vaults: Vaults, config: Config) throws -> [String] {
        let fm = FileManager.default
        var made: [URL] = []
        for vault in [vaults.human, vaults.claude] where !fm.fileExists(atPath: vault.path) {
            var isDirectory: ObjCBool = false
            let parent = vault.deletingLastPathComponent().path
            guard fm.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue else { throw FFError.notADirectory(parent) }
            made.append(vault)
        }
        let humanName = vaults.human.lastPathComponent, claudeName = vaults.claude.lastPathComponent
        let deny = "\"Edit(\(vaults.human.path.hasPrefix(NSHomeDirectory() + "/") ? "" : "/")\(tilde(vaults.human.path))/**)\""
        var imported: [String] = []
        for vault in made {
            let isHuman = vault == vaults.human
            var files = [
                "AGENTS.md": isHuman ? humanRules(humanName, claudeName) : claudeRules(humanName, claudeName),
                "CLAUDE.md": "@AGENTS.md\n",
                ".claude/settings.json": isHuman ? "{\n  \"permissions\": { \"deny\": [\(deny)] }\n}\n" : """
                    {
                      "permissions": {
                        "additionalDirectories": ["\(tilde(vaults.human.path))"],
                        "deny": [\(deny)]
                      },
                      "sandbox": {
                        "enabled": true,
                        "allowUnsandboxedCommands": false,
                        "filesystem": { "denyWrite": ["\(tilde(vaults.human.path))"] }
                      }
                    }

                    """,
            ]
            if isHuman {
                files["Templates/Project.md"] = template
                for (index, project) in config.projects.enumerated() {
                    let name = fileName(for: project.name)
                    files["Projects/\(name).md"] = project.noteMarkdown(order: index + 1)
                    imported.append(name)
                }
            }
            for folder in isHuman ? ["Projects"] : ["Projects", "Backgrounds", "Scheduled"] {
                try fm.createDirectory(at: vault.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            for (path, text) in files {
                let url = vault.appendingPathComponent(path)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url, options: .withoutOverwriting)
            }
        }
        return imported
    }

    /// A project name as a file name: characters that Obsidian or the file system refuse become "-".
    public static func fileName(for projectName: String) -> String {
        String(projectName.map { "/\\:*?\"<>|#^[]".contains($0) ? "-" : $0 })
    }

    /// A `file://` address that is safe inside a Markdown link and that Obsidian can open.
    public static func fileLink(_ path: String) -> String { linkSafe(URL(fileURLWithPath: path).absoluteString) }

    /// Round brackets and spaces would end a Markdown link target early.
    static func linkSafe(_ target: String) -> String {
        target.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: " ", with: "%20")
    }

    /// `~/...` for a path in the home folder, so the text also fits another Mac.
    static func tilde(_ path: String) -> String {
        path.hasPrefix(NSHomeDirectory() + "/") ? "~" + path.dropFirst(NSHomeDirectory().count) : path
    }

    static let format = """
        ## Project notes

        One note per project: `Projects/<Project Name>.md`. The file name is the card title.

        ```
        ---
        type: project
        status: active
        order: 1
        icon: hammer
        path: ~/Code/example
        ---
        ## Files
        - [Budget](file:///Users/me/Documents/Budget%202026.xlsx)
        ## Links
        - [Board](https://example.com/board)
        - [[A note in this vault]]
        ## Notes
        Free text.
        ```

        - Properties are flat `key: value` lines. Use these names exactly. All are optional.
          - `status`: `active`, `paused` or `completed`. A completed project has no card.
          - `order`: a number. Cards sort by it, then by name.
          - `icon`: an SF Symbol name for the card art.
          - `path`: the project folder.
          - `id`: the project's id in the old project list. The card finds its Kanban board in OpenPMTools by it.
            A note without it is found by its name, so a renamed note needs it.
        - Every `## Heading` is a group on the card. Use any headings.
        - A list item with one link is something to open. All other Markdown is shown as written,
          in the same order: nested lists, headings from `###` down, bold, links in text, quotes, code,
          tables, and pictures (`![alt](address)` or `![[file.png]]`) on a line of their own.
        - Extended Markdown works too: `==highlight==`, `H~2~O`, `X^2^`, `~~strike~~`, `:emoji:` codes,
          footnotes (`[^1]` in the text, `[^1]: the note` on a line), definition lists (a term, then
          `: definition` lines), `~~~` code fences, and `### Heading {#id}` with links to `#id`.
        - A link target is a web address, a `file://` address, an absolute or `~/` path, or a `[[note]]`.
          In a target, write a space as `%20` and round brackets as `%28` and `%29`, or put the target in `<...>`.
        - A folder with `.git` in it is shown as a git repository.
        """

    static func humanRules(_ human: String, _ claude: String) -> String {
        """
        # \(human): the owner's vault

        Frequent Finder Deck reads this vault and shows one card per project.

        **AI agents: this vault is read-only.** Do not create, change, move, rename or delete anything here,
        with any tool or shell command. Your side is the `\(claude)` vault, the folder next to this one.

        ## Layout

        - `Projects/`: one note per project.
        - `Templates/Project.md`: the shape of a project note.

        \(format)

        """
    }

    static func claudeRules(_ human: String, _ claude: String) -> String {
        """
        # \(claude): the AI's vault

        Frequent Finder Deck reads this vault and the owner's vault, `\(human)`, the folder next to this one.

        - You may read and write here.
        - You may read `\(human)`. **Never write there**, with any tool or shell command.
          If you are not sure where something goes, it goes here. The owner moves what they want to keep.
        - Never put passwords, API keys or tokens in a note.

        ## Layout

        - `Projects/<Project Name>.md`: your additions to a project. Use exactly the file name of the owner's
          note in `\(human)/Projects/`. The card shows your groups with the label "From Claude".
          A name with no owner's note makes a new card. Do not repeat items the owner's note already has.
        - `Backgrounds/<Project Name>.png` (or `.jpg`, `.jpeg`, `.heic`, `.webp`): the picture for that card.
        - `Scheduled/`: scheduled actions. The format is not decided yet.

        \(format)

        """
    }

    static let template = """
        ---
        type: project
        # status: active | paused | completed
        status: active
        order:
        icon:
        path:
        ---
        ## Files

        ## Links

        ## Notes

        """
}

extension Project {
    /// The project as a vault note. `order` is its place in the old project list.
    public func noteMarkdown(order: Int) -> String {
        var lines = ["---", "type: project", "id: \(id.uuidString)", "status: \(active ? "active" : "paused")", "order: \(order)"]
        if let path { lines.append("path: \(VaultSetup.tilde(path))") }
        lines.append("---")
        func group(_ title: String, _ items: [(label: String, target: String)]) {
            guard !items.isEmpty else { return }
            lines.append("## \(title)")
            // ponytail: square brackets in a label become round ones instead of being escaped.
            lines += items.map { "- [\($0.label.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")"))](\($0.target))" }
        }
        // Inside the project folder the label is the path from it; outside, the last name.
        func label(_ item: String) -> String { item.hasPrefix("/") ? (item as NSString).lastPathComponent : item }
        group("Files", keyFiles.map { (label($0), VaultSetup.fileLink(fullPath(of: $0))) })
        group("Repos", repos.map { (label($0), VaultSetup.fileLink(fullPath(of: $0))) })
        group("Links", urls.map { ($0.title, VaultSetup.linkSafe($0.url)) })
        if let notes, !notes.isEmpty {
            // Headings go two levels down, so a "## " line in the notes does not start a new group.
            lines.append("## Notes")
            lines += notes.components(separatedBy: "\n").map { $0.wholeMatch(of: #/#{1,6}\s.*/#) == nil ? $0 : "##" + $0 }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
