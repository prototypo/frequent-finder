import Foundation

/// The extended Markdown that Apple's Markdown reader does not know: highlight, subscript, superscript,
/// footnote marks and emoji short codes. See https://www.markdownguide.org/extended-syntax/
public enum ExtendedMarkdown {
    /// Rewrites `==text==`, `H~2~O`, `X^2^`, `[^note]` and the tags `<mark>`, `<sub>`, `<sup>` as the
    /// attribute form that Apple's reader keeps: `^[text](ff: 'mark')`, with `mark`, `sub` or `sup`.
    /// A known `:short_code:` becomes its emoji. Code, link targets and web addresses stay as written.
    public static func inline(_ text: String) -> String {
        func wrap(_ inner: Substring, _ style: some StringProtocol) -> String { "^[\(inline(String(inner)))](ff: '\(style)')" }
        return text.replacing(#/
              (?<keep> \\. | (?<tick>`+).+?\k<tick> | \]\((?:<[^>]*>|[^)]*)\) | https?:\/\/\S+ | ~~.+?~~ )
            | <(?<tag>mark|sub|sup)>(?<html>.*?)<\/\k<tag>>
            | \[\^(?<note>[^\]\s]+)\]
            | ==(?<mark>\S(?:.*?\S)?)==
            | ~(?<sub>[^~\s]+)~
            | \^(?<sup>[^\^\s]+)\^
            | :(?<emoji>[a-z0-9_+\-]+):
            /#) { m in
            if let tag = m.tag, let html = m.html { return wrap(html, tag) }
            if let note = m.note { return "^[\(note)](ff: 'sup')" }
            if let mark = m.mark { return wrap(mark, "mark") }
            if let sub = m.sub { return wrap(sub, "sub") }
            if let sup = m.sup { return wrap(sup, "sup") }
            if let code = m.emoji { return emoji(String(code)) ?? String(m.0) }
            return String(m.0)
        }
    }

    /// The emoji for a short code such as `tent` or `joy`. Nil when the code is not known.
    // ponytail: the Unicode name of the emoji, plus a few common GitHub names. Other GitHub-only names
    // (for example `:sweat_smile:`) show as written; add them here, or ship the full gemoji list.
    static func emoji(_ code: String) -> String? {
        if let known = common[code] { return known }
        let name = code.replacingOccurrences(of: "_", with: " ").uppercased()
        guard let found = "\\N{\(name)}".applyingTransform(StringTransform("Name-Any"), reverse: false),
              found.unicodeScalars.count == 1, let scalar = found.unicodeScalars.first,
              scalar.properties.isEmoji, scalar.value > 0xFF else { return nil }
        // Some emoji are drawn as plain text unless this mark follows them.
        return scalar.properties.isEmojiPresentation ? found : found + "\u{FE0F}"
    }

    private static let common = [
        "joy": "😂", "smile": "😄", "grin": "😁", "laughing": "😆", "wink": "😉", "thinking": "🤔", "cry": "😢",
        "heart": "❤️", "+1": "👍", "thumbsup": "👍", "-1": "👎", "thumbsdown": "👎", "clap": "👏", "pray": "🙏",
        "wave": "👋", "eyes": "👀", "tada": "🎉", "star": "⭐", "bulb": "💡", "memo": "📝", "book": "📖",
        "warning": "⚠️", "white_check_mark": "✅", "x": "❌", "question": "❓", "exclamation": "❗", "100": "💯",
        "email": "📧", "phone": "☎️", "computer": "💻", "moneybag": "💰", "zap": "⚡", "sunny": "☀️",
    ]
}
