import Foundation
import Testing
@testable import FFCore

private func write(_ text: String, _ path: String) throws {
    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

/// Two vault folders that do not exist yet, inside a new temp folder.
private func tempVaults() throws -> Vaults {
    let root = URL(fileURLWithPath: try makeTempDir())
    return Vaults(human: root.appendingPathComponent("FF Human"), claude: root.appendingPathComponent("FF Claude"))
}

@Test func noteHasPropertiesGroupsAndText() {
    let note = ProjectNote(markdown: """
        ---
        type: project
        # status: active | paused | completed
        status: "paused"
        path: ~/Code/my project
        due:
        ---
        Intro line.

        ## Links
        - [Board](https://example.com/board) for the sprint
        - https://example.com/bare
        - [ ] not a link
        ## Empty
        ## Notes
        ### Sub heading
        Some text.
        """)
    #expect(note.properties == ["type": "project", "status": "paused", "path": "~/Code/my project"])
    #expect(note.sections.map(\.title) == ["", "Links", "Notes"])
    #expect(note.sections[0].lines == [.text("Intro line.")])
    #expect(note.sections[1].resources.map(\.label) == ["Board for the sprint", "https://example.com/bare"])
    #expect(note.sections[1].resources.map(\.kind) == [.url, .url])
    #expect(note.sections[1].lines.last == .item(marker: "☐", text: "not a link", indent: 0))
    #expect(note.sections[2].lines == [.heading(level: 3, text: "Sub heading"), .text("Some text.")])
}

@Test func markdownStaysInTheOrderWritten() {
    let note = ProjectNote(markdown: """
        ## Links
        - site.example
         - [repo](https://example.com/repo)
        \t- **Live** [site](https://site.example) now
        \t\t1. deeper
        - see [a](https://a.example) and [b](https://b.example)
        - ![picture|200](https://example.com/p.png)
        - [x] done
        ![[shots/Screen one.png|300]]
        ![[Some note]]

        | Name | Link \\| more |
        |:--|--:|
        | **a** | [x](https://x.example) |
        | b |
        after the table

        > quoted

        ---
        ```
        ## not a heading
          - [not](a-link)
        ```
        """)
    let site = Resource(label: "**Live** site now", target: "https://site.example")
    #expect(note.sections.count == 1)
    #expect(note.sections[0].lines == [
        .item(marker: "•", text: "site.example", indent: 0),
        .resource(Resource(label: "repo", target: "https://example.com/repo"), indent: 1),
        .resource(site, indent: 2),
        .item(marker: "1.", text: "deeper", indent: 3),
        .item(marker: "•", text: "see [a](https://a.example) and [b](https://b.example)", indent: 0),
        .image(alt: "picture", target: "https://example.com/p.png", indent: 0),
        .item(marker: "☑", text: "done", indent: 0),
        .image(alt: "Screen one.png", target: "shots/Screen one.png", indent: 0),
        .text("![[Some note]]"),
        .text(""),
        .table(header: ["Name", "Link | more"], rows: [["**a**", "[x](https://x.example)"], ["b"]]),
        .text("after the table"),
        .text(""),
        .quote("quoted"),
        .text(""),
        .rule,
        .code("## not a heading"),
        .code("  - [not](a-link)"),
    ])
    #expect(note.sections[0].resources.map(\.label) == ["repo", "**Live** site now"])
}

@Test func wikilinksAreNotes() {
    let note = ProjectNote(markdown: "## Links\n- [[Plan]]\n- [[Ideas/Big one#Part 2|The big one]]\n- [Rel](Some%20Note.md)")
    let links = note.sections[0].resources
    #expect(links.map(\.kind) == [.note, .note, .note])
    #expect(links.map(\.label) == ["Plan", "The big one", "Rel"])
    #expect(links.map(\.location) == ["Plan", "Ideas/Big one", "Some Note"])
}

