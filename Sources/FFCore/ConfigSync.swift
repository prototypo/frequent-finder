import Foundation

extension Config {
    /// Returns self with stamps and tombstones brought up to date for the edit from `before`.
    /// Per-Mac fields (path, keyFiles, repos, terminal, linkedApps) are never stamped.
    public func stamped(from before: Config, by device: Device, now: Date) -> Config {
        var out = self
        func bump(_ key: String) {
            out.stamps[key] = out.stamps[key]?.bumped(by: device, now: now) ?? .first(by: device, now: now)
        }
        let old = Dictionary(before.projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in projects {
            let k = "project:\(p.id.uuidString)"
            let o = old[p.id]
            if o == nil || o!.name != p.name { bump(k + ".name") }
            if o == nil || o!.urls != p.urls { bump(k + ".urls") }
            if o == nil || o!.active != p.active { bump(k + ".active") }
            if o == nil || o!.notes != p.notes { bump(k + ".notes") }
        }
        if projects.map(\.id) != before.projects.map(\.id) { bump("config.order") }
        let ids = Set(projects.map(\.id))
        for p in before.projects where !ids.contains(p.id) {
            let k = "project:\(p.id.uuidString)"
            out.deleted[k] = now.timeIntervalSince1970
            out.stamps = out.stamps.filter { !$0.key.hasPrefix(k + ".") }
        }
        // A re-created project must not keep its old tombstone, or pruning would strip its live stamps.
        for id in ids { out.deleted["project:\(id.uuidString)"] = nil }
        let cutoff = now.timeIntervalSince1970 - 90 * 86400
        for (k, t) in out.deleted where t < cutoff {
            out.deleted[k] = nil
            out.stamps = out.stamps.filter { !$0.key.hasPrefix(k + ".") }
        }
        return out
    }
}

extension Config {
    /// Merges another device's copy into this one. `self` is this Mac's copy: per-Mac fields
    /// (path, keyFiles, repos, terminal, linkedApps) come from it; shared fields merge by stamp.
    public func merged(with other: Config) -> Config {
        var out = self
        out.deleted = deleted.merging(other.deleted, uniquingKeysWith: max)
        out.stamps = [:]
        let mine = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let theirs = Dictionary(other.projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var kept: [UUID: Project] = [:]

        for id in Set(mine.keys).union(theirs.keys) {
            let k = "project:\(id.uuidString)"
            let keys = ["name", "urls", "active", "notes"].map { k + "." + $0 }
            switch (mine[id], theirs[id]) {
            case let (a?, b?):
                var p = a
                func field<T: Equatable>(_ key: String, _ x: T, _ y: T) -> T {
                    let (v, st) = mergeValue(x, stamps[key], y, other.stamps[key])
                    out.stamps[key] = st
                    return v
                }
                p.name = field(keys[0], a.name, b.name)
                p.urls = field(keys[1], a.urls, b.urls)
                p.active = field(keys[2], a.active, b.active)
                (p.notes, out.stamps[keys[3]]) =
                    mergeText(a.notes, stamps[keys[3]], b.notes, other.stamps[keys[3]], join: .notes)
                kept[id] = p
            case let (a, b):
                let (side, p) = a != nil ? (self, a!) : (other, b!)
                let latest = keys.compactMap { side.stamps[$0]?.at }.max() ?? -.infinity
                if let t = out.deleted[k], t > latest { continue }
                for key in keys { out.stamps[key] = side.stamps[key] }
                kept[id] = a ?? Project(id: id, name: p.name, path: nil, urls: p.urls, active: p.active, notes: p.notes)
            }
        }
        for id in kept.keys { out.deleted["project:\(id.uuidString)"] = nil }

        let mineOrder = projects.map(\.id)
        let (order, orderStamp) =
            mergeValue(mineOrder, stamps["config.order"], other.projects.map(\.id), other.stamps["config.order"])
        out.stamps["config.order"] = orderStamp
        let selfWins = order == mineOrder
        let (first, second) = selfWins ? (projects, other.projects) : (other.projects, projects)
        var seen = Set<UUID>()
        out.projects = (first + second).compactMap { p in
            seen.insert(p.id).inserted ? kept[p.id] : nil
        }
        return out
    }
}
