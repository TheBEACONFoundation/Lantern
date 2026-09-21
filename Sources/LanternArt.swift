import AppKit

/// Static artwork for the desktop widget's layer tree.
///
/// Each piece is drawn once — per size, palette and charge level — with the
/// same Core Graphics helpers `LanternRenderer` uses, so the look matches. Core
/// Animation then moves, rotates and fades these images in the system
/// compositor, and the app does no drawing at all between state changes.
///
/// All geometry is in canvas points: (0, 0) is the canvas's bottom-left and the
/// emblem is centred in it, exactly as `LanternRenderer` lays it out.
enum LanternArt {

    /// Draws into a fresh bitmap of `size` points at `scale` pixels per point.
    static func image(_ size: CGSize, scale: CGFloat,
                      _ draw: (CGContext) -> Void) -> CGImage? {
        let w = max(1, Int((size.width * scale).rounded(.up)))
        let h = max(1, Int((size.height * scale).rounded(.up)))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        draw(ctx)
        return ctx.makeImage()
    }

    private static func geometry(_ canvas: CGSize) -> (local: CGRect, emblem: CGRect, r: CGFloat) {
        let local = CGRect(origin: .zero, size: canvas)
        let emblem = LanternGlyph.emblemBounds(in: local)
        return (local, emblem, emblem.width / 2)
    }

    // MARK: - Emblem