@Test func kindComesFromTheTarget() throws {
    let dir = try makeTempDir()
    let repo = dir + "/a repo (old)"
    try FileManager.default.createDirectory(atPath: repo + "/.git", withIntermediateDirectories: true)
    try write("x", dir + "/file.txt")

    #expect(Resource(label: "", target: dir).kind == .folder)
    #expect(Resource(label: "", target: dir + "/file.txt").kind == .file)
    #expect(Resource(label: "", target: dir + "/missing.txt").kind == .file)
    #expect(Resource(label: "", target: "<\(repo)>") == Resource(label: repo, target: repo))
    let encoded = Resource(label: "r", target: VaultSetup.fileLink(repo))
    #expect(encoded.kind == .repo)
    #expect(encoded.location == repo)
    #expect(Resource(label: "", target: "~").location == NSHomeDirectory())
    #expect(Resource(label: "", target: "mailto:a@example.com").kind == .other)
    #expect(Resource(label: "", target: "HTTPS://example.com").kind == .url)
}

@Test func importedNoteReadsBackTheSame() throws {
    let dir = try makeTempDir()
    try write("x", dir + "/docs/Plan (v2).md")
    try FileManager.default.createDirectory(atPath: dir + "/code/.git", withIntermediateDirectories: true)
    let project = Project(name: "Demo", path: dir, keyFiles: ["docs/Plan (v2).md", "/etc/hosts"],
                          urls: [ProjectURL(url: "https://example.com/a_(b)", label: "Wiki [x]"), ProjectURL(url: "https://example.com")],
                          repos: ["code"], active: false, notes: "# Top\nBody\n## Second")
    let note = ProjectNote(markdown: project.noteMarkdown(order: 4))

    #expect(note.properties["status"] == "paused")
    #expect(note.properties["order"] == "4")
    #expect(Resource(label: "", target: note.properties["path"]!).location == dir)
    #expect(note.sections.map(\.title) == ["Files", "Repos", "Links", "Notes"])
    #expect(note.sections[0].resources.map(\.location) == [dir + "/docs/Plan (v2).md", "/etc/hosts"])
    #expect(note.sections[0].resources.map(\.label) == ["docs/Plan (v2).md", "hosts"])
    #expect(note.sections[1].resources.map(\.kind) == [.repo])
    #expect(note.sections[2].resources.map(\.label) == ["Wiki (x)", "https://example.com"])
    #expect(note.sections[2].resources[0].location == "https://example.com/a_%28b%29")
    #expect(note.sections[3].lines == [.heading(level: 3, text: "Top"), .text("Body"), .heading(level: 4, text: "Second")])
}

