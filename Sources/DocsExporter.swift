import AppKit

/// Development aid: renders the images the README uses, so they are generated
/// from the live renderer rather than screenshotted by hand and left to rot.
/// Invoked via `Lantern --export-docs <dir>`.
enum DocsExporter {

    /// The emotional spectrum's own order, and how each corps is reached.
    private static let corps: [(LanternGlyph.Emblem, String)] = [
        (.black, "the last 1%, or its oath"),
        (.red, "under 10%"),
        (.orange, "its oath only"),
        (.sinestro, "under 20%"),
        (.green, "every charge between"),
        (.blue, "its oath only"),
        (.indigo, "its oath only"),
        (.sapphire, "its oath only"),
        (.white, "a full charge, or its oath"),
    ]

    static func run(into path: String) {
        let dir = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        write(sheet(), to: dir.appendingPathComponent("corps.png"))
        write(menuBar(), to: dir.appendingPathComponent("menu-bar.png"))
    }

    private static func write(_ rep: NSBitmapImageRep?, to url: URL) {
        guard let data = rep?.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("failed to render \(url.lastPathComponent)\n".utf8))
            return
        }
        try? data.write(to: url)
    }

    /// A bitmap of `size` points at 2×, drawn by `body` in point coordinates.
    private static func canvas(_ size: CGSize, _ body: (CGContext) -> Void) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = size
        let previous = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previous }
        NSGraphicsContext.current = gc
        gc.cgContext.scaleBy(x: 2, y: 2)
        body(gc.cgContext)
        gc.flushGraphics()
        return rep
    }

    private static func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight,
                              _ alpha: CGFloat) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ])
    }

    private static func centred(_ str: NSAttributedString, in x: CGFloat,
                                width: CGFloat, y: CGFloat) {
        str.draw(at: CGPoint(x: x + (width - str.size().width) / 2, y: y))
    }

    /// All nine emblems, each lit to the same level so only the corps differs.
    private static func sheet() -> NSBitmapImageRep? {
        let tile: CGFloat = 220, caption: CGFloat = 44, cols = 3
        let rows = (corps.count + cols - 1) / cols
        let size = CGSize(width: tile * CGFloat(cols),
                          height: (tile + caption) * CGFloat(rows))
        return canvas(size) { ctx in
            ctx.setFillColor(NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            for (i, entry) in corps.enumerated() {
                let col = CGFloat(i % cols), row = CGFloat(i / cols)
                let originY = size.height - (row + 1) * (tile + caption)
                let x = col * tile
                LanternRenderer.draw(
                    in: ctx,
                    rect: LanternGlyph.canvas(center: CGPoint(x: x + tile / 2,
                                                              y: originY + caption + tile / 2),
                                              emblemDiameter: tile * 0.80),
                    // The same charge for every one, so the figure and the
                    // palette are the only things that differ between tiles.
                    state: .init(level: 0.62, charging: false, pluggedIn: false,
                                 time: 0.4, sworn: entry.0))
                centred(label(OathListener.name(of: entry.0), 14, .semibold, 0.92),
                        in: x, width: tile, y: originY + 22)
                centred(label(entry.1, 11, .regular, 0.45),
                        in: x, width: tile, y: originY + 7)
            }
        }
    }

    /// The same nine at the menu bar's true 19pt, magnified so the simplified
    /// figures can actually be looked at.
    private static func menuBar() -> NSBitmapImageRep? {
        let side: CGFloat = 19, zoom: CGFloat = 5, gap: CGFloat = 6
        let cell = side * zoom + gap
        let size = CGSize(width: cell * CGFloat(corps.count) + gap, height: cell + gap)
        return canvas(size) { ctx in
            ctx.setFillColor(NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.interpolationQuality = .none
            for (i, entry) in corps.enumerated() {
                // Drawn at 19pt, then blown up — not drawn large, which would
                // show the detailed figure rather than the simplified one.
                guard let icon = canvas(CGSize(width: side, height: side), { small in
                    let rect = CGRect(x: 0, y: 0, width: side, height: side)
                    LanternRenderer.draw(
                        in: small,
                        rect: LanternGlyph.canvas(center: CGPoint(x: rect.midX, y: rect.midY),
                                                  emblemDiameter: side * 0.83),
                        state: .init(level: 0.62, charging: false, pluggedIn: false,
                                     time: 0, glow: 0, sworn: entry.0))
                })?.cgImage else { continue }
                ctx.draw(icon, in: CGRect(x: gap + CGFloat(i) * cell, y: gap,
                                          width: side * zoom, height: side * zoom))
            }
        }
    }
}
