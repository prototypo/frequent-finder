import FFCore
import Foundation

do {
    let output = try CLI.run(
        Array(CommandLine.arguments.dropFirst()),
        store: ConfigStore(),
        cwd: FileManager.default.currentDirectoryPath
    )
    if !output.isEmpty { print(output) }
} catch FFError.usage(let text) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("ff: \(error)\n".utf8))
    exit(1)
}
