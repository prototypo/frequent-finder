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

@Test func bothUnstampedNotesKeepBoth() {
    let r1 = mergeText("x", nil, "y", nil, join: .notes)
    let r2 = mergeText("y", nil, "x", nil, join: .notes)
    #expect(r1 == r2)
    #expect(r1.0?.hasPrefix("x") == true && r1.0?.hasSuffix("y") == true)
    // The joined text dominates both inputs, so merging again is a no-op.
    #expect(mergeText(r1.0, r1.1, "y", nil, join: .notes) == r1)
    #expect(mergeText("x", nil, r1.0, r1.1, join: .notes) == r1)
}

@Test func bothUnstampedValueIsSymmetric() {
    #expect(mergeValue(1, nil, 2, nil) == mergeValue(2, nil, 1, nil))
    let s = stamp(5, "Mac", ["A": 1])
    #expect(mergeValue(1, s, 2, s).0 == mergeValue(2, s, 1, s).0)
}

@Test func equalAtAndByIsSymmetric() {
    let a = stamp(5, "Mac", ["A": 1]), b = stamp(5, "Mac", ["B": 1])
    #expect(mergeValue(1, a, 2, b).0 == mergeValue(2, b, 1, a).0)
    #expect(mergeText("x", a, "y", b, join: .notes).0 == mergeText("y", b, "x", a, join: .notes).0)
}

@Test func nilTextKeepsMaxClock() {
    let a = stamp(5, "Mac", ["A": 1]), b = stamp(6, "iPhone", ["B": 1])
    #expect(mergeText(nil, a, "x", b, join: .notes).1?.clock == ["A": 1, "B": 1])
    #expect(mergeText("x", b, nil, a, join: .notes).1?.clock == ["A": 1, "B": 1])
}

@Test func unreadableDeviceFileThrows() throws {
    let url = URL(fileURLWithPath: try makeTempDir()).appendingPathComponent("device.json")
    let original = try JSONEncoder().encode(Device(id: "keep", name: "Keep"))
    try original.write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
    #expect(throws: (any Error).self) { try Device.load(from: url) }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    #expect(try Data(contentsOf: url) == original)
    // Invalid JSON also throws and is left alone.
    try Data("not json".utf8).write(to: url)
    #expect(throws: (any Error).self) { try Device.load(from: url) }
    #expect(try Data(contentsOf: url) == Data("not json".utf8))
}
