import Foundation

/// Another app that opens `<scheme>://project/<UUID>` links. Apps link each other only through
/// this link format, so no app needs to know any other by name.
public struct LinkedApp: Codable, Hashable, Sendable {
    public var bundleID: String
    public var name: String
    public var scheme: String

    public init(bundleID: String, name: String, scheme: String) {
        self.bundleID = bundleID
        self.name = name
        self.scheme = scheme
    }

    /// Reads an app's id, name and first URL scheme from its Info.plist.
    /// Throws `FFError.notLinkable` when any of them is missing.
    public init(appAt url: URL) throws {
        let fallback = url.pathExtension == "app" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        let plist = (try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let name = plist?["CFBundleDisplayName"] as? String ?? plist?["CFBundleName"] as? String ?? fallback
        let types = plist?["CFBundleURLTypes"] as? [[String: Any]]
        guard let bundleID = plist?["CFBundleIdentifier"] as? String,
              let scheme = (types?.first?["CFBundleURLSchemes"] as? [String])?.first
        else { throw FFError.notLinkable(name) }
        self.init(bundleID: bundleID, name: name, scheme: scheme)
    }

    /// `<scheme>://project/<uuid>`, uuid in lowercase.
    public func link(to project: UUID) -> URL {
        URL(string: "\(scheme)://project/\(project.uuidString.lowercased())")!
    }

    /// The project id in a `<scheme>://project/<UUID>` link; nil for anything else.
    public static func projectID(in url: URL, scheme: String) -> UUID? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.caseInsensitiveCompare(scheme) == .orderedSame, c.host == "project"
        else { return nil }
        let parts = c.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].isEmpty else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    /// Opens the project in this app, by bundle id, so the link goes here even if another app claims the scheme.
    public func open(_ project: UUID) throws {
        try Launcher.open("-b", bundleID, link(to: project).absoluteString)
    }
}

extension Array where Element == LinkedApp {
    /// Adds an app, or replaces the entry with the same bundle id in place. An app cannot link itself.
    public mutating func add(_ app: LinkedApp, selfBundleID: String?) throws {
        if app.bundleID == selfBundleID { throw FFError.linkedSelf(app.name) }
        if let i = firstIndex(where: { $0.bundleID == app.bundleID }) { self[i] = app } else { append(app) }
    }

    public mutating func remove(bundleID: String) {
        removeAll { $0.bundleID == bundleID }
    }
}
