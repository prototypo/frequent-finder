import Foundation
import Testing
@testable import FFCore

/// Writes a minimal `<name>.app` with an Info.plist in a temp folder.
private func makeApp(name: String, bundleID: String, schemes: [String]?) throws -> URL {
    let app = URL(fileURLWithPath: try makeTempDir()).appendingPathComponent("\(name).app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name]
    if let schemes { plist["CFBundleURLTypes"] = [["CFBundleURLSchemes": schemes]] }
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return app
}

@Test func linkedAppReadsInfoPlist() throws {
    let app = try LinkedApp(appAt: makeApp(name: "Boards", bundleID: "org.example.Boards", schemes: ["boards", "other"]))
    #expect(app == LinkedApp(bundleID: "org.example.Boards", name: "Boards", scheme: "boards"))
}

@Test func linkedAppFromAppWithoutSchemeThrows() throws {
    let url = try makeApp(name: "Plain", bundleID: "org.example.Plain", schemes: nil)
    #expect(throws: FFError.notLinkable("Plain")) { try LinkedApp(appAt: url) }
}

@Test func linkedAppFromNonAppThrows() throws {
    let url = URL(fileURLWithPath: try makeTempDir()).appendingPathComponent("notes.txt")
    try Data("hi".utf8).write(to: url)
    #expect(throws: FFError.notLinkable("notes.txt")) { try LinkedApp(appAt: url) }
}

@Test func linkRoundTrips() {
    let id = UUID(), app = LinkedApp(bundleID: "b", name: "B", scheme: "boards")
    #expect(app.link(to: id)?.absoluteString == "boards://project/\(id.uuidString.lowercased())")
    #expect(LinkedApp.projectID(in: app.link(to: id)!, scheme: "boards") == id)
    #expect(LinkedApp.projectID(in: URL(string: "boards://project/\(id.uuidString)")!, scheme: "BOARDS") == id)
}

@Test func projectIDRejectsBadLinks() {
    for s in ["boards://project/nope", "boards://board/\(UUID())", "other://project/\(UUID())",
              "boards://project/\(UUID())/extra", "boards://project/"] {
        #expect(LinkedApp.projectID(in: URL(string: s)!, scheme: "boards") == nil, "\(s)")
    }
}

@Test func addLinkedAppReplacesSameBundleID() throws {
    var apps: [LinkedApp] = []
    try apps.add(LinkedApp(bundleID: "b", name: "Old", scheme: "x"), selfBundleID: "me")
    try apps.add(LinkedApp(bundleID: "c", name: "C", scheme: "c"), selfBundleID: "me")
    try apps.add(LinkedApp(bundleID: "b", name: "New", scheme: "y"), selfBundleID: "me")
    #expect(apps.map(\.name) == ["New", "C"])
    #expect(throws: FFError.linkedSelf("Me")) { try apps.add(LinkedApp(bundleID: "me", name: "Me", scheme: "m"), selfBundleID: "me") }
    apps.remove(bundleID: "b")
    #expect(apps.map(\.name) == ["C"])
}

@Test func configWithoutLinkedAppsDecodes() throws {
    let c = try JSONDecoder().decode(Config.self, from: Data(#"{"terminal":"iterm","projects":[]}"#.utf8))
    #expect(c.linkedApps.isEmpty)
}

@Test func configKeepsLinkedApps() throws {
    var c = Config()
    c.linkedApps = [LinkedApp(bundleID: "b", name: "B", scheme: "boards")]
    #expect(try JSONDecoder().decode(Config.self, from: c.jsonData()) == c)
}

@Test func linkedAppRejectsBadScheme() throws {
    for bad in ["my scheme", "%", "é", "-n", "1abc"] {
        let url = try makeApp(name: "Odd", bundleID: "org.example.Odd", schemes: [bad])
        #expect(throws: FFError.notLinkable("Odd"), "\(bad)") { try LinkedApp(appAt: url) }
    }
}

@Test func badSchemeFromConfigDoesNotCrash() {
    let app = LinkedApp(bundleID: "b", name: "B", scheme: "my scheme")
    #expect(app.link(to: UUID()) == nil)
    #expect(throws: FFError.badURL("my scheme://project/…")) { try app.open(UUID()) }
}
