import AppKit
import FFCore
import ImageIO
import SwiftUI

/// A card's background: its picture, or a gradient and symbol drawn from its name.
struct CardArt: View {
    let name: String
    let symbol: String
    let image: CGImage?

    var body: some View {
        Color.clear.overlay {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                generated
            }
        }
        .clipped()
    }

    /// The same name always gives the same colours and shape.
    private var generated: some View {
        var seed = stableHash(name)
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        let hue = next()
        func mid() -> Float { Float(0.5 + (next() - 0.5) * 0.5) }
        let points: [SIMD2<Float>] = [[0, 0], [mid(), 0], [1, 0], [0, mid()], [mid(), mid()], [1, mid()], [0, 1], [mid(), 1], [1, 1]]
        let colors = (0..<9).map { _ in
            Color(hue: (hue + (next() - 0.5) * 0.22 + 1).truncatingRemainder(dividingBy: 1), saturation: 0.55 + next() * 0.4, brightness: 0.3 + next() * 0.55)
        }
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
            .overlay(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 280, weight: .light))
                    .foregroundStyle(.white.opacity(0.16))
                    .padding(48)
                    .accessibilityHidden(true)
            }
    }
}

/// The symbol for a card: its `icon` property, else a word in its name, else what it holds.
@MainActor
func symbolName(for card: ProjectCard?) -> String {
    guard let card else { return "clock" }
    let name = card.name.lowercased()
    let words: [(String, [String])] = [
        ("figure.yoga", ["yoga", "health", "fitness", "gym"]),
        ("sailboat", ["maritime", "ship", "boat", "sea", "ocean", "naval"]),
        ("newspaper", ["brief", "news", "daily", "journal"]),
        ("magnifyingglass", ["find", "search"]),
        ("cylinder.split.1x2", ["data"]),
        ("chart.line.uptrend.xyaxis", ["market", "finance", "money", "tax", "budget", "sales"]),
        ("server.rack", ["infra", "server", "cloud", "network"]),
        ("book", ["book", "manning", "writing", "paper", "thesis"]),
        ("lightbulb", ["breakthrough", "idea", "research"]),
        ("checklist", ["method", "process", "plan"]),
        ("person.3", ["coord", "team", "people"]),
        ("flame", ["fire", "game"]),
        ("house", ["home", "house"]),
        ("airplane", ["travel", "trip"]),
        ("chevron.left.forwardslash.chevron.right", ["code", "tool", "dev"]),
    ]
    let kinds = Set([card.human, card.claude].compactMap { $0 }.flatMap(\.sections).flatMap(\.resources).map(\.kind))
    let candidates = [
        card.property("icon"),
        words.first { $0.1.contains { name.contains($0) } }?.0,
        kinds.contains(.repo) ? "chevron.left.forwardslash.chevron.right" : kinds == [.url] ? "link" : nil,
    ]
    return candidates.compactMap { $0 }.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "folder"
}

/// Reads a picture at screen size, WebP included: a file, or the web address of one.
/// Nil when it is not a picture or cannot be read.
func decodeArt(_ url: URL) async -> CGImage? {
    let data = url.isFileURL ? nil : try? await URLSession.shared.data(from: url).0
    guard let source = data.map({ CGImageSourceCreateWithData($0 as CFData, nil) }) ?? CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 2560,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}