@Test func setupMakesBothVaultsOnceAndNeverOverwrites() throws {
    let vaults = try tempVaults()
    let config = Config(projects: [Project(name: "One", path: nil), Project(name: "A/B: two", path: nil)])

    #expect(try VaultSetup.run(vaults, config: config) == ["One", "A-B- two"])
    let fm = FileManager.default
    for path in ["AGENTS.md", "CLAUDE.md", "Templates/Project.md", ".claude/settings.json", "Projects/One.md", "Projects/A-B- two.md"] {
        #expect(fm.fileExists(atPath: vaults.human.appendingPathComponent(path).path), "human \(path)")
    }
    for path in ["AGENTS.md", "CLAUDE.md", "Backgrounds", "Scheduled", "Projects", ".claude/settings.json"] {
        #expect(fm.fileExists(atPath: vaults.claude.appendingPathComponent(path).path), "claude \(path)")
    }
    let settings = try String(contentsOf: vaults.claude.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
    #expect(settings.contains("\"Edit(/\(vaults.human.path)/**)\""))
    _ = try JSONSerialization.jsonObject(with: Data(settings.utf8))

    // A second run changes nothing, even after the owner edits and deletes notes.
    let one = vaults.human.appendingPathComponent("Projects/One.md")
    try "mine".write(to: one, atomically: true, encoding: .utf8)
    try fm.removeItem(at: vaults.human.appendingPathComponent("Projects/A-B- two.md"))
    #expect(try VaultSetup.run(vaults, config: config) == [])
    #expect(try String(contentsOf: one, encoding: .utf8) == "mine")
    #expect(try fm.contentsOfDirectory(atPath: vaults.human.appendingPathComponent("Projects").path) == ["One.md"])
}

@Test func setupNeedsTheParentFolder() throws {
    let missing = URL(fileURLWithPath: try makeTempDir()).appendingPathComponent("no/such")
    let vaults = Vaults(human: missing.appendingPathComponent("H"), claude: missing.appendingPathComponent("C"))
    #expect(throws: FFError.notADirectory(missing.path)) { try VaultSetup.run(vaults, config: Config()) }
    #expect(!FileManager.default.fileExists(atPath: missing.path))
}

@Test func cardsMergeBothVaultsInOrder() throws {
    let vaults = try tempVaults()
    try write("---\norder: 2\n---\n## Links\n- [a](https://a.example)", vaults.human.path + "/Projects/Beta.md")
    try write("---\norder: 1\nicon: hammer\n---", vaults.human.path + "/Projects/Zed.md")
    try write("---\nstatus: completed\n---", vaults.human.path + "/Projects/Done.md")
    try write("## Ideas\n- [b](https://b.example)", vaults.claude.path + "/Projects/beta.md")
    try write("---\nicon: star\n---", vaults.claude.path + "/Projects/Alpha.md")
    try write("not a project", vaults.human.path + "/Projects/readme.txt")

    let cards = vaults.loadCards()
    #expect(cards.map(\.name) == ["Zed", "Beta", "Alpha"])
    #expect(cards[1].human?.sections.map(\.title) == ["Links"])
    #expect(cards[1].claude?.sections.map(\.title) == ["Ideas"])
    #expect(cards[2].human == nil)
    #expect(cards[2].property("icon") == "star")
    #expect(Vaults(human: vaults.claude, claude: vaults.human).loadCards().count == 3)
}

@Test func backgroundIsFoundByProjectName() throws {
    let vaults = try tempVaults()
    #expect(vaults.background(for: "Beta") == nil)
    try write("x", vaults.claude.path + "/Backgrounds/Beta.webp")
    #expect(vaults.background(for: "Beta")?.lastPathComponent == "Beta.webp")
}

@Test func picturesAreFoundLikeObsidianFindsThem() throws {
    let vault = URL(fileURLWithPath: try makeTempDir())
    try write("x", vault.path + "/Attachments/deep/Screen one.png")
    try write("x", vault.path + "/.obsidian/hidden.png")
    #expect(Vaults.pictureURL("Screen one.png", in: vault)?.path.hasSuffix("/Attachments/deep/Screen one.png") == true)
    #expect(Vaults.pictureURL("Attachments/deep/Screen%20one.png", in: vault)?.lastPathComponent == "Screen one.png")
    #expect(Vaults.pictureURL("hidden.png", in: vault) == nil)
    #expect(Vaults.pictureURL("missing.png", in: vault) == nil)
    #expect(Vaults.pictureURL("https://example.com/p.png", in: vault)?.host == "example.com")
    #expect(Vaults.pictureURL("/tmp/p.png", in: vault)?.path == "/tmp/p.png")
}

@Test func obsidianLinkEscapesNames() {
    let url = Vaults.obsidianURL(vault: URL(fileURLWithPath: "/tmp/FF Human"), file: "Projects/R&D plan")
    #expect(url == "obsidian://open?vault=FF%20Human&file=Projects/R%26D%20plan")
    #expect(Vaults.obsidianURL(vault: URL(fileURLWithPath: "/tmp/FF Claude")) == "obsidian://open?vault=FF%20Claude")
}

@Test func stableHashIsFNV1a() {
    #expect(stableHash("") == 0xcbf2_9ce4_8422_2325)
    #expect(stableHash("a") == 0xaf63_dc4c_8601_ec8c)
}