    /// The unlit vessel: ember fill, merged outline, and the unlit core.
    static func ember(canvas: CGSize, scale: CGFloat,
                      palette: LanternGlyph.Palette) -> CGImage? {
        image(canvas, scale: scale) { ctx in
            let (local, _, r) = geometry(canvas)
            ctx.addPath(LanternGlyph.path(in: local, emblem: palette.emblem))
            ctx.setFillColor(palette.ember.cgColor)
            ctx.fillPath(using: .winding)
            ctx.addPath(LanternGlyph.outline(in: local, emblem: palette.emblem))
            ctx.setStrokeColor(palette.deep.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(max(0.75, r * 0.012))
            ctx.strokePath()
            let core = LanternGlyph.hubCore(in: local, emblem: palette.emblem)
            LanternRenderer.drawCore(ctx, center: core.center, radius: core.radius,
                                     color: palette.deep, alpha: 0.5, time: 0, pulse: false)
        }
    }

    /// The emblem's shape in opaque white — a mask that clips the lit
    /// content and the effects to the emblem.
    static func glyphMask(canvas: CGSize, scale: CGFloat,
                          emblem: LanternGlyph.Emblem) -> CGImage? {
        image(canvas, scale: scale) { ctx in
            ctx.addPath(LanternGlyph.path(in: CGRect(origin: .zero, size: canvas),
                                          emblem: emblem))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath(using: .winding)
        }
    }

    /// The lit engraved core. It sits in the hub's bore — a hole in the glyph —
    /// so it lives outside the emblem mask.
    static func core(canvas: CGSize, scale: CGFloat, level: CGFloat,
                     palette: LanternGlyph.Palette) -> CGImage? {
        image(canvas, scale: scale) { ctx in
            let core = LanternGlyph.hubCore(in: CGRect(origin: .zero, size: canvas),
                                            emblem: palette.emblem)
            LanternRenderer.drawCore(ctx, center: core.center, radius: core.radius,
                                     color: palette.bright,
                                     alpha: min(1, 0.28 + 0.72 * level), time: 0, pulse: false)
        }
    }

    /// A soft bloom in the bore, flickered while charging as motes are swallowed.
    static func coreFlash(canvas: CGSize, scale: CGFloat,
                          palette: LanternGlyph.Palette) -> CGImage? {
        image(canvas, scale: scale) { ctx in
            let core = LanternGlyph.hubCore(in: CGRect(origin: .zero, size: canvas),
                                            emblem: palette.emblem)
            let hot = palette.bright.blended(withFraction: 0.35, of: .white) ?? palette.bright
            LanternRenderer.drawRadialGlow(ctx, center: core.center, radius: core.radius * 1.25,
                                           color: hot.withAlphaComponent(0.9))
        }
    }

    /// The glow of the lit charge and core, at the renderer's maximum bloom.
    /// The layer's opacity scales it down to the resting intensity, which
    /// leaves headroom to flare it on plug-in and on the oath.
    static let glowCeiling: CGFloat = 1.4

    static func glow(canvas: CGSize, scale: CGFloat, level: CGFloat,
                     palette: LanternGlyph.Palette) -> CGImage? {
        let (local, emblem, r) = geometry(canvas)
        guard level > 0.001 else { return nil }
        // Bloom works from alpha only, so the silhouette can be flat white.
        let blurred = LanternRenderer.bloomImage(
            rect: local, r: r, palette: palette, bloom: glowCeiling,
            silhouette: { c, b in
                let surfaceY = emblem.minY + level * emblem.height
                c.saveGState()
                c.addPath(LanternGlyph.path(in: b, emblem: palette.emblem))
                c.clip(using: .winding)
                c.setFillColor(NSColor.white.cgColor)
                c.fill(CGRect(x: 0, y: 0, width: b.width, height: surfaceY))
                c.restoreGState()
                let core = LanternGlyph.hubCore(in: b, emblem: palette.emblem)
                LanternRenderer.drawCore(c, center: core.center, radius: core.radius,
                                         color: .white, alpha: min(1, 0.28 + 0.72 * level),
                                         time: 0, pulse: false)
            })
        guard let blurred else { return nil }
        // Upsample once here, rather than having the compositor stretch a
        // 240px bitmap across a Retina canvas every frame.
        return image(canvas, scale: scale) { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(blurred, in: local)
        }
    }

    // MARK: - Surface

    /// One period of the liquid surface: two harmonics, so it reads as liquid
    /// rather than a plain sine, and exactly periodic so it can slide forever.
    static func surfaceY(_ x: CGFloat, base: CGFloat, amp: CGFloat, period: CGFloat) -> CGFloat {
        let k = 2 * CGFloat.pi / period
        return base + amp * (sin(k * x) + 0.55 * sin(2 * k * x + 0.9))
    }

    /// The lit charge as a horizontally tileable strip: the charge's vertical
    /// gradient below a moving surface, with the bright meniscus along it.
    ///
    /// The gradient varies only with height, so sliding the strip sideways
    /// changes nothing but the surface — which is exactly the liquid motion.
    /// Baking the surface in, rather than masking a fill with a moving wave,
    /// saves the compositor an offscreen pass every frame.
    ///
    /// Strip coordinates are canvas coordinates lifted by `margin`, so the
    /// strip can breathe up and down without exposing its bottom edge.
    static func litStrip(canvas: CGSize, width: CGFloat, margin: CGFloat, scale: CGFloat,
                         level: CGFloat, palette: LanternGlyph.Palette,
                         amp: CGFloat, period: CGFloat) -> CGImage? {
        let size = CGSize(width: width, height: canvas.height + margin * 2)
        return image(size, scale: scale) { ctx in
            let (_, emblem, r) = geometry(canvas)
            let full = level >= 0.995
            ctx.translateBy(x: 0, y: margin)
            let surface = full ? canvas.height + margin : emblem.minY + level * emblem.height
            let area = CGRect(x: 0, y: -margin, width: width, height: canvas.height + margin * 2)

            let edge = CGMutablePath()
            var x: CGFloat = -2
            edge.move(to: CGPoint(x: x, y: surfaceY(x, base: surface, amp: amp, period: period)))
            while x <= width + 2 {
                x += 1
                edge.addLine(to: CGPoint(x: x, y: surfaceY(x, base: surface, amp: amp, period: period)))
            }
            guard let below = edge.mutableCopy() else { return }
            below.addLine(to: CGPoint(x: width + 2, y: -margin - 2))
            below.addLine(to: CGPoint(x: -2, y: -margin - 2))
            below.closeSubpath()

            ctx.saveGState()
            ctx.addPath(below)
            ctx.clip()
            LanternRenderer.drawVerticalGradient(
                ctx, from: palette.deep.withAlphaComponent(0.92), to: palette.bright,
                y0: emblem.minY - r * 0.1, y1: surface + r * 0.02, rect: area)
            // Light pools toward the surface.
            LanternRenderer.drawVerticalGradient(
                ctx, from: NSColor.white.withAlphaComponent(0),
                to: NSColor.white.withAlphaComponent(full ? 0.449 : 0.657),
                y0: surface - r * 0.55, y1: surface, rect: area)
            ctx.restoreGState()

            if !full {
                // The meniscus.
                ctx.addPath(edge)
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.973).cgColor)
                ctx.setLineWidth(max(0.7, r * 0.022))
                ctx.setLineCap(.round)
                ctx.strokePath()
            }
        }
    }

    // MARK: - Effects

    /// Light around the outer ring with its head at angle 0: a comet while
    /// charging, a long slow shimmer when topped up. Rotated by its layer.
    static func sweep(canvas: CGSize, scale: CGFloat, palette: LanternGlyph.Palette,
                      comet: Bool) -> CGImage? {
        image(canvas, scale: scale) { ctx in
            let (_, emblem, r) = geometry(canvas)
            LanternRenderer.drawRingSweep(ctx, center: CGPoint(x: emblem.midX, y: emblem.midY),
                                          r: r, palette: palette, time: 0, comet: comet)
        }
    }

    /// The comet's glow, spilling past the ring. Unmasked, rotated in step.
    static func sweepHalo(canvas: CGSize, scale: CGFloat,
                          palette: LanternGlyph.Palette) -> CGImage? {
        let (local, emblem, r) = geometry(canvas)
        guard let blurred = LanternRenderer.bloomImage(
            rect: local, r: r, palette: palette, bloom: 1.0,
            silhouette: { c, _ in
                LanternRenderer.drawRingSweep(c, center: CGPoint(x: emblem.midX, y: emblem.midY),
                                              r: r, palette: palette, time: 0, comet: true)
            }) else { return nil }
        return image(canvas, scale: scale) { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(blurred, in: local)
        }
    }

    /// The ring at full strength; its layer breathes it while the gate is sealed.
    static func heldRing(canvas: CGSize, scale: CGFloat,
                         palette: LanternGlyph.Palette) -> CGImage? {
        image(canvas, scale: scale) { ctx in
            let (_, emblem, r) = geometry(canvas)
            ctx.setStrokeColor(palette.bright.cgColor)
            ctx.setLineWidth(r * (1 - LanternGlyph.ringInner))
            ctx.addArc(center: CGPoint(x: emblem.midX, y: emblem.midY),
                       radius: r * (1 + LanternGlyph.ringInner) / 2,
                       startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.strokePath()
        }
    }

    /// The hub's glint at full strength; its layer pulses it. It follows the
    /// bore, which the Red Lantern figure puts below the emblem's centre.
    static func glint(canvas: CGSize, scale: CGFloat,
                      palette: LanternGlyph.Palette) -> CGImage? {
        image(canvas, scale: scale) { ctx in
            let (local, _, r) = geometry(canvas)
            let bore = LanternGlyph.hubCore(in: local, emblem: palette.emblem)
            guard bore.radius > 0 else { return }   // no bore, nothing to glint in
            LanternRenderer.drawRadialGlow(ctx, center: bore.center,
                                           radius: r * 0.5, color: palette.bright)
        }
    }

    // MARK: - Particles

    /// A soft glowing mote, white so emitter cells can tint it.
    static let dot: CGImage? = image(CGSize(width: 32, height: 32), scale: 1) { ctx in
        let mid = CGPoint(x: 16, y: 16)
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [NSColor.white.cgColor,
                                          NSColor.white.withAlphaComponent(0.55).cgColor,
                                          NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                 locations: [0, 0.28, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: mid, startRadius: 0,
                               endCenter: mid, endRadius: 16, options: [])
    }

    /// A mote stretched along +y, for particles aimed that way: a streak reads
    /// as streaming energy where a dot reads as floating dust.
    static let streak: CGImage? = image(CGSize(width: 16, height: 48), scale: 1) { ctx in
        ctx.translateBy(x: 8, y: 24)
        ctx.scaleBy(x: 1, y: 3)
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [NSColor.white.cgColor,
                                          NSColor.white.withAlphaComponent(0.5).cgColor,
                                          NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                 locations: [0, 0.3, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: 8, options: [])
    }
}
