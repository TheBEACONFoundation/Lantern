import AppKit

/// Development aid: renders a contact sheet of emblem states to a PNG so the
/// visuals can be checked without babysitting a live window.
/// Invoked via `Lantern --export-preview <file.png>`.
enum PreviewExporter {

    private struct Cell {
        var label: String
        var state: LanternRenderer.State
    }

    static func run(to path: String) {
        let tile: CGFloat = 200
        let labelH: CGFloat = 26
        let cells = sheet()
        let cols = 5
        let rows = (cells.count + cols - 1) / cols
        let width = tile * CGFloat(cols)
        let height = (tile + labelH) * CGFloat(rows)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep)
        else { exit(1) }
        rep.size = CGSize(width: width, height: height)

        let previous = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previous }
        NSGraphicsContext.current = gc
        let ctx = gc.cgContext
        ctx.scaleBy(x: 2, y: 2)

        // Mid-grey backdrop: checks the emblem reads on a real wallpaper.
        ctx.setFillColor(NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (i, cell) in cells.enumerated() {
            let col = i % cols, row = i / cols
            let originY = height - CGFloat(row + 1) * (tile + labelH)
            let rect = CGRect(x: CGFloat(col) * tile, y: originY + labelH,
                              width: tile, height: tile)
            LanternRenderer.draw(in: ctx,
                                 rect: LanternGlyph.canvas(center: CGPoint(x: rect.midX, y: rect.midY),
                                                           emblemDiameter: tile * 0.83),
                                 state: cell.state)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.75),
            ]
            let str = NSAttributedString(string: cell.label, attributes: attrs)
            let s = str.size()
            str.draw(at: CGPoint(x: CGFloat(col) * tile + (tile - s.width) / 2,
                                 y: originY + (labelH - s.height) / 2))
        }

        gc.flushGraphics()
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private static func sheet() -> [Cell] {
        var cells: [Cell] = []
        for level in [0.0, 0.08, 0.17, 0.45, 0.78] {
            cells.append(Cell(label: String(format: "%.0f%% idle", level * 100),
                              state: .init(level: level, charging: false,
                                           pluggedIn: false, time: 1.0)))
        }
        cells.append(Cell(label: "100% idle",
                          state: .init(level: 1.0, charging: false, pluggedIn: false, time: 1.0)))
        cells.append(Cell(label: "100% plugged",
                          state: .init(level: 1.0, charging: false, pluggedIn: true, time: 1.0)))
        for t in [0.15, 0.55, 1.05] {
            cells.append(Cell(label: String(format: "charging t=%.2f", t),
                              state: .init(level: 0.42, charging: true,
                                           pluggedIn: true, time: t)))
        }
        for t in [1.6, 2.0] {
            cells.append(Cell(label: String(format: "charging t=%.2f", t),
                              state: .init(level: 0.42, charging: true,
                                           pluggedIn: true, time: t)))
        }
        cells.append(Cell(label: "charge 92%",
                          state: .init(level: 0.92, charging: true, pluggedIn: true, time: 0.8)))
        cells.append(Cell(label: "charge 6%",
                          state: .init(level: 0.06, charging: true, pluggedIn: true, time: 0.8)))
        cells.append(Cell(label: "plug-in flare",
                          state: .init(level: 0.42, charging: true, pluggedIn: true,
                                       time: 0.3, glow: 2.1)))
        // Sealed: plugged in, but the oath hasn't been spoken.
        for t in [0.3, 1.5] {
            cells.append(Cell(label: String(format: "sealed t=%.1f", t),
                              state: .init(level: 0.42, charging: true, pluggedIn: true,
                                           time: t, sealed: true)))
        }
        // The oath landing.
        for f in [0.08, 0.3, 0.62] {
            cells.append(Cell(label: String(format: "oath flare %.0f%%", f * 100),
                              state: .init(level: 0.42, charging: true, pluggedIn: true,
                                           time: 0.5,
                                           glow: 1.0 + 2.0 * pow(1 - f, 3),
                                           sealed: false, flare: f)))
        }
        return cells
    }
}
