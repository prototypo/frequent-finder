import Foundation
import Testing
@testable import FFCore

private let dev = Device(id: "A", name: "Mac A")
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func project(_ name: String = "P") -> Project { Project(name: name, path: "/p") }

@Test func notesChangeIsStamped() {
    let p = project()
    let c0 = Config(projects: [p])
    var c1 = c0
    c1.projects[0].notes = "hi"
    let s1 = c1.stamped(from: c0, by: dev, now: now)
    #expect(Set(s1.stamps.keys) == ["project:\(p.id.uuidString).notes"])
    #expect(s1.stamps.values.first?.clock == ["A": 1])
    var c2 = s1
    c2.projects[0].notes = "yo"
    #expect(c2.stamped(from: s1, by: dev, now: now).stamps.values.first?.clock == ["A": 2])
}

@Test func pathChangeIsNotStamped() {
    let c0 = Config(projects: [project()])
    var c1 = c0
    c1.projects[0].path = "/q"
    c1.projects[0].keyFiles = ["a"]
    c1.projects[0].repos = ["r"]
    c1.terminal = .iterm
    #expect(c1.stamped(from: c0, by: dev, now: now).stamps.isEmpty)
}

@Test func removeLeavesTombstone() {
    let p = project()
    var c0 = Config(projects: [p])
    c0 = c0.stamped(from: Config(), by: dev, now: now)
    #expect(!c0.stamps.isEmpty)
    let c1 = Config().stamped(from: c0, by: dev, now: now)
    #expect(c1.deleted["project:\(p.id.uuidString)"] == now.timeIntervalSince1970)
    #expect(c1.stamps.keys.filter { $0.hasPrefix("project:") }.isEmpty)
}

@Test func reorderStampsOrder() {
    let c0 = Config(projects: [project("a"), project("b")])
    var c1 = c0
    c1.projects.reverse()
    #expect(c1.stamped(from: c0, by: dev, now: now).stamps["config.order"] != nil)
}

@Test func oldTombstonesArePruned() {
    let day = 86400.0, t = now.timeIntervalSince1970
    var c = Config()
    c.deleted = ["project:old": t - 91 * day, "project:new": t - 89 * day]
    c.stamps = ["project:old.name": .first(by: dev, now: now)]
    let out = c.stamped(from: c, by: dev, now: now)
    #expect(Set(out.deleted.keys) == ["project:new"])
    #expect(out.stamps.isEmpty)
}

@Test func oldFileRoundTrips() throws {
    let json = #"{"terminal":"terminal","projects":[{"name":"X"}]}"#
    let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    let out = String(decoding: try c.jsonData(), as: UTF8.self)
    #expect(!out.contains("stamps") && !out.contains("deleted"))
}

@Test func cliSaveStamps() throws {
    let dir = try makeTempDir()
    let url = URL(fileURLWithPath: dir + "/projects.json")
    let store = ConfigStore(url: url, device: dev)
    try store.save(Config(projects: [project("Foo")]))
    _ = try CLI.run(["notes", "Foo", "hi"], store: store, cwd: dir)
    let saved = try store.load()
    #expect(saved.stamps.keys.contains { $0.hasSuffix(".notes") })
}
