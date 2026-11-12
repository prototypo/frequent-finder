import Testing
import Foundation
@testable import FFCore

private let devA = Device(id: "A", name: "Mac")
private let devB = Device(id: "B", name: "iPhone")
private func stamp(_ at: Double, _ by: String, _ clock: [String: Int]) -> Stamp {
    Stamp(at: at, by: by, clock: clock)
}

@Test func deviceFileIsCreatedOnce() throws {
    let url = URL(fileURLWithPath: try makeTempDir()).appendingPathComponent("sub/device.json")
    let d1 = try Device.load(from: url)
    let d2 = try Device.load(from: url)
    #expect(d1 == d2)
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func causalOrder() {
    let s1 = Stamp.first(by: devA, now: Date(timeIntervalSince1970: 1))
    let s2 = s1.bumped(by: devA, now: Date(timeIntervalSince1970: 2))
    #expect(causal(nil, s1) == .aBeforeB)
    #expect(causal(s2, s1) == .bBeforeA)
    #expect(causal(s1, s2) == .aBeforeB)
    #expect(causal(s1, s1) == .same)
    let x = s1.bumped(by: devA, now: Date(timeIntervalSince1970: 3))
    let y = s1.bumped(by: devB, now: Date(timeIntervalSince1970: 3))
    #expect(causal(x, y) == .concurrent)
}

@Test func causalBeatsClock() {
    let a = Stamp.first(by: devA, now: Date(timeIntervalSince1970: 1000))
    let b = a.bumped(by: devB, now: Date(timeIntervalSince1970: 10))
    #expect(mergeValue(1, a, 2, b).0 == 2)
    #expect(mergeValue(2, b, 1, a).0 == 2)
}

@Test func concurrentValueNewerWins() {
    let a = stamp(5, "Mac", ["A": 1]), b = stamp(6, "iPhone", ["B": 1])
    let r1 = mergeValue(1, a, 2, b), r2 = mergeValue(2, b, 1, a)
    #expect(r1.0 == 2 && r2.0 == 2)
    #expect(r1.1 == r2.1)
    #expect(r1.1?.clock == ["A": 1, "B": 1])
    #expect(r1.1?.at == 6)
}

@Test func concurrentNotesKeepBoth() {
    let a = stamp(5, "Mac", ["A": 1]), b = stamp(6, "iPhone", ["B": 1])
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd HH:mm"
    let expected = "x\n\n— Also edited on iPhone, \(f.string(from: Date(timeIntervalSince1970: 6))) —\n\ny"
    let r1 = mergeText("x", a, "y", b, join: .notes)
    let r2 = mergeText("y", b, "x", a, join: .notes)
    #expect(r1.0 == expected)
    #expect(r2.0 == expected)
    #expect(r1.1 == r2.1)
    #expect(r1.1 == stamp(6, "iPhone", ["A": 1, "B": 1]))
}

@Test func concurrentTitlesKeepBoth() {
    let a = stamp(5, "Mac", ["A": 1]), b = stamp(6, "iPhone", ["B": 1])
    #expect(mergeText("x", a, "y", b, join: .title).0 == "x / y")
    #expect(mergeText("y", b, "x", a, join: .title).0 == "x / y")
}

@Test func sameTextNoCopy() {
    let a = stamp(5, "Mac", ["A": 1]), b = stamp(6, "iPhone", ["B": 1])
    #expect(mergeText("x", a, "x", b, join: .notes).0 == "x")
}

@Test func nilTextSideTakesOther() {
    let a = stamp(5, "Mac", ["A": 1])
    #expect(mergeText(nil, nil, "x", a, join: .notes).0 == "x")
    #expect(mergeText("x", a, nil, nil, join: .notes).0 == "x")
}
