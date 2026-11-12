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
        let cutoff = now.timeIntervalSince1970 - 90 * 86400
        for (k, t) in out.deleted where t < cutoff {
            out.deleted[k] = nil
            out.stamps = out.stamps.filter { !$0.key.hasPrefix(k + ".") }
        }
        return out
    }
}
