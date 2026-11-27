import FFCore
import SwiftUI

private let glide = Animation.timingCurve(0.16, 0.84, 0.26, 1, duration: 0.28)

/// The whole overlay: one big card in the middle, a dim one on each side, and the middle card's colours behind.
struct RootView: View {
    @Environment(DeckModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width, height = geo.size.height
            // "" is the Scheduled card; a note cannot have an empty name.
            let names = [""] + model.cards.map(\.name)
            ZStack {
                Color.black
                art(for: model.card)
                    .scaleEffect(1.4)
                    .blur(radius: 80)
                    .opacity(0.6)
                    .id(model.index)
                    .transition(.opacity)
                ForEach(Array(names.enumerated()), id: \.element) { i, _ in
                    let slot = slot(of: i)
                    // Only the middle card and its neighbours are built; the next ones out stay ready, unseen.
                    if abs(slot) <= 2 {
                        CardView(card: i == 0 ? nil : model.cards[i - 1], isHero: slot == 0)
                            .frame(width: width * 0.68, height: height * 0.74)
                            .clipShape(.rect(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.5), radius: 40, x: 16, y: 30)
                            .saturation(slot == 0 ? 1 : 0.86)
                            .brightness(slot == 0 ? 0 : -0.18)
                            .opacity(slot == 0 ? 1 : abs(slot) == 1 ? 0.7 : 0)
                            .scaleEffect(slot == 0 ? 1 : 0.8)
                            .rotation3DEffect(.degrees(Double(-4 * slot)), axis: (0, 1, 0))
                            .offset(x: CGFloat(slot) * width * 0.42)
                            .zIndex(slot == 0 ? 1 : 0)
                            .onTapGesture { model.tap(i) }
                    }
                }
                if let error = model.error {
                    Text(error)
                        .font(.title3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.85), in: .capsule)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, height * 0.05)
                }
            }
            .animation(glide, value: model.index)
            .gesture(DragGesture(minimumDistance: 40).onEnded { drag in
                if abs(drag.translation.width) > 52 { model.step(drag.translation.width < 0 ? 1 : -1) }
            })
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .environment(\.openURL, OpenURLAction { url in
            model.openLink(url)
            return .handled
        })
    }

    /// How many places card `i` is from the middle, the short way round the ring.
    private func slot(of i: Int) -> Int {
        let distance = ((i - model.index) % model.count + model.count) % model.count
        return distance > model.count / 2 ? distance - model.count : distance
    }
}

@MainActor
private func art(for card: ProjectCard?, in model: DeckModel) -> CardArt {
    CardArt(name: card?.name ?? "Scheduled", symbol: symbolName(for: card), image: card.flatMap { model.art[$0.name] })
}

extension RootView {
    fileprivate func art(for card: ProjectCard?) -> CardArt { FrequentFinderDeck.art(for: card, in: model) }
}

/// One card, always filled with its project. `card` is nil for the Scheduled card.
struct CardView: View {
    @Environment(DeckModel.self) private var model
    let card: ProjectCard?
    let isHero: Bool

    var body: some View {
        ZStack {
            art(for: card, in: model)
            Color.black.opacity(0.5)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(2)
                    .opacity(0.7)
                Text(card?.name ?? "Scheduled")
                    .font(.system(size: 40, weight: .semibold))
                    .lineLimit(1)
                if card == nil {
                    // ponytail: a placeholder; show real scheduled actions when their source is decided.
                    Text("Nothing scheduled yet.").font(.title2).opacity(0.8)
                } else {
                    // A side card shows its project but takes no clicks: a click there brings it to the middle.
                    DetailView(groups: model.groups(of: card), isHero: isHero).allowsHitTesting(isHero)
                }
            }
            .padding(44)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                model.edit(card)
            } label: {
                Image(systemName: "gearshape").font(.system(size: 22)).padding(10).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Edit in Obsidian")
            .accessibilityLabel("Edit \(card?.name ?? "Scheduled") in Obsidian")
            .padding(16)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card?.name ?? "Scheduled")
    }

    private var eyebrow: String {
        guard let card else { return NSFullUserName().uppercased() }
        let items = [card.human, card.claude].compactMap { $0 }.flatMap(\.sections).map(\.resources.count).reduce(0, +)
        return (items == 1 ? "1 ITEM" : "\(items) ITEMS") + (card.property("status") == "paused" ? "  ·  PAUSED" : "")
    }
}

