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

// MARK: - merged(with:)

private let devB = Device(id: "B", name: "Mac B")
private func at(_ s: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + s) }

/// A shared starting copy with one project, stamped by A at t=0.
private func start(_ p: Project = project()) -> Config {
    Config(projects: [p]).stamped(from: Config(), by: dev, now: at(0))
}

private func edit(_ c: Config, by d: Device, at t: Double, _ change: (inout Config) -> Void) -> Config {
    var n = c
    change(&n)
    return n.stamped(from: c, by: d, now: at(t))
}

@Test func differentFieldsBothSurvive() {
    let s = start()
    let a = edit(s, by: dev, at: 10) { $0.projects[0].name = "New" }
    let b = edit(s, by: devB, at: 20) { $0.projects[0].notes = "notes" }
    let m = a.merged(with: b)
    #expect(m.projects[0].name == "New")
    #expect(m.projects[0].notes == "notes")
}

@Test func perMacFieldsStayLocal() {
    let s = start()
    var b = edit(s, by: devB, at: 10) { $0.projects[0].name = "B" }
    b.projects[0].path = "/elsewhere"
    b.projects[0].keyFiles = ["k"]
    let m = s.merged(with: b)
    #expect(m.projects[0].path == "/p")
    #expect(m.projects[0].keyFiles.isEmpty)
    #expect(m.projects[0].name == "B")
}

@Test func newProjectFromOtherHasNoPath() {
    let s = start()
    var q = project("Q")
    q.keyFiles = ["k"]
    q.repos = ["r"]
    let b = edit(s, by: devB, at: 10) { $0.projects.append(q) }
    let m = s.merged(with: b)
    let got = m.projects.first { $0.id == q.id }
    #expect(got?.name == "Q")
    #expect(got?.path == nil && got?.keyFiles == [] && got?.repos == [])
}

@Test func deleteBeatsOlderEdit() {
    let s = start()
    let a = edit(s, by: dev, at: 20) { $0.projects.removeAll() }
    let b = edit(s, by: devB, at: 10) { $0.projects[0].notes = "old edit" }
    #expect(a.merged(with: b).projects.isEmpty)
    #expect(b.merged(with: a).projects.isEmpty)
    #expect(b.merged(with: a).deleted.count == 1)
}

@Test func newerEditBeatsDelete() {
    let s = start()
    let a = edit(s, by: dev, at: 10) { $0.projects.removeAll() }
    let b = edit(s, by: devB, at: 20) { $0.projects[0].notes = "kept" }
    for m in [a.merged(with: b), b.merged(with: a)] {
        #expect(m.projects.map(\.notes) == ["kept"])
        #expect(m.deleted.isEmpty)
    }
}

@Test func typedNotesMergeCleanly() {
    let s = start()
    var a = s
    for i in 1...300 {
        a = edit(a, by: dev, at: Double(i)) { $0.projects[0].notes = ($0.projects[0].notes ?? "") + "x" }
    }
    #expect(a.merged(with: s).projects[0].notes == String(repeating: "x", count: 300))
    #expect(s.merged(with: a).projects[0].notes == String(repeating: "x", count: 300))
}

@Test func concurrentNotesKeptBoth() {
    let s = start()
    let a = edit(s, by: dev, at: 10) { $0.projects[0].notes = "from A" }
    let b = edit(s, by: devB, at: 20) { $0.projects[0].notes = "from B" }
    let notes = a.merged(with: b).projects[0].notes ?? ""
    #expect(notes.hasPrefix("from A") && notes.hasSuffix("from B"))
    #expect(notes.contains("— Also edited on Mac B"))
}

/// Two diverged copies exercising every merge path.
private func diverged() -> (Config, Config) {
    let p = project("P"), q = project("Q"), r = project("R")
    let s = Config(projects: [p, q, r]).stamped(from: Config(), by: dev, now: at(0))
    let a = edit(s, by: dev, at: 10) {
        $0.projects[0].notes = "A notes"
        $0.projects[1].name = "Q2"
        $0.projects.remove(at: 2)
        $0.projects.append(project("A new"))
    }
    let b = edit(s, by: devB, at: 20) {
        $0.projects[0].notes = "B notes"
        $0.projects[0].active = false
        $0.projects.reverse()
        $0.projects.append(project("B new"))
    }
    return (a, b)
}

@Test func mergeIsIdempotent() {
    let (a, b) = diverged()
    let m = a.merged(with: b)
    #expect(m.merged(with: b) == m)
    #expect(m.merged(with: a) == m)
}

@Test func sharedPartIsSymmetric() {
    var (a, b) = diverged()
    // Equal per-Mac fields: give each new project the same path on both sides.
    for i in a.projects.indices { a.projects[i].path = nil }
    for i in b.projects.indices { b.projects[i].path = nil }
    #expect(a.merged(with: b) == b.merged(with: a))
    #expect(a.merged(with: b).projects.count == 4)
}

@Test func unstampedOrderConverges() {
    let p = project("P"), q = project("Q")
    let a = Config(projects: [p, q]), b = Config(projects: [q, p])
    #expect(a.merged(with: b).projects.map(\.id) == b.merged(with: a).projects.map(\.id))
}

@Test func tombstoneEqualToEditKeepsProject() {
    let s = start()
    let a = edit(s, by: dev, at: 10) { $0.projects.removeAll() }
    let b = edit(s, by: devB, at: 10) { $0.projects[0].notes = "same instant" }
    #expect(a.merged(with: b).projects.map(\.notes) == ["same instant"])
    #expect(b.merged(with: a).projects.map(\.notes) == ["same instant"])
}
