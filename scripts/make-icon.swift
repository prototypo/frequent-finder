// Draws Resources/AppIcon.icns. Run from the repo root: swift scripts/make-icon.swift
import AppKit

/// One square PNG on the macOS icon grid: a rounded 824/1024 body with the menu bar symbol on it.
func render(_ px: Int) -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("could not create bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    guard let gradient = NSGradient(starting: NSColor(srgbRed: 0.30, green: 0.60, blue: 1.00, alpha: 1),
                                    ending: NSColor(srgbRed: 0.08, green: 0.33, blue: 0.82, alpha: 1))
    else { fatalError("could not create gradient") }
    gradient.draw(in: NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s), angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: 420 * s, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let base = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil)
    else { fatalError("missing SF Symbol folder.badge.gearshape") }
    guard let symbol = base.withSymbolConfiguration(config) else { fatalError("could not apply symbol configuration") }
    let size = symbol.size
    symbol.draw(in: NSRect(x: (CGFloat(px) - size.width) / 2, y: (CGFloat(px) - size.height) / 2,
                           width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
    return png
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