/// A card's groups and rows. Only the middle card has a chosen row and takes the keys.
struct DetailView: View {
    @Environment(DeckModel.self) private var model
    let groups: [CardGroup]
    let isHero: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if groups.isEmpty { Text("Nothing here yet. Use the gear to add items in Obsidian.").opacity(0.8) }
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 10) {
                                    Text(group.title.uppercased()).tracking(1.5).opacity(0.65)
                                    if group.fromClaude {
                                        Text("From Claude")
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(.white.opacity(0.2), in: .capsule)
                                    }
                                }
                                .font(.system(size: 13, weight: .semibold))
                                ForEach(group.lines) { line in
                                    LineView(line: line, vault: model.vault(group.fromClaude), isHero: isHero)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.row) { _, row in
                    if isHero { withAnimation(glide) { proxy.scrollTo("row \(row)") } }
                }
                .onChange(of: model.anchor) { _, id in
                    guard isHero, let id else { return }
                    withAnimation(glide) { proxy.scrollTo("#\(id)", anchor: .top) }
                    model.anchor = nil
                }
            }
            Text("← → project     ↑ ↓ choose     ⏎ open     E edit     esc hide")
                .font(.system(size: 14))
                .opacity(isHero ? 0.6 : 0)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 19))
    }
}

/// One line of a note, shown as Markdown: a thing to open, a list item, a heading, a quote, code or text.
struct LineView: View {
    @Environment(DeckModel.self) private var model
    let line: CardLine
    /// The vault the note is in, for `[[links]]` in its text.
    let vault: URL
    let isHero: Bool

    var body: some View {
        switch line.line {
        case .resource(let resource, let indent):
            let row = line.row ?? 0
            RowView(label: inline(resource.label), kind: resource.kind, isSelected: isHero && row == model.row, git: model.git[resource.location])
                .padding(.leading, CGFloat(indent) * 24)
                // Text, not the bare number: the groups and lines around it already use numbers as their
                // identity, and the scroll view would go to one of those instead.
                .id("row \(row)")
                .onTapGesture {
                    model.row = row
                    model.activate()
                }
        case .item(let marker, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(marker).frame(minWidth: 28)
                Text(inline(text))
            }
            .padding(.leading, 12 + CGFloat(indent) * 24)
            .padding(.vertical, 3)
        case .heading(let level, let text, let id):
            let heading = Text(inline(text)).font(.system(size: level <= 3 ? 21 : 18, weight: .semibold)).padding(.top, 8)
            // A link to "#id" in the note's text goes here.
            if let id { heading.id("#\(id)") } else { heading }
        case .quote(let text):
            Text(inline(text)).italic().opacity(0.85).padding(.leading, 14).overlay(alignment: .leading) {
                Rectangle().frame(width: 3).opacity(0.4)
            }
        case .code(let text):
            Text(text.isEmpty ? " " : text).font(.system(size: 15, design: .monospaced)).opacity(0.9)
        case .rule:
            Divider().padding(.vertical, 6)
        case .table(let header, let align, let rows):
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                GridRow {
                    ForEach(header.indices, id: \.self) { column in
                        let side = column < align.count ? align[column] : .left
                        Text(inline(header[column]))
                            .fontWeight(.semibold)
                            .gridColumnAlignment(side == .center ? .center : side == .right ? .trailing : .leading)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        // A short row still fills every column.
                        ForEach(header.indices, id: \.self) { Text(inline($0 < rows[row].count ? rows[row][$0] : "")) }
                    }
                }
            }
            .font(.system(size: 17))
            .padding(.vertical, 6)
        case .image(let alt, let target, let indent):
            PictureView(alt: alt, target: target, vault: vault).padding(.leading, CGFloat(indent) * 24).padding(.vertical, 4)
        case .term(let text):
            Text(inline(text)).fontWeight(.semibold).padding(.top, 4)
        case .definition(let text):
            Text(inline(text)).font(.system(size: 18)).padding(.leading, 24)
        case .footnote(let id, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(id).font(.system(size: 12)).baselineOffset(5)
                Text(inline(text))
            }
            .font(.system(size: 15))
            .opacity(0.85)
        case .text(let text):
            Text(inline(text.isEmpty ? " " : text)).font(.system(size: text.isEmpty ? 8 : 18))
        }
    }

    /// Bold, italic, code, strike-through, links, highlight, subscript, superscript and emoji short codes;
    /// `[[Note]]` becomes a link into Obsidian. The text unchanged if it is not valid Markdown.
    private func inline(_ text: String) -> AttributedString {
        let linked = text.replacing(#/\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]*))?\]\]/#) { match in
            "[\(match.2 ?? match.1)](<\(Vaults.obsidianURL(vault: vault, file: String(match.1)))>)"
        }
        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var styled = try? AttributedString(markdown: ExtendedMarkdown.inline(linked), including: \.deck, options: options) else {
            return AttributedString(text)
        }
        for run in styled.runs {
            let style = run[ExtendedStyle.self]
            if style == "mark" { styled[run.range].swiftUI.backgroundColor = .yellow.opacity(0.4) }
            if style == "sub" || style == "sup" {
                // ponytail: one size for every text size; scale from the line's own size if it looks wrong in headings.
                styled[run.range].swiftUI.font = .system(size: 12)
                styled[run.range].swiftUI.baselineOffset = style == "sub" ? -4 : 7
            }
        }
        return styled
    }
}

