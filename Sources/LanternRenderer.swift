import Accelerate
import AppKit

/// Draws the lantern emblem as a battery gauge: the emblem is the vessel and
/// the charge level fills it from the bottom like luminous fluid.
enum LanternRenderer {

    struct State {
        var level: Double          // 0...1
        var charging: Bool
        var pluggedIn: Bool
        var time: CFTimeInterval
        var glow: Double = 1.0     // global bloom multiplier
        var sealed: Bool = false   // charging withheld pending the oath
        var flare: Double = 0      // 0...1 progress of the oath shockwave
        /// The corps whose oath was spoken, overriding the charge's own.
        var sworn: LanternGlyph.Emblem?
    }

    /// Fixed spark seeds so the motes keep their identity frame to frame.
    private static let sparks: [(x: CGFloat, speed: CGFloat, phase: CGFloat, scale: CGFloat)] = {
        var rng = SystemRandomNumberGenerator()
        return (0..<20).map { i in
            let t = CGFloat(i) / 20
            return (x: CGFloat.random(in: -0.92...0.92, using: &rng),
                    speed: CGFloat.random(in: 0.28...0.62, using: &rng),
                    phase: t + CGFloat.random(in: -0.03...0.03, using: &rng),
                    scale: CGFloat.random(in: 0.65...1.35, using: &rng))
        }
    }()

    // MARK: - Entry point

