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
        if let data = try? Data(contentsOf: url) {
            return try JSONDecoder().decode(Device.self, from: data)
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

/// True if side a is the later one: by causality, else larger `at`, else larger `by`.
private func aWins(_ a: Stamp?, _ b: Stamp?) -> Bool {
    switch causal(a, b) {
    case .aBeforeB: return false
    case .bBeforeA: return true
    case .same, .concurrent:
        let (x, y) = (a?.at ?? 0, b?.at ?? 0)
        return x != y ? x > y : (a?.by ?? "") >= (b?.by ?? "")
    }
}

public func mergeValue<T: Equatable>(_ a: T, _ sa: Stamp?, _ b: T, _ sb: Stamp?) -> (T, Stamp?) {
    let winner = aWins(sa, sb) ? sa : sb
    let stamp = winner.map { Stamp(at: $0.at, by: $0.by, clock: maxClock(sa, sb)) }
    return (aWins(sa, sb) ? a : b, stamp)
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
    guard let ta = a, let tb = b, ta != tb, causal(sa, sb) == .concurrent, let sa, let sb else {
        if a == nil { return (b, sb) }
        if b == nil { return (a, sa) }
        return mergeValue(a, sa, b, sb)
    }
    let newer = aWins(sa, sb) ? sa : sb
    let (old, new) = aWins(sa, sb) ? (tb, ta) : (ta, tb)
    let divider: String
    switch join {
    case .title: divider = " / "
    case .notes:
        let date = dividerFormatter.string(from: Date(timeIntervalSince1970: newer.at))
        divider = "\n\n— Also edited on \(newer.by), \(date) —\n\n"
    }
    return (old + divider + new, Stamp(at: newer.at, by: newer.by, clock: maxClock(sa, sb)))
}
