import Foundation

public enum FFError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case usage(String)
    case badConfig(String)
    case noSuchProject(String)
    case duplicateName(String)
    case emptyName
    case notADirectory(String)
    case fileNotFound(String)
    case fileOutsideProject(String)
    case notInList(String)
    case badURL(String)
    case launchFailed(String)

    public var description: String {
        switch self {
        case .usage(let text): text
        case .badConfig(let detail): "Cannot read config file \(detail). Fix or delete it; it was not changed."
        case .noSuchProject(let name): "No project named '\(name)'."
        case .duplicateName(let name): "A project named '\(name)' already exists."
        case .emptyName: "Project name cannot be empty."
        case .notADirectory(let path): "Not a directory: \(path)"
        case .fileNotFound(let path): "File not found: \(path)"
        case .fileOutsideProject(let path): "File is not inside the project folder: \(path)"
        case .notInList(let item): "Not in the list: \(item)"
        case .badURL(let url): "Not a valid http, https or file URL: \(url)"
        case .launchFailed(let detail): "Could not open: \(detail)"
        }
    }

    public var errorDescription: String? { description }
}