    static func draw(in ctx: CGContext, rect: CGRect, state: State) {
        let palette = LanternGlyph.palette(level: state.level, charging: state.charging,
                                           sworn: state.sworn)
        let glyph = LanternGlyph.path(in: rect, emblem: palette.emblem)
        let emblem = LanternGlyph.emblemBounds(in: rect)
        let r = emblem.width / 2

        // Unlit vessel, always visible so the emblem reads even at 0%.
        ctx.saveGState()
        ctx.addPath(glyph)
        ctx.setFillColor(palette.ember.cgColor)
        ctx.fillPath(using: .winding)
        // Stroke the merged outline, not the raw path: the raw path's internal
        // boundaries would show as seams across the bars.
        ctx.addPath(LanternGlyph.outline(in: rect, emblem: palette.emblem))
        ctx.setStrokeColor(palette.deep.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(max(0.75, r * 0.012))
        ctx.strokePath()
        ctx.restoreGState()

        // Unlit core, so the hub never reads as an empty hole. Skipped at the
        // sizes where the emblem falls back to its simplified figure.
        if !LanternGlyph.isSimplified(in: rect) {
            let core = LanternGlyph.hubCore(in: rect, emblem: palette.emblem)
            drawCore(ctx, center: core.center, radius: core.radius,
                     color: palette.deep, alpha: 0.5, time: 0, pulse: false)
        }

        // Lit portion is composited off-screen, then drawn over its glow. The
        // layer only covers the emblem, not the whole canvas: the padding around
        // it is always empty, and compositing it would cost three times as much.
        let local = CGRect(origin: .zero, size: rect.size)
        let litRect = LanternGlyph.emblemBounds(in: local).insetBy(dx: -r * 0.03,
                                                                  dy: -r * 0.03)
        guard state.level > 0.001 || state.charging,
              let layer = CGLayer(ctx, size: litRect.size, auxiliaryInfo: nil),
              let lit = layer.context else { return }

        lit.translateBy(x: -litRect.minX, y: -litRect.minY)
        drawLit(in: lit, bounds: local, state: state, palette: palette)

        let bloom = CGFloat(max(0, min(1.4, state.glow)))
        if bloom > 0.001,
           let glow = bloomImage(rect: rect, r: r, palette: palette, bloom: bloom,
                                 silhouette: { c, local in
                                     drawLit(in: c, bounds: local, state: state, palette: palette)
                                 }) {
            ctx.saveGState()
            ctx.interpolationQuality = .high
            ctx.draw(glow, in: rect)
            ctx.restoreGState()
        }

        // Composited once. The translucent effects below carry the alpha they
        // used to reach after three source-over passes — a' = 1 - (1 - a)^3 —
        // which looks the same and costs two full-canvas composites less.
        ctx.draw(layer, in: litRect.offsetBy(dx: rect.minX, dy: rect.minY))

        if state.flare > 0 {
            drawShockwave(ctx, center: CGPoint(x: emblem.midX, y: emblem.midY),
                          r: r, palette: palette, progress: CGFloat(state.flare))
        }
    }

    /// Expanding rings thrown off when the oath lands. Drawn outside the glyph
    /// clip so it can travel past the emblem.
    private static func drawShockwave(_ ctx: CGContext, center: CGPoint, r: CGFloat,
                                      palette: LanternGlyph.Palette, progress: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        for i in 0..<3 {
            let offset = CGFloat(i) * 0.16
            let p = progress - offset
            guard p > 0, p < 1 else { continue }
            let eased = 1 - pow(1 - p, 2.2)          // fast out, slow settle
            // The canvas reaches r / (1 - glowPadding) ≈ 1.67r from the centre;
            // the wave finishes well inside that so the window edge never cuts it.
            let radius = r * (0.55 + eased * 0.85)
            let alpha = pow(1 - p, 2.0) * 0.75
            ctx.setStrokeColor(palette.bright.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(r * 0.06 * (1 - eased * 0.45))
            ctx.addArc(center: center, radius: radius, startAngle: 0,
                       endAngle: 2 * .pi, clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Concentric rings engraved in the hub, echoing the core of the ring the
    /// emblem is modelled on.
    static func drawCore(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                                 color: NSColor, alpha: CGFloat,
                                 time: CFTimeInterval, pulse: Bool) {
        guard radius > 1, alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi,
                   clockwise: false)
        ctx.clip()
        ctx.setLineWidth(max(0.5, radius * 0.11))
        let rings = 4
        for i in 0..<rings {
            let f = CGFloat(i + 1) / CGFloat(rings + 1)
            var a = alpha * (1 - f * 0.3)
            // Charging sends a slow ripple outward through the rings.
            if pulse { a *= 0.7 + 0.45 * CGFloat(sin(time * 2.6 - Double(i) * 0.8)) }
            guard a > 0.001 else { continue }
            ctx.setStrokeColor(color.withAlphaComponent(min(1, a)).cgColor)
            ctx.addArc(center: center, radius: radius * f * 1.06, startAngle: 0,
                       endAngle: 2 * .pi, clockwise: false)
            ctx.strokePath()
        }
        ctx.setFillColor(color.withAlphaComponent(min(1, alpha)).cgColor)
        ctx.addArc(center: center, radius: radius * 0.11, startAngle: 0, endAngle: 2 * .pi,
                   clockwise: false)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Plugged in but withheld: a slow, dim pulse around the ring instead of
    /// the charging comet — visibly waiting for something.
    static func drawHeld(_ ctx: CGContext, center: CGPoint, r: CGFloat,
                                 palette: LanternGlyph.Palette, time: CFTimeInterval) {
        let radius = r * (1 + LanternGlyph.ringInner) / 2
        let width = r * (1 - LanternGlyph.ringInner)
        let breath = 0.169 + 0.173 * CGFloat(sin(time * 1.15) * 0.5 + 0.5)
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.setStrokeColor(palette.bright.withAlphaComponent(breath).cgColor)
        ctx.setLineWidth(width)
        ctx.addArc(center: center, radius: radius, startAngle: 0,
                   endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Bloom

    /// Blur spreads, as Gaussian sigma in units of the emblem radius.
    private static let wideSpread: CGFloat = 0.10
    private static let tightSpread: CGFloat = 0.035
    /// Longest side of the glow buffer. The glow is soft enough that it loses
    /// nothing at this resolution; going higher costs frame time for no gain.
    private static let bloomResolution: CGFloat = 240

    /// Reused between frames; the renderer only ever runs on the main thread.
    private final class BloomBuffers {
        var width = 0, height = 0
        var rgba: [UInt8] = [], alpha: [UInt8] = [], temp: [UInt8] = []
        var wide: [UInt8] = [], tight: [UInt8] = []

        func fit(_ w: Int, _ h: Int) {
            guard w != width || h != height else { return }
            width = w; height = h
            rgba = [UInt8](repeating: 0, count: w * h * 4)
            alpha = [UInt8](repeating: 0, count: w * h)
            temp = alpha; wide = alpha; tight = alpha
        }
    }
    private static let bloomBuffers = BloomBuffers()

    /// The glow, computed as pixels: the lit silhouette is rendered small, its
    /// alpha blurred with vImage, and the result tinted.
    ///
    /// This deliberately avoids `CGContext.setShadow`. In a live window's
    /// layer-backed context the shadow is only generated inside the bounds of
    /// what the lit layer drew — the emblem's bounding box — so the glow
    /// stopped dead along a square. Offscreen bitmap contexts don't do that,
    /// which is how it slipped past rendering checks.
    static func bloomImage(rect: CGRect, r: CGFloat, palette: LanternGlyph.Palette,
                           bloom: CGFloat,
                           silhouette: (CGContext, CGRect) -> Void) -> CGImage? {
        let scale = min(1, bloomResolution / max(rect.width, rect.height))
        let w = max(8, Int((rect.width * scale).rounded(.up)))
        let h = max(8, Int((rect.height * scale).rounded(.up)))
        let n = w * h
        let b = bloomBuffers
        b.fit(w, h)
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue

        // 1. Lit silhouette at glow resolution; keep only its alpha.
        let drew: Bool = b.rgba.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: w, height: h,
                                    bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: srgb, bitmapInfo: info) else { return false }
            c.clear(CGRect(x: 0, y: 0, width: w, height: h))
            c.scaleBy(x: CGFloat(w) / rect.width, y: CGFloat(h) / rect.height)
            silhouette(c, CGRect(origin: .zero, size: rect.size))
            return true
        }
        guard drew else { return nil }
        for i in 0..<n { b.alpha[i] = b.rgba[i * 4 + 3] }

        // 2. Two blurs of that alpha: a wide soft halo and a tight rim.
        let pxPerPoint = CGFloat(w) / rect.width
        boxBlur3(&b.alpha, into: &b.wide, temp: &b.temp, w: w, h: h,
                 sigma: wideSpread * r * pxPerPoint)
        boxBlur3(&b.alpha, into: &b.tight, temp: &b.temp, w: w, h: h,
                 sigma: tightSpread * r * pxPerPoint)

        // 3. Tint and combine, as two glow layers composited source-over.
        let color = palette.bright.usingColorSpace(.sRGB) ?? palette.bright
        let cr = Float(color.redComponent), cg = Float(color.greenComponent)
        let cb = Float(color.blueComponent)
        let wideAlpha = Float(0.42 * bloom) / 255, tightAlpha = Float(0.55 * bloom) / 255
        for i in 0..<n {
            let a1 = Float(b.wide[i]) * wideAlpha
            let a2 = Float(b.tight[i]) * tightAlpha
            let a = min(1, a1 + a2 * (1 - a1))
            let o = i * 4
            b.rgba[o] = UInt8(cr * a * 255 + 0.5)
            b.rgba[o + 1] = UInt8(cg * a * 255 + 0.5)
            b.rgba[o + 2] = UInt8(cb * a * 255 + 0.5)
            b.rgba[o + 3] = UInt8(a * 255 + 0.5)
        }

        guard let provider = CGDataProvider(data: Data(b.rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: srgb,
                       bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Three box passes approximate a Gaussian of the given sigma (in pixels).
    private static func boxBlur3(_ src: inout [UInt8], into dst: inout [UInt8],
                                 temp: inout [UInt8], w: Int, h: Int, sigma: CGFloat) {
        // Three passes of width k give sigma ≈ k / 2; vImage needs k odd.
        var k = max(1, Int((sigma * 2).rounded()))
        if k % 2 == 0 { k += 1 }
        let kernel = UInt32(k)
        let flags = vImage_Flags(kvImageEdgeExtend)
        src.withUnsafeMutableBytes { s in
            dst.withUnsafeMutableBytes { d in
                temp.withUnsafeMutableBytes { t in
                    var bs = vImage_Buffer(data: s.baseAddress, height: vImagePixelCount(h),
                                           width: vImagePixelCount(w), rowBytes: w)
                    var bd = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(h),
                                           width: vImagePixelCount(w), rowBytes: w)
                    var bt = vImage_Buffer(data: t.baseAddress, height: vImagePixelCount(h),
                                           width: vImagePixelCount(w), rowBytes: w)
                    vImageBoxConvolve_Planar8(&bs, &bd, nil, 0, 0, kernel, kernel, 0, flags)
                    vImageBoxConvolve_Planar8(&bd, &bt, nil, 0, 0, kernel, kernel, 0, flags)
                    vImageBoxConvolve_Planar8(&bt, &bd, nil, 0, 0, kernel, kernel, 0, flags)
                }
            }
        }
    }

    // MARK: - Lit silhouette

    private static func drawLit(in ctx: CGContext, bounds: CGRect,
                                state: State, palette: LanternGlyph.Palette) {
        let glyph = LanternGlyph.path(in: bounds, emblem: palette.emblem)
        let emblem = LanternGlyph.emblemBounds(in: bounds)
        let r = emblem.width / 2
        let c = CGPoint(x: emblem.midX, y: emblem.midY)
        let t = state.time

        // The core sits in the hub's bore, which is a hole in the glyph — so it
        // has to be drawn before the clip, not inside it.
        let level0 = CGFloat(max(0, min(1, state.level)))
        if !LanternGlyph.isSimplified(in: bounds) {
            let core = LanternGlyph.hubCore(in: bounds, emblem: palette.emblem)
            drawCore(ctx, center: core.center, radius: core.radius,
                     color: palette.bright,
                     alpha: min(1, 0.28 + 0.72 * level0),
                     time: t, pulse: state.charging && !state.sealed)
        }

        ctx.saveGState()
        ctx.addPath(glyph)
        ctx.clip(using: .winding)

        let level = CGFloat(max(0, min(1, state.level)))
        let full = level >= 0.995
        // A charging cell breathes a little above its true level.
        let breath = (state.charging && !state.sealed) ? CGFloat(sin(t * 1.9)) * 0.012 : 0
        let surfaceY = emblem.minY + (level + breath) * emblem.height
        let amp = full ? 0 : r * (state.charging && !state.sealed ? 0.028 : 0.016)

        if level > 0.001 {
            let wave = surfacePath(bounds: bounds, emblem: emblem,
                                   surfaceY: surfaceY, amp: amp, time: t)

            ctx.saveGState()
            ctx.addPath(wave)
            ctx.clip()
            drawVerticalGradient(ctx,
                                 from: palette.deep.withAlphaComponent(0.92),
                                 to: palette.bright,
                                 y0: emblem.minY - r * 0.1, y1: surfaceY + r * 0.02,
                                 rect: bounds)
            // Light pools toward the surface.
            drawVerticalGradient(ctx,
                                 from: NSColor.white.withAlphaComponent(0),
                                 to: NSColor.white.withAlphaComponent(full ? 0.449 : 0.657),
                                 y0: surfaceY - r * 0.55, y1: surfaceY,
                                 rect: bounds)
            ctx.restoreGState()

            if !full {
                // Crisp meniscus along the surface.
                ctx.saveGState()
                ctx.addPath(crestPath(bounds: bounds, emblem: emblem,
                                      surfaceY: surfaceY, amp: amp, time: t))
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.973).cgColor)
                ctx.setLineWidth(max(0.7, r * 0.022))
                ctx.setLineCap(.round)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }

        if state.charging && !state.sealed {
            drawSurge(ctx, emblem: emblem, r: r, palette: palette, time: t)
            drawSparks(ctx, emblem: emblem, r: r, palette: palette, time: t)
            drawRingSweep(ctx, center: c, r: r, palette: palette, time: t, comet: true)
        } else if state.sealed && state.pluggedIn {
            drawHeld(ctx, center: c, r: r, palette: palette, time: t)
        } else if state.pluggedIn && full {
            drawRingSweep(ctx, center: c, r: r, palette: palette, time: t, comet: false)
        }

        // Glint in the hub bore, which is not always the emblem's centre — and
        // which the Black Lantern figure doesn't have at all.
        let bore = LanternGlyph.hubCore(in: bounds, emblem: palette.emblem)
        if bore.radius > 0, level > 0.5 || (state.charging && !state.sealed) {
            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            let pulse = 0.271 + 0.136 * CGFloat(sin(t * (state.charging && !state.sealed ? 3.4 : 1.2)) * 0.5 + 0.5)
            drawRadialGlow(ctx, center: bore.center, radius: r * 0.50,
                           color: palette.bright.withAlphaComponent(pulse))
            ctx.restoreGState()
        }

        ctx.restoreGState()
    }

    // MARK: - Surface geometry

    private static func waveY(_ x: CGFloat, surfaceY: CGFloat, amp: CGFloat,
                              r: CGFloat, time: CFTimeInterval) -> CGFloat {
        guard amp > 0 else { return surfaceY }
        let k1 = 3.1 / r, k2 = 5.7 / r
        return surfaceY
            + sin(x * k1 + CGFloat(time) * 1.5) * amp
            + sin(x * k2 - CGFloat(time) * 2.3) * amp * 0.55
    }

    private static func surfacePath(bounds: CGRect, emblem: CGRect,
                                    surfaceY: CGFloat, amp: CGFloat,
                                    time: CFTimeInterval) -> CGPath {
        let r = emblem.width / 2
        let p = CGMutablePath()
        let x0 = bounds.minX - 2, x1 = bounds.maxX + 2
        p.move(to: CGPoint(x: x0, y: bounds.minY - 2))
        p.addLine(to: CGPoint(x: x0, y: waveY(x0 - emblem.midX, surfaceY: surfaceY, amp: amp, r: r, time: time)))
        var x = x0
        while x <= x1 {
            p.addLine(to: CGPoint(x: x, y: waveY(x - emblem.midX, surfaceY: surfaceY, amp: amp, r: r, time: time)))
            x += 2
        }
        p.addLine(to: CGPoint(x: x1, y: bounds.minY - 2))
        p.closeSubpath()
        return p
    }

    private static func crestPath(bounds: CGRect, emblem: CGRect,
                                  surfaceY: CGFloat, amp: CGFloat,
                                  time: CFTimeInterval) -> CGPath {
        let r = emblem.width / 2
        let p = CGMutablePath()
        var x = bounds.minX - 2
        p.move(to: CGPoint(x: x, y: waveY(x - emblem.midX, surfaceY: surfaceY, amp: amp, r: r, time: time)))
        while x <= bounds.maxX + 2 {
            p.addLine(to: CGPoint(x: x, y: waveY(x - emblem.midX, surfaceY: surfaceY, amp: amp, r: r, time: time)))
            x += 2
        }
        return p
    }

    // MARK: - Charging effects

    /// A band of light that climbs the emblem on a loop.
    private static func drawSurge(_ ctx: CGContext, emblem: CGRect, r: CGFloat,
                                  palette: LanternGlyph.Palette, time: CFTimeInterval) {
        let period: CFTimeInterval = 2.1
        let progress = CGFloat((time.truncatingRemainder(dividingBy: period)) / period)
        // Ease so the band accelerates away at the top.
        let eased = progress * progress * (3 - 2 * progress)
        let y = emblem.minY - r * 0.3 + eased * (emblem.height + r * 0.6)
        let height = r * 0.62
        let fade = CGFloat(1 - pow(Double(progress), 2.4))

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.clip(to: CGRect(x: emblem.minX - r, y: y - height / 2,
                            width: emblem.width + r * 2, height: height))
        drawVerticalGradient(ctx,
                             from: palette.bright.withAlphaComponent(0),
                             to: palette.bright.withAlphaComponent(0.713 * fade),
                             y0: y - height / 2, y1: y,
                             rect: CGRect(x: emblem.minX - r, y: y - height / 2,
                                          width: emblem.width + r * 2, height: height / 2))
        drawVerticalGradient(ctx,
                             from: palette.bright.withAlphaComponent(0.713 * fade),
                             to: palette.bright.withAlphaComponent(0),
                             y0: y, y1: y + height / 2,
                             rect: CGRect(x: emblem.minX - r, y: y,
                                          width: emblem.width + r * 2, height: height / 2))
        ctx.restoreGState()
    }

    /// Motes of charge drifting upward through the emblem. Drawn as soft
    /// vertically-stretched blobs — hard-edged rectangles read as scratches.
    private static func drawSparks(_ ctx: CGContext, emblem: CGRect, r: CGFloat,
                                   palette: LanternGlyph.Palette, time: CFTimeInterval) {
        let core = palette.bright.blended(withFraction: 0.55, of: .white) ?? .white
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        for s in sparks {
            var f = (CGFloat(time) * s.speed + s.phase).truncatingRemainder(dividingBy: 1)
            if f < 0 { f += 1 }
            let y = emblem.minY + f * emblem.height
            // Sway so they don't read as a rigid column.
            let sway = sin(CGFloat(time) * 1.3 + s.phase * 11) * r * 0.035
            let x = emblem.midX + s.x * r + sway
            let alpha = 0.805 * sin(CGFloat.pi * f)   // fade in at the base, out at the top
            let radius = r * 0.045 * s.scale

            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.scaleBy(x: 1, y: 2.3)   // stretch into a rising streak
            drawRadialGlow(ctx, center: .zero, radius: radius,
                           color: core.withAlphaComponent(alpha))
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    /// Light travelling around the outer ring — a comet while charging, a slow
    /// shimmer when topped up.
    ///
    /// Built from overlapping soft blobs rather than stroked arc segments:
    /// discrete segments leave visible seams where their antialiased butt ends
    /// meet, which additive blending only makes worse.
    static func drawRingSweep(_ ctx: CGContext, center: CGPoint, r: CGFloat,
                                      palette: LanternGlyph.Palette,
                                      time: CFTimeInterval, comet: Bool) {
        let radius = r * (1 + LanternGlyph.ringInner) / 2
        let width = r * (1 - LanternGlyph.ringInner)
        let head = CGFloat(time) * (comet ? 2.2 : 0.55)
        let tail: CGFloat = comet ? 1.5 : 2.8
        let blobs = 64
        let tint = palette.bright.blended(withFraction: 0.5, of: .white) ?? palette.bright
        let peak: CGFloat = comet ? 0.657 : 0.319

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        for i in 0..<blobs {
            let f = CGFloat(i) / CGFloat(blobs - 1)
            let angle = head - tail * f
            let alpha = pow(1 - f, 2.0) * peak
            guard alpha > 0.002 else { continue }
            let p = CGPoint(x: center.x + cos(angle) * radius,
                            y: center.y + sin(angle) * radius)
            drawRadialGlow(ctx, center: p, radius: width * 1.15,
                           color: tint.withAlphaComponent(alpha))
        }
        if comet {
            // A hotter core right at the head.
            let p = CGPoint(x: center.x + cos(head) * radius,
                            y: center.y + sin(head) * radius)
            drawRadialGlow(ctx, center: p, radius: width * 0.85,
                           color: NSColor.white.withAlphaComponent(0.834))
        }
        ctx.restoreGState()
    }

    // MARK: - Gradient helpers

    static func drawVerticalGradient(_ ctx: CGContext, from c0: NSColor, to c1: NSColor,
                                             y0: CGFloat, y1: CGFloat, rect: CGRect) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [c0.cgColor, c1.cgColor] as CFArray,
                                 locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: rect.midX, y: y0),
                               end: CGPoint(x: rect.midX, y: y1),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    static func drawRadialGlow(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                                       color: NSColor) {
        guard radius > 0, let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [color.cgColor,
                                          color.withAlphaComponent(0).cgColor] as CFArray,
                                 locations: [0, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: radius, options: [])
    }
}
