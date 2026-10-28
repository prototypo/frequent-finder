/// One line of a project's notes, sorted out for basic Markdown display.
public enum NoteLine: Equatable, Sendable {
    case heading(level: Int, text: String)
    /// A list item: nesting level (two spaces each), its marker ("•" or "1." etc.), and its text.
    case item(indent: Int, marker: String, text: String)
    case text(String)

    public init(_ line: String) {
        if let m = line.wholeMatch(of: #/(#{1,6})\s+(.*)/#) {
            self = .heading(level: m.1.count, text: String(m.2))
        } else if let m = line.wholeMatch(of: #/( *)([-*+]|\d+[.)])\s+(.*)/#) {
            self = .item(indent: m.1.count / 2, marker: m.2.first!.isNumber ? String(m.2) : "•", text: String(m.3))
        } else {
            self = .text(line)
        }
    }
}
