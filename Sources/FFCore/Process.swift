import Foundation

/// Runs a program, waits for it, and returns its exit status, stdout and stderr.
/// A program that cannot start returns status -1 with the reason in `err`.
func runProcess(_ executable: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do { try process.run() } catch { return (-1, "", error.localizedDescription) }
    // ponytail: reads stdout then stderr; blocks if stderr alone fills the 64 KB pipe buffer. Fine for git/open; read both concurrently if reused for chatty tools.
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self))
}