/// What `ExtendedMarkdown.inline` marks a piece of text with: "mark", "sub" or "sup".
enum ExtendedStyle: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
    typealias Value = String
    static let name = "ff"
}

extension AttributeScopes {
    struct DeckAttributes: AttributeScope {
        let ff: ExtendedStyle
        let foundation: FoundationAttributes
        let swiftUI: SwiftUIAttributes
    }

    var deck: DeckAttributes.Type { DeckAttributes.self }
}

/// A picture from a note. It loads when its card comes near the middle.
// ponytail: no cache, so a picture is read again each time its card comes back; cache by file date if that is slow.
struct PictureView: View {
    let alt: String
    let target: String
    let vault: URL
    @State private var image: CGImage?
    @State private var isMissing = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: CGFloat(image.width), maxHeight: 300, alignment: .leading)
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityLabel(alt)
            } else {
                Text(isMissing ? "Picture not found: \(target)" : " ").font(.system(size: 15)).opacity(0.7)
            }
        }
        .task(id: target) {
            let target = target, vault = vault
            // Off the main thread: the file can be online-only in Dropbox, or on the web.
            image = await Task.detached { () -> CGImage? in
                guard let url = Vaults.pictureURL(target, in: vault) else { return nil }
                return await decodeArt(url)
            }.value
            isMissing = image == nil
        }
    }
}

struct RowView: View {
    let label: AttributedString
    let kind: Resource.Kind
    let isSelected: Bool
    let git: GitStatus?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 26).accessibilityHidden(true)
            Text(label).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let git {
                // Words and marks, not colour alone, say what state the repository is in.
                Text([git.branch, git.isDirty ? "● \(git.changes) changed" : "✓ clean", git.syncSummary].filter { !$0.isEmpty }.joined(separator: "   "))
                    .font(.system(size: 15))
                    .opacity(0.75)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.white.opacity(isSelected ? 0.2 : 0), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var symbol: String {
        switch kind {
        case .url: "globe"
        case .repo: "arrow.triangle.branch"
        case .folder: "folder"
        case .file: "doc"
        case .note: "note.text"
        case .other: "arrow.up.forward.app"
        }
    }
}
