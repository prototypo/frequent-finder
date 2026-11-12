import Foundation

/// This Mac, as the sync merge knows it. Stored per machine and never synced.
public struct Device: Codable, Hashable, Sendable {
    public var id: String
    public var name: String

    /// `$FF_DEVICE` if set, else `~/.config/frequent-finder/device.json`.
    public static var defaultURL: URL {
        if let p = ProcessInfo.processInfo.environment["FF_DEVICE"], !p.isEmpty {
            return URL(fileURLWithPath: p)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/frequent-finder/device.json")
    }

    /// Reads the device file; creates it on first use.
    public static func load(from url: URL = Device.defaultURL) throws -> Device {
        if FileManager.default.fileExists(atPath: url.path) {
            return try JSONDecoder().decode(Device.self, from: Data(contentsOf: url))
        }
        let device = Device(id: UUID().uuidString, name: Host.current().localizedName ?? "Mac")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(device).write(to: url, options: .atomic)
        return device
    }
}

/// When and where a field was last edited. `clock` is a version vector: device id to edit count.
public struct Stamp: Codable, Hashable, Sendable {
    /// Seconds since 1970, sub-second on purpose.
    public var at: Double
    /// Device name.
    public var by: String
    public var clock: [String: Int]

    public func bumped(by device: Device, now: Date) -> Stamp {
        var c = clock
        c[device.id, default: 0] += 1
        return Stamp(at: now.timeIntervalSince1970, by: device.name, clock: c)
    }

    public static func first(by device: Device, now: Date) -> Stamp {
        Stamp(at: now.timeIntervalSince1970, by: device.name, clock: [:]).bumped(by: device, now: now)
    }
}

public typealias Stamps = [String: Stamp]
/// Key to deletion time.
public typealias Tombstones = [String: Double]

public enum Causal { case same, aBeforeB, bBeforeA, concurrent }

public func causal(_ a: Stamp?, _ b: Stamp?) -> Causal {
    let ca = a?.clock ?? [:], cb = b?.clock ?? [:]
    let aLE = ca.allSatisfy { $0.value <= cb[$0.key, default: 0] }
    let bLE = cb.allSatisfy { $0.value <= ca[$0.key, default: 0] }
    switch (aLE, bLE) {
    case (true, true): return .same
    case (true, false): return .aBeforeB
    case (false, true): return .bBeforeA
    case (false, false): return .concurrent
    }
}

private func maxClock(_ a: Stamp?, _ b: Stamp?) -> [String: Int] {
    (a?.clock ?? [:]).merging(b?.clock ?? [:]) { max($0, $1) }
}

/// True if side a is the later one: by causality, else larger `at`, else larger `by`,
/// else the larger value as text, so argument order never changes the result.
private func aWins<T>(_ a: T, _ sa: Stamp?, _ b: T, _ sb: Stamp?) -> Bool {
    switch causal(sa, sb) {
    case .aBeforeB: return false
    case .bBeforeA: return true
    case .same, .concurrent:
        let (x, y) = (sa?.at ?? 0, sb?.at ?? 0)
        if x != y { return x > y }
        let (p, q) = (sa?.by ?? "", sb?.by ?? "")
        if p != q { return p > q }
        return String(describing: a) >= String(describing: b)
    }
}

/// Winner's at/by with the max of both clocks; nil only when both stamps are nil.
private func joined(_ winner: Stamp?, _ sa: Stamp?, _ sb: Stamp?) -> Stamp? {
    (winner ?? sa ?? sb).map { Stamp(at: $0.at, by: $0.by, clock: maxClock(sa, sb)) }
}

public func mergeValue<T: Equatable>(_ a: T, _ sa: Stamp?, _ b: T, _ sb: Stamp?) -> (T, Stamp?) {
    let w = aWins(a, sa, b, sb)
    return (w ? a : b, joined(w ? sa : sb, sa, sb))
}

public enum TextJoin { case notes, title }

private let dividerFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f
}()

public func mergeText(_ a: String?, _ sa: Stamp?, _ b: String?, _ sb: Stamp?, join: TextJoin) -> (String?, Stamp?) {
    let order = causal(sa, sb)
    // `.same` with different texts (e.g. both unstamped) is treated as concurrent: keep both.
    guard let ta = a, let tb = b, ta != tb, order == .concurrent || order == .same else {
        // A clear that is causally later wins (mergeValue below); one that is concurrent keeps the text.
        if (a == nil) != (b == nil), order == .concurrent || order == .same {
            return a == nil ? (b, joined(sb, sa, sb)) : (a, joined(sa, sa, sb))
        }
        return mergeValue(a, sa, b, sb)
    }
    let w = aWins(ta, sa, tb, sb)
    let newer = w ? sa : sb
    let (old, new) = w ? (tb, ta) : (ta, tb)
    let divider: String
    switch join {
    case .title: divider = " / "
    case .notes:
        if let newer {
            let date = dividerFormatter.string(from: Date(timeIntervalSince1970: newer.at))
            divider = "\n\n— Also edited on \(newer.by), \(date) —\n\n"
        } else {
            divider = "\n\n— Also edited on another Mac —\n\n"
        }
    }
    var clock = maxClock(sa, sb)
    // Equal clocks cannot order the joined text after its inputs, so add a merge tick;
    // otherwise merging the result with either input again would join a second time.
    if order == .same { clock["merge", default: 0] += 1 }
    return (old + divider + new, Stamp(at: newer?.at ?? 0, by: newer?.by ?? "", clock: clock))
}
