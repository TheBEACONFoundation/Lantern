import AppKit

enum IconExporter {
    static func run(into directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for size in [16, 32, 64, 128, 256, 512, 1024] {
            guard let data = png(side: CGFloat(size)) else {
                FileHandle.standardError.write(Data("failed to render \(size)px icon\n".utf8))
                exit(1)
            }
            try? data.write(to: dir.appendingPathComponent("icon_\(size).png"))
        }
    }

    private static func png(side: CGFloat) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(side), pixelsHigh: Int(side),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }

        let previous = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previous }
        guard let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = gc
        let ctx = gc.cgContext

        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        // Standard macOS icon proportions: a squircle inset from the canvas.
        let plate = canvas.insetBy(dx: side * 0.085, dy: side * 0.085)
        let squircle = CGPath(roundedRect: plate,
                              cornerWidth: plate.width * 0.2237,
                              cornerHeight: plate.height * 0.2237,
                              transform: nil)

        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor(srgbRed: 0.05, green: 0.11, blue: 0.07, alpha: 1).cgColor,
                                       NSColor(srgbRed: 0.01, green: 0.03, blue: 0.02, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: plate.midX, y: plate.maxY),
                                   end: CGPoint(x: plate.midX, y: plate.minY), options: [])
        }
        let state = LanternRenderer.State(level: 0.86, charging: false, pluggedIn: false,
                                          time: 0.4, glow: 1.15)
        let inner = plate.insetBy(dx: plate.width * 0.10, dy: plate.height * 0.10)
        LanternRenderer.draw(in: ctx,
                             rect: LanternGlyph.canvas(center: CGPoint(x: plate.midX, y: plate.midY),
                                                       emblemDiameter: inner.width * 0.83),
                             state: state)
        ctx.restoreGState()

        gc.flushGraphics()
        return rep.representation(using: .png, properties: [:])
    }
}
