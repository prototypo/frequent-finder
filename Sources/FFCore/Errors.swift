import Foundation

public enum FFError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case usage(String)
    case badConfig(String)
    case noSuchProject(String)
    case duplicateName(String)
    case emptyName
    case notADirectory(String)
    case fileNotFound(String)
    case notInList(String)
    case notARepository(String)
    case noFolder(String)
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
        case .notInList(let item): "Not in the list: \(item)"
        case .noFolder(let name): "Project '\(name)' has no folder."
        case .notARepository(let path): "Not a git repository (no .git inside): \(path)"
        case .badURL(let url): "Not a valid http, https or file URL: \(url)"
        case .launchFailed(let detail): "Could not open: \(detail)"
        }
    }

    public var errorDescription: String? { description }
}
