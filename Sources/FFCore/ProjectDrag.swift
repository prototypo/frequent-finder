import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Declared by FrequentFinder's Info.plist (UTImportedTypeDeclarations) and exported by OpenPMTools.
    public static let openPMToolsProject = UTType(exportedAs: "org.hyland-wood.openpmtools.project", conformingTo: .json)
}

/// A project dragged from OpenPMTools: its id and name, as JSON `{"id": "<UUID>", "name": "<name>"}`.
public struct ProjectDrag: Codable, Hashable, Sendable, Transferable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .openPMToolsProject)
        ProxyRepresentation(exporting: \.name)  // drops as plain text elsewhere
    }
}

extension Config {
    /// Adds a project dragged from OpenPMTools. Returns false when its id is already here.
    public mutating func addDropped(_ drag: ProjectDrag) throws -> Bool {
        if index(of: drag.id) != nil { return false }
        try add(path: nil, name: drag.name, id: drag.id, cwd: "/")
        return true
    }
}
