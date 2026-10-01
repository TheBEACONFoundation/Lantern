import AppKit
import QuartzCore

/// The desktop emblem, built as a Core Animation layer tree.
///
/// Every static piece — the unlit vessel, the lit charge, the glow, the ring
/// sweep — is drawn once by `LanternArt` with the renderer's own Core Graphics
/// code. Everything that moves (the liquid surface, the sweep, the surge, the
/// particles, the flares) is a Core Animation animation or emitter, run by the
/// system compositor on the GPU. So the app only does work when something
/// actually changes — the percentage, the palette, the charging state — rather
/// than redrawing a Retina-sized bitmap on the CPU up to 60 times a second.
final class LanternView: NSView {

    var info = BatteryInfo() {
        didSet {
            if info.isCharging && !oldValue.isCharging { flareGlow(duration: 1.6) }
            update()
        }
    }

    var contextMenu: NSMenu?

    /// Charging withheld pending the oath: the charging effects give way to a
    /// slow "held back" pulse, and inbound motes stall short of the hub.
    var gateSealed = false {
        didSet { if gateSealed != oldValue { update() } }
    }

    /// The corps whose oath was spoken. It overrides the one the charge would
    /// choose, so the lantern dissolves into that corps and stays there until
    /// it is sealed again.
    var swornCorps: LanternGlyph.Emblem? {
        didSet { if swornCorps != oldValue { update() } }
    }

    /// The oath lands: a particle burst, and — unless the corps it swore to
    /// has just thrown its own — rings and a glow flare.
    ///
    /// The two collide otherwise. Both draw on the same layers under the same
    /// keys and this call comes second, so the generic three rings replaced
    /// whatever the arriving corps had thrown: the Indigo Tribe's three slow
    /// ones, the Star Sapphire's two on its heartbeats, the Black Lantern's
    /// bloom, which it *snuffs* rather than spikes. For the four corps an oath
    /// is the only way into, that was every single time.
    func triggerOathFlare() {
        guard !reduceMotion else { return }
        if CACurrentMediaTime() - lastFlourish > 0.25 {
            fireShockwave()
            flareGlow(duration: 2.4)
        }
        if Settings.shared.particleEffects { fireBurst() }
    }

    /// Percentage, particles or opacity changed in the menu. None of them touch
    /// the artwork, so this is cheap enough to call on every slider tick; a
    /// size change arrives through `setFrameSize` instead.
    func settingsDidChange() { update() }

    // MARK: - Layers

    private let emblemRoot = CALayer()        // the canvas, lifted for the caption
    private let emberLayer = CALayer()
    private let glowLayer = CALayer()
    private let sweepHaloLayer = CALayer()
    private let coreLayer = CALayer()
    private let coreFlashLayer = CALayer()
    private let litContainer = CALayer()      // masked to the emblem's shape
    private let glyphMaskLayer = CALayer()
    private let litStrip = CALayer()          // the charge and its surface, sliding
    private let surgeLayer = CAGradientLayer()
    private let sweepLayer = CALayer()
    private let heldLayer = CALayer()
    private let glintLayer = CALayer()
    private let emberEmitter = CAEmitterLayer()
    private let inflowRing = CALayer()
    private let inflowEmitters: [CAEmitterLayer] = (0..<LanternView.inflowCount).map { _ in CAEmitterLayer() }
    private static let inflowCount = 24
    private let burstEmitter = CAEmitterLayer()
    private let shockwaves: [CAShapeLayer] = (0..<3).map { _ in CAShapeLayer() }
    private let captionLayer = CALayer()

    private var hovering = false { didSet { update() } }
    private var tracking: NSTrackingArea?
    private let reduceMotionPreference: () -> Bool
    private var reduceMotion: Bool
    private var accessibilityObserver: NSObjectProtocol?

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override convenience init(frame: NSRect) {
        self.init(frame: frame, reduceMotionPreference: {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        })
    }

    /// The preference provider also lets rendering checks exercise accessibility
    /// changes without changing the user's system settings.
    init(frame: NSRect, reduceMotionPreference: @escaping () -> Bool) {
        self.reduceMotionPreference = reduceMotionPreference
        reduceMotion = reduceMotionPreference()
        super.init(frame: frame)
        // Layer-hosting: the view owns this tree outright and never draws.
        let root = CALayer()
        root.backgroundColor = CGColor.clear
        layer = root
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        assembleTree(in: root)
        update(force: true)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshMotionPreference() }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }

    private func refreshMotionPreference() {
        let preference = reduceMotionPreference()
        guard preference != reduceMotion else { return }
        reduceMotion = preference
        if reduceMotion {
            // Cancel transitions already in flight, including the shape mask,
            // before rebuilding the static indicators for the current state.
            if let layer { stopAnimations(in: layer) }
        }
        update()
    }

    private func stopAnimations(in layer: CALayer) {
        layer.removeAllAnimations()
        if let mask = layer.mask { stopAnimations(in: mask) }
        layer.sublayers?.forEach { stopAnimations(in: $0) }
    }

    private func assembleTree(in root: CALayer) {
        root.addSublayer(emblemRoot)
        root.addSublayer(captionLayer)

        for l in [emberLayer, glowLayer, sweepHaloLayer, coreLayer, coreFlashLayer,
                  litContainer, emberEmitter, inflowRing, burstEmitter] {
            emblemRoot.addSublayer(l)
        }
        shockwaves.forEach(emblemRoot.addSublayer)

        litContainer.mask = glyphMaskLayer
        for l in [litStrip, surgeLayer, sweepLayer, heldLayer, glintLayer] {
            litContainer.addSublayer(l)
        }
        inflowEmitters.forEach(inflowRing.addSublayer)

        // The strip slides by its left edge.
        litStrip.anchorPoint = .zero

        for e in [emberEmitter, burstEmitter] + inflowEmitters {
            e.renderMode = .additive
            e.birthRate = 0
        }
        for s in shockwaves {
            s.fillColor = nil
            s.opacity = 0
        }
    }

    // MARK: - Geometry (shared with hit testing)

    /// Emblem diameter. Taken from the unshifted bounds: the lift below moves
    /// the emblem but never resizes it, and the caption's own measurements feed
    /// that lift — going through `emblemFrame` here would recurse.
    private var emblemDiameter: CGFloat { LanternGlyph.emblemBounds(in: bounds).width }

    private var captionFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: emblemDiameter * 0.14, weight: .semibold)
    }

    /// Gap plus cap height: the space the percentage actually occupies.
    ///
    /// Digits and "%" paint from the baseline up to the cap height and have no
    /// descenders, so the line box is taller than the paint — at 22pt the box
    /// is 26pt tall while the paint covers 15pt, sitting 5pt above the draw
    /// origin. Laying out by the box sits the pair a few points high.
    private var captionBlock: CGFloat {
        Settings.shared.showPercent ? emblemDiameter * 0.05 + captionFont.capHeight : 0
    }

    /// The canvas, lifted by half the caption block so the ring and the number
    /// together straddle the window's centre — the point the saved position
    /// and Reset Position work from.
    private var canvasRect: CGRect { bounds.offsetBy(dx: 0, dy: captionBlock / 2) }

    /// The drawn emblem. Everything around it is padding that exists so the
    /// glow can fade out before the window edge.
    private var emblemFrame: CGRect { LanternGlyph.emblemBounds(in: canvasRect) }

    private func captionString() -> NSAttributedString {
        let font = captionFont
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = font.pointSize * 0.45
        shadow.shadowOffset = .zero
        return NSAttributedString(
            string: info.hasBattery ? "\(info.percent)%" : "AC",
            attributes: [
                .font: font,
                .foregroundColor: palette.bright.blended(withFraction: 0.25, of: .white) ?? palette.bright,
                .shadow: shadow,
            ])
    }

    /// Where the number's paint should land, and the origin to draw from to put
    /// it there: tucked under the ring, with the *digits* centred on the window
    /// and the "%" hanging off to the right. Centring the whole "74%" instead
    /// puts the midpoint inside the "%", which reads as off-centre.
    private func captionLayout() -> (string: NSAttributedString, origin: CGPoint, ink: CGRect) {
        let font = captionFont
        let str = captionString()
        let width = str.size().width
        let top = emblemFrame.minY - emblemDiameter * 0.05
        let ink = CGRect(x: bounds.midX - digitsWidth(of: str) / 2,
                         y: top - font.capHeight,
                         width: width, height: font.capHeight)
        // draw(at:) takes the line-box origin, and the baseline sits one descent
        // above it; `descender` is negative, hence the addition.
        return (str, CGPoint(x: ink.minX, y: ink.minY + font.descender), ink)
    }

    /// Width of the leading digits alone. Falls back to the whole string when
    /// there are none, so "AC" still centres as a whole.
    private func digitsWidth(of str: NSAttributedString) -> CGFloat {
        let digits = String(str.string.prefix { $0.isNumber })
        guard !digits.isEmpty else { return str.size().width }
        let attributes = str.attributes(at: 0, effectiveRange: nil)
        return NSAttributedString(string: digits, attributes: attributes).size().width
    }

    // MARK: - State

    private enum Mode: Equatable { case idle, charging, held, topped }

    private var level: CGFloat { CGFloat(info.hasBattery ? info.level : 1) }
    private var palette: LanternGlyph.Palette {
        LanternGlyph.palette(level: Double(level), charging: info.isCharging,
                             sworn: swornCorps)
    }
    private var scale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private var mode: Mode {
        if info.isCharging && !gateSealed { return .charging }
        if gateSealed && info.isPluggedIn { return .held }
        if info.isPluggedIn && level >= 0.995 { return .topped }
        return .idle
    }

    /// The corps the artwork is drawn as — the charge's, unless an oath has
    /// overridden it. Keyed on, so entering a new one dissolves.
    private var corps: LanternGlyph.Emblem { palette.emblem }

    /// Stays with the battery even when an oath has overridden the corps: the
    /// breathing means the charge is low, not that the lantern is yellow.
    private var lowBattery: Bool { !info.isCharging && level <= 0.20 }

    private struct ArtKey: Equatable {
        var canvas: CGSize, scale: CGFloat, percent: Int
        var corps: LanternGlyph.Emblem, charging: Bool
    }
    private struct MotionKey: Equatable {
        var canvas: CGSize, mode: Mode, low: Bool, glint: Bool, particles: Bool
        var reduceMotion: Bool
    }
    private struct CaptionKey: Equatable {
        var bounds: CGRect, scale: CGFloat, text: String
        var corps: LanternGlyph.Emblem, shown: Bool
    }
    private var artKey: ArtKey?
    private var motionKey: MotionKey?
    private var captionKey: CaptionKey?

    // MARK: - Update

    /// Brings the tree in line with the current state, doing only what changed:
    /// artwork when the size, palette or percentage moves; animations when the
    /// mode does. A reading that changes nothing visible costs nothing.
    private func update(force: Bool = false) {
        guard bounds.width > 1 else { return }
        if force {
            // Resizes and display changes rebuild at a new geometry or scale.
            // A dissolve's outgoing bitmap and a flourish's old positions no
            // longer fit; clear those before restarting the ambient motion.
            if let layer { stopAnimations(in: layer) }
            artKey = nil; motionKey = nil; captionKey = nil
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Whole device pixels: a layer at a fractional position is resampled by
        // the compositor, which softens every edge in it.
        emblemRoot.frame = snapped(canvasRect)
        // Cleared first because `rebuildArtIfNeeded` can return early without
        // reaching its own assignment, and a stale shift would dissolve the
        // caption for a change that isn't one.
        shift = nil
        rebuildArtIfNeeded()
        placeSurface()
        placeEmitters()
        configureMotionIfNeeded()
        updateCaptionIfNeeded()
        emblemRoot.opacity = Float(Settings.shared.opacity)
        captionLayer.opacity = Float(Settings.shared.opacity)
        glowLayer.opacity = glowBase
        CATransaction.commit()
    }

    private var local: CGRect { CGRect(origin: .zero, size: bounds.size) }

    private func rebuildArtIfNeeded() {
        let key = ArtKey(canvas: bounds.size, scale: scale,
                         percent: Int((level * 1000).rounded()), corps: corps,
                         charging: info.isCharging && !gateSealed)
        guard key != artKey else { return }
        let previous = artKey
        artKey = key
        let geometryChanged = previous?.canvas != key.canvas || previous?.scale != key.scale
        // The figure inside the ring changes with the palette tier, so the
        // mask has to be recut when it does, not only when the canvas moves.
        let figureChanged = previous?.corps != key.corps

        let canvas = local.size, s = scale, p = palette

        // A corps change is a moment, not a swap. `previous == nil` is a forced
        // rebuild — launch, a resize, a display change — which is not a shift;
        // nor is a rebuild at a new size, where the outgoing artwork is the
        // wrong shape to cross-fade against.
        let entered: LanternGlyph.Emblem? =
            (previous != nil && figureChanged && !geometryChanged) ? p.emblem : nil
        shift = reduceMotion ? nil : entered.map { CorpsShift(dissolve: dissolveTime(for: $0)) }

        /// Swaps a layer's artwork, dissolving into it during a corps shift.
        /// `contents` is animatable, so handing Core Animation the outgoing
        /// image as `fromValue` cross-fades the two in the compositor — which
        /// costs the app nothing beyond the images it was drawing anyway.
        func art(_ layer: CALayer, _ image: CGImage?) {
            let outgoing = layer.contents
            layer.contents = image
            guard let shift, let outgoing, image != nil else { return }
            let fade = CABasicAnimation(keyPath: "contents")
            fade.fromValue = outgoing
            fade.duration = shift.dissolve
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(paced(fade, 30), forKey: "corpsShift")
        }
        let e = LanternGlyph.emblemBounds(in: local), r = e.width / 2
        let centre = CGPoint(x: local.midX, y: local.midY)

        if geometryChanged {
            for l in [emberLayer, glowLayer, sweepHaloLayer, coreLayer, coreFlashLayer,
                      litContainer, glyphMaskLayer, sweepLayer, heldLayer, glintLayer,
                      emberEmitter, inflowRing, burstEmitter] + inflowEmitters + shockwaves {
                l.bounds = local
                l.position = centre
                l.contentsScale = s
            }
        }
        if geometryChanged || figureChanged {
            // Cross-fading the mask blends the two silhouettes, so the charge
            // shows at partial strength wherever the figures disagree — which
            // is exactly the dissolve, for free.
            art(glyphMaskLayer, LanternArt.glyphMask(canvas: canvas, scale: s,
                                                     emblem: p.emblem))
        }

        art(emberLayer, LanternArt.ember(canvas: canvas, scale: s, palette: p))
        art(glowLayer, LanternArt.glow(canvas: canvas, scale: s, level: level, palette: p))
        art(coreLayer, LanternArt.core(canvas: canvas, scale: s, level: level, palette: p))
        art(coreFlashLayer, LanternArt.coreFlash(canvas: canvas, scale: s, palette: p))
        art(heldLayer, LanternArt.heldRing(canvas: canvas, scale: s, palette: p))
        art(glintLayer, LanternArt.glint(canvas: canvas, scale: s, palette: p))
        art(sweepHaloLayer, LanternArt.sweepHalo(canvas: canvas, scale: s, palette: p))
        art(sweepLayer, LanternArt.sweep(canvas: canvas, scale: s, palette: p,
                                         comet: mode == .charging))

        // The charge: one period wider than the canvas so it can slide by a
        // period and loop without a seam.
        let period = r * 2
        let stripWidth = canvas.width + period
        art(litStrip, LanternArt.litStrip(canvas: canvas, width: stripWidth,
                                          margin: stripMargin, scale: s, level: level,
                                          palette: p, amp: surfaceAmp, period: period))
        litStrip.bounds = CGRect(x: 0, y: 0, width: stripWidth,
                                 height: canvas.height + stripMargin * 2)
        litStrip.contentsScale = s

        surgeLayer.colors = [p.bright.withAlphaComponent(0).cgColor,
                             p.bright.withAlphaComponent(0.713).cgColor,
                             p.bright.withAlphaComponent(0).cgColor]
        surgeLayer.bounds = CGRect(x: 0, y: 0, width: e.width + 2 * r, height: r * 0.62)
        surgeLayer.contentsScale = s

        let end = r * 1.4
        for w in shockwaves {
            w.path = CGPath(ellipseIn: CGRect(x: centre.x - end, y: centre.y - end,
                                              width: end * 2, height: end * 2), transform: nil)
            w.strokeColor = p.bright.cgColor
        }

        // After the cells and the shockwaves' colour, so the flourish throws
        // the corps it is arriving as.
        configureCells(r: r, palette: p)
        if let entered { flourish(entered) }
    }

    /// Surface ripple height: livelier while charging, flat when full.
    private var surfaceAmp: CGFloat {
        let r = LanternGlyph.emblemBounds(in: local).width / 2
        if level >= 0.995 { return 0 }
        return r * (mode == .charging ? 0.028 : 0.016)
    }

    /// Room above and below the strip for it to breathe into.
    private var stripMargin: CGFloat { local.height * 0.03 }

    /// The surface level is baked into the strip, so placing it is fixed.
    private func placeSurface() {
        litStrip.position = CGPoint(x: 0, y: -stripMargin)
        litStrip.isHidden = level <= 0.001
    }

    // MARK: - Particles

    /// How a corps' light behaves when nothing is happening to it — the motes
    /// the charge gives off as it sits there.
    ///
    /// Willpower is disciplined and rises evenly. Fear jitters and gutters
    /// out. Rage is spat upward and falls back. Avarice will not let anything
    /// go. Hope floats. Compassion gives itself away in every direction. Love
    /// drifts and sparkles. Death sinks. Life pours upward.
    ///
    /// The defaults are the Green Lantern's, which is what every corps used
    /// before; each of the others says only what it differs in.
    private struct Motes {
        var streaked = false            // the stretched mote, not the round one
        var lifetime: Float = 2.2
        var lifetimeRange: Float = 0.8
        var speed: CGFloat = 0.18       // × the emblem's radius
        var speedRange: CGFloat = 0.14
        var direction: CGFloat = .pi / 2    // emission longitude: up
        var spread: CGFloat = 0.6           // emission range
        var drift: CGFloat = 0.30       // y acceleration × r; negative sinks
        var size: CGFloat = 0.022       // × r
        var grow: CGFloat = 0.6         // scale speed, × size
        var fade: Float = -0.38
        var rate: Float = 1             // multiplies the emitter's birth rate
        var hotShare: Float = 0.28      // how many are the whiter cell
    }

    private static func motes(for emblem: LanternGlyph.Emblem) -> Motes {
        switch emblem {
        case .green:
            return Motes()

        case .sinestro:
            // Fear: short-lived, flung every which way, guttering out almost
            // as fast as it appears, and more of it than anything else.
            return Motes(lifetime: 1.4, lifetimeRange: 0.7, speed: 0.30,
                         speedRange: 0.28, spread: 2.3, drift: 0.06,
                         size: 0.021, grow: 0.3, fade: -0.78, rate: 1.7)

        case .red:
            // Rage: spat out hard and pulled straight back down, as streaks
            // rather than motes. It arcs and falls instead of rising.
            return Motes(streaked: true, lifetime: 1.7, lifetimeRange: 0.5,
                         speed: 0.58, speedRange: 0.30, spread: 1.5,
                         drift: -0.62, size: 0.030, grow: 0.1, fade: -0.5,
                         rate: 1.2, hotShare: 0.34)

        case .orange:
            // Avarice: nothing is allowed to leave. The motes barely get off
            // the charge before they are hauled back into it.
            return Motes(lifetime: 2.8, lifetimeRange: 0.7, speed: 0.09,
                         speedRange: 0.07, spread: 0.30, drift: -0.34,
                         size: 0.024, grow: 0.25, fade: -0.22, rate: 0.85)

        case .blue:
            // Hope: slow, orderly, buoyant. It rises further than any other
            // and takes its time about fading.
            return Motes(lifetime: 3.6, lifetimeRange: 1.0, speed: 0.10,
                         speedRange: 0.06, spread: 0.32, drift: 0.44,
                         size: 0.021, grow: 0.9, fade: -0.20, rate: 0.9,
                         hotShare: 0.34)

        case .indigo:
            // Compassion: given away rather than given off. It leaves in
            // every direction at once and weighs nothing.
            return Motes(lifetime: 3.0, lifetimeRange: 0.9, speed: 0.15,
                         speedRange: 0.05, spread: .pi, drift: 0,
                         size: 0.020, grow: 0.4, fade: -0.30, rate: 0.95)

        case .sapphire:
            // Love: crystalline. It drifts wide and slow, and more of it than
            // usual is the whiter cell, so it reads as facets catching light.
            return Motes(lifetime: 3.2, lifetimeRange: 1.1, speed: 0.19,
                         speedRange: 0.16, spread: 1.2, drift: 0.16,
                         size: 0.017, grow: 1.1, fade: -0.26, hotShare: 0.55)

        case .black:
            // Death: it doesn't rise at all. What comes off the charge sinks
            // away from it, slowly, and hardly brightens on the way.
            return Motes(lifetime: 3.4, lifetimeRange: 1.0, speed: 0.10,
                         speedRange: 0.08, direction: -.pi / 2, spread: 0.55,
                         drift: -0.20, size: 0.020, grow: 0.2, fade: -0.20,
                         rate: 0.7, hotShare: 0.12)

        case .white:
            // Life: all of it at once — the most, the fastest, the brightest.
            return Motes(lifetime: 2.8, lifetimeRange: 0.9, speed: 0.32,
                         speedRange: 0.18, spread: 0.95, drift: 0.55,
                         size: 0.024, grow: 0.8, fade: -0.30, rate: 1.7,
                         hotShare: 0.45)
        }
    }

    private func cell(_ image: CGImage?, color: NSColor) -> CAEmitterCell {
        let c = CAEmitterCell()
        c.contents = image
        c.color = color.cgColor
        return c
    }

    private func configureCells(r: CGFloat, palette p: LanternGlyph.Palette) {
        let hot = p.bright.blended(withFraction: 0.5, of: .white) ?? p.bright
        let e = LanternGlyph.emblemBounds(in: local)
        let m = Self.motes(for: p.emblem)

        // Embers: what the charge gives off while it just sits there. Every
        // corps' light behaves differently — see `Motes`.
        emberEmitter.emitterShape = .rectangle
        emberEmitter.emitterMode = .surface
        emberEmitter.emitterCells = [(p.bright, 1 - m.hotShare), (hot, m.hotShare)]
            .map { color, share in
                let art = m.streaked ? LanternArt.streak : LanternArt.dot
                let c = cell(art, color: color)
                c.birthRate = share
                c.lifetime = m.lifetime; c.lifetimeRange = m.lifetimeRange
                c.velocity = r * m.speed; c.velocityRange = r * m.speedRange
                c.emissionLongitude = m.direction; c.emissionRange = m.spread
                c.yAcceleration = r * m.drift
                // Born small and growing, since a cell can't fade *in*. The
                // streak art is half the dot's width, so it scales by half.
                c.scale = r * m.size / (m.streaked ? 16 : 32)
                c.scaleRange = c.scale * 0.45
                c.scaleSpeed = c.scale * m.grow
                c.alphaSpeed = m.fade
                return c
            }

        // Inflow: point emitters on a circle outside the ring, each aimed at
        // the hub. Straight paths inside a slowly rotating container trace
        // spirals on screen. Streaks, since these move fast. (A line-shaped
        // emitter would spread the spawn points more evenly, but it changes
        // the emission direction and flings motes outward — toward the window
        // edge, where they'd be cut off.)
        let radius = r * 1.34, speed = r * 0.85
        let centre = CGPoint(x: local.midX, y: local.midY)
        for (i, emitter) in inflowEmitters.enumerated() {
            let count = CGFloat(LanternView.inflowCount)
            emitter.transform = CATransform3DMakeRotation(2 * .pi * CGFloat(i) / count, 0, 0, 1)
            emitter.emitterShape = .point
            emitter.emitterPosition = CGPoint(x: centre.x, y: centre.y - radius)
            emitter.emitterCells = [("cool", p.bright, Float(0.7)),
                                    ("hot", hot, Float(0.3))].map { name, color, share in
                let c = cell(LanternArt.streak, color: color)
                c.name = name
                c.birthRate = share
                // Varied speed so the streams don't march in lockstep.
                c.velocity = speed; c.velocityRange = r * 0.22
                c.emissionLongitude = .pi / 2; c.emissionRange = 0.14
                c.scale = r * 0.034 / 16; c.scaleRange = c.scale * 0.35
                c.alphaSpeed = -0.25
                return c
            }
        }

        // Burst: flung out from the hub. Speed and life are capped so nothing
        // reaches the window edge (1.67r away), where it would be cut off.
        burstEmitter.emitterShape = .point
        burstEmitter.emitterPosition = CGPoint(x: e.midX, y: e.midY)
        burstEmitter.emitterCells = [(p.bright, Float(290)), (hot, Float(160))].map { color, rate in
            let c = cell(LanternArt.dot, color: color)
            c.birthRate = rate
            c.lifetime = 0.8; c.lifetimeRange = 0.25
            c.velocity = r * 0.95; c.velocityRange = r * 0.35
            c.emissionRange = 2 * .pi
            c.scale = r * 0.046 / 32; c.scaleRange = c.scale * 0.4
            c.alphaSpeed = -1.1
            return c
        }
    }

    /// Emission rates and the ember region follow the level and the mode;
    /// these are plain property sets, so they never restart an animation.
    private func placeEmitters() {
        let e = LanternGlyph.emblemBounds(in: local), r = e.width / 2
        let on = Settings.shared.particleEffects && !reduceMotion
        emberEmitter.isHidden = !on
        burstEmitter.isHidden = !on
        if !on { burstEmitter.birthRate = 0 }
        let fillH = max(1, level * e.height)
        emberEmitter.emitterPosition = CGPoint(x: e.midX, y: e.minY + fillH / 2)
        emberEmitter.emitterSize = CGSize(width: e.width * 0.78, height: fillH)
        emberEmitter.birthRate = on && level > 0.02
            ? Float(mode == .charging ? 20 : 6 + 7 * level) * Self.motes(for: corps).rate : 0

        // Held back: motes die at 0.78r, short of the hub, rather than 0.14r.
        let reach: CGFloat = mode == .held ? 0.78 : 0.14
        let life = Float((1.34 - reach) * r / (r * 0.85))
        for emitter in inflowEmitters {
            let perEmitter = Float(LanternView.inflowCount)
            emitter.birthRate = on ? (mode == .charging ? 34 / perEmitter
                                      : mode == .held ? 16 / perEmitter : 0) : 0
            // Cells are copied into the layer, so change them through it.
            emitter.setValue(life, forKeyPath: "emitterCells.cool.lifetime")
            emitter.setValue(life, forKeyPath: "emitterCells.hot.lifetime")
        }
        inflowRing.isHidden = !on
    }

    private func fireBurst() {
        guard !reduceMotion else { return }
        burstEmitter.beginTime = burstEmitter.convertTime(CACurrentMediaTime(), from: nil)
        burstEmitter.birthRate = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.burstEmitter.birthRate = 0
        }
    }

    // MARK: - Motion

    private var glowBase: Float {
        Float((1 + (hovering ? 0.25 : 0)) / LanternArt.glowCeiling)
    }

    private func configureMotionIfNeeded() {
        let key = MotionKey(canvas: bounds.size, mode: mode, low: lowBattery,
                            glint: level > 0.5 || mode == .charging,
                            particles: Settings.shared.particleEffects && !reduceMotion,
                            reduceMotion: reduceMotion)
        guard key != motionKey else { return }
        motionKey = key

        let e = LanternGlyph.emblemBounds(in: local), r = e.width / 2
        let charging = mode == .charging

        // The liquid surface slides one period and loops.
        let period = r * 2
        litStrip.removeAnimation(forKey: "slide")
        litStrip.removeAnimation(forKey: "breath")
        if !reduceMotion {
            let strip = litStrip
            let slide = CABasicAnimation(keyPath: "position.x")
            slide.fromValue = 0
            slide.toValue = -period
            slide.duration = 4.2
            slide.repeatCount = .infinity
            strip.add(paced(slide, 30), forKey: "slide")
            if charging {
                // A charging cell breathes a little above its true level.
                let breath = CABasicAnimation(keyPath: "position.y")
                breath.isAdditive = true
                breath.fromValue = -0.012 * e.height
                breath.toValue = 0.012 * e.height
                breath.duration = 1.65
                breath.autoreverses = true
                breath.repeatCount = .infinity
                breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                strip.add(paced(breath, 30), forKey: "breath")
            }
        }

        // Surge: a band of light climbing the emblem.
        surgeLayer.removeAnimation(forKey: "surge")
        surgeLayer.isHidden = !charging || reduceMotion
        if charging && !reduceMotion {
            surgeLayer.position = CGPoint(x: e.midX, y: e.minY)
            let climb = CABasicAnimation(keyPath: "position.y")
            climb.fromValue = e.minY - r * 0.3
            climb.toValue = e.maxY + r * 0.3
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.55, 1]
            let group = CAAnimationGroup()
            group.animations = [climb, fade]
            group.duration = 2.1
            group.repeatCount = .infinity
            climb.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            surgeLayer.add(paced(group, 60), forKey: "surge")
        }

        // Ring sweep: a fast comet while charging, a slow shimmer when full.
        for l in [sweepLayer, sweepHaloLayer] { l.removeAnimation(forKey: "spin") }
        sweepLayer.isHidden = !(charging || mode == .topped)
        sweepHaloLayer.isHidden = !charging
        if !reduceMotion && (charging || mode == .topped) {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * CGFloat.pi
            spin.duration = charging ? 2 * .pi / 2.2 : 2 * .pi / 0.55
            spin.repeatCount = .infinity
            let paced = paced(spin, charging ? 60 : 30)
            sweepLayer.add(paced, forKey: "spin")
            if charging { sweepHaloLayer.add(paced, forKey: "spin") }
        }

        // Held back: the ring breathes, waiting.
        heldLayer.removeAnimation(forKey: "pulse")
        heldLayer.isHidden = mode != .held
        heldLayer.opacity = 0.255
        if mode == .held && !reduceMotion {
            heldLayer.add(pulse(from: 0.169, to: 0.342, half: .pi / 1.15), forKey: "pulse")
        }

        // Hub glint, quicker while charging.
        glintLayer.removeAnimation(forKey: "pulse")
        glintLayer.isHidden = !key.glint
        glintLayer.opacity = 0.339
        if key.glint && !reduceMotion {
            glintLayer.add(pulse(from: 0.271, to: 0.407, half: .pi / (charging ? 3.4 : 1.2)),
                           forKey: "pulse")
        }

        // The hub flickers as it swallows motes.
        coreFlashLayer.removeAnimation(forKey: "flicker")
        coreFlashLayer.isHidden = !(charging && key.particles)
        if charging && key.particles {
            let flicker = CAKeyframeAnimation(keyPath: "opacity")
            flicker.values = [0.15, 0.6, 0.2, 0.75, 0.25, 0.55, 0.15]
            flicker.duration = 2.3
            flicker.repeatCount = .infinity
            coreFlashLayer.add(paced(flicker, 30), forKey: "flicker")
        }

        // Motes spiral in: the whole inflow ring turns slowly.
        inflowRing.removeAnimation(forKey: "spin")
        if key.particles && (charging || mode == .held) {
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = 2 * CGFloat.pi
            turn.duration = 10
            turn.repeatCount = .infinity
            inflowRing.add(paced(turn, 30), forKey: "spin")
        }

        // Low battery breathes, so it catches the eye.
        glowLayer.removeAnimation(forKey: "breathe")
        if key.low && !reduceMotion {
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.isAdditive = true
            breathe.fromValue = -0.25 * glowBase
            breathe.toValue = 0.10 * glowBase
            breathe.duration = .pi / 2
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            glowLayer.add(paced(breathe, 30), forKey: "breathe")
        }
    }

    /// Caps an animation's frame rate. This display runs at up to 120Hz; slow
    /// ambient motion looks the same at 30, and the compositor does a quarter
    /// of the work. Only fast things — the comet, the surge, flares — get 60.
    private func paced<A: CAAnimation>(_ animation: A, _ fps: Float) -> A {
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: min(fps, 24),
                                                             maximum: fps, preferred: fps)
        return animation
    }

    private func pulse(from: Float, to: Float, half: CFTimeInterval) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = to
        a.duration = half
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return paced(a, 30)
    }

    /// A glow spike that decays back to rest — on plug-in, and on the oath.
    private func flareGlow(duration: CFTimeInterval) {
        guard !reduceMotion else { return }
        let spike = CABasicAnimation(keyPath: "opacity")
        spike.isAdditive = true
        spike.fromValue = 1 - glowBase
        spike.toValue = 0
        spike.duration = duration
        spike.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.7, 0.3, 1)
        glowLayer.add(paced(spike, 60), forKey: "flare")
    }

    /// The opposite of `flareGlow`: the bloom is put out and creeps back.
    /// Sharing the "flare" key means one replaces the other rather than the
    /// two fighting over the layer.
    private func snuffGlow(duration: CFTimeInterval) {
        guard !reduceMotion else { return }
        let snuff = CABasicAnimation(keyPath: "opacity")
        snuff.isAdditive = true
        snuff.fromValue = -glowBase
        snuff.toValue = 0
        snuff.duration = duration
        snuff.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.5, 1)
        glowLayer.add(paced(snuff, 60), forKey: "flare")
    }

    /// Rings thrown outward in turn. Each finishes at 1.4r, well inside the
    /// canvas's 1.67r reach, so the window edge never cuts one off. The
    /// defaults are the oath's; a corps shift asks for its own count and pace.
    private func fireShockwave(count: Int = 3, duration: CFTimeInterval = 2.4,
                               stagger: CFTimeInterval = 0.384, alpha: Float = 0.75) {
        guard !reduceMotion else { return }
        let r = LanternGlyph.emblemBounds(in: local).width / 2
        let now = CACurrentMediaTime()
        for (i, wave) in shockwaves.enumerated() {
            // Rings this call doesn't want must drop whatever they were still
            // running, or a leftover wave finishes over the top of the new ones.
            guard i < count else { wave.removeAnimation(forKey: "wave"); continue }
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.55 / 1.4
            grow.toValue = 1
            grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.4, 1)
            let thin = CABasicAnimation(keyPath: "lineWidth")
            thin.fromValue = r * 0.06 * 1.4 / 0.55
            thin.toValue = r * 0.033
            thin.timingFunction = grow.timingFunction
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = alpha
            fade.toValue = 0
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.3, 0.6, 1)
            let group = CAAnimationGroup()
            group.animations = [grow, thin, fade]
            group.duration = duration
            group.beginTime = wave.convertTime(now, from: nil) + Double(i) * stagger
            wave.add(paced(group, 60), forKey: "wave")
        }
    }

    // MARK: - Corps shift

    /// A corps change — the charge crossing 20% or 10% — is a moment, not a
    /// swap. Every piece of artwork dissolves from the old figure and palette
    /// into the next, and the corps being *entered* throws its own flourish
    /// over the top. Direction doesn't matter: charging back up plays the
    /// flourish of whichever corps the light lands in.
    ///
    /// All of it is Core Animation on layers that already exist, so a shift
    /// costs one round of artwork — which the palette change needed anyway —
    /// and then nothing until it ends.
    private struct CorpsShift {
        var dissolve: CFTimeInterval
    }
    private var shift: CorpsShift?
    /// When a corps last threw its flourish, so an oath that caused one knows
    /// not to throw a second over the top of it.
    private var lastFlourish: CFTimeInterval = -.infinity

    private func dissolveTime(for emblem: LanternGlyph.Emblem) -> CFTimeInterval {
        switch emblem {
        case .sinestro: return 0.55    // covered by the stutter
        case .red:      return 0.40    // quick, like the blow that carries it
        case .orange:   return 0.32    // quickest of all: greed doesn't wait
        case .black:    return 1.15    // slowest: a light going out, not a change
        case .white:    return 0.90    // unhurried, and brighter all the way
        case .blue:     return 0.80    // gentle; hope isn't sudden
        case .sapphire: return 0.70    // quick enough to keep up with the beats
        case .indigo:   return 1.00    // unhurried, and unhurriedly returned
        case .green:    return 0.70    // unhurried, but not a lingering blur
        }
    }

    /// The flourish the arriving corps throws while the artwork dissolves
    /// under it. Applied to the emblem and the caption together, so the
    /// number goes with the lantern rather than sitting steady beside it.
    private func flourish(_ emblem: LanternGlyph.Emblem) {
        guard !reduceMotion else { return }
        lastFlourish = CACurrentMediaTime()
        let r = LanternGlyph.emblemBounds(in: local).width / 2

        func play(_ animation: CAAnimation) {
            // Adding one animation object to two layers is safe: Core
            // Animation copies it on add.
            for l in [emblemRoot, captionLayer] { l.add(animation, forKey: "corpsFlourish") }
        }

        switch emblem {
        case .sinestro:
            // Fear. The green light stutters out — hard, uneven cuts, not a
            // fade — and the emblem flinches before the yellow takes hold.
            let stutter = CAKeyframeAnimation(keyPath: "opacity")
            stutter.isAdditive = true
            // Scaled by the opacity setting: an absolute -0.9 would black the
            // emblem out entirely for someone running the lantern faint, and
            // barely register for someone running it solid.
            let depth = Settings.shared.opacity
            stutter.values = [0, -0.85, -0.05, -0.92, -0.30, -0.75, -0.10, 0]
                .map { $0 * depth }
            stutter.keyTimes = [0, 0.04, 0.09, 0.15, 0.21, 0.29, 0.37, 1]
            let flinch = CAKeyframeAnimation(keyPath: "transform.scale")
            flinch.values = [1, 0.945, 1.018, 1]
            flinch.keyTimes = [0, 0.30, 0.68, 1]
            flinch.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let group = CAAnimationGroup()
            group.animations = [stutter, flinch]
            group.duration = 0.9
            play(paced(group, 60))
            fireShockwave(count: 1, duration: 1.3, alpha: 0.6)
            flareGlow(duration: 1.0)

        case .red:
            // Rage. It arrives as a blow: the emblem kicks, shudders sideways
            // and throws three hard rings, with a burst out of the hub.
            let kick = CAKeyframeAnimation(keyPath: "transform.scale")
            kick.values = [1, 1.085, 0.962, 1.025, 0.995, 1]
            kick.keyTimes = [0, 0.12, 0.30, 0.48, 0.72, 1]
            // The shudder rides `position`, not `transform`: two animations on
            // parts of the same transform fight over it.
            let shudder = CAKeyframeAnimation(keyPath: "position.x")
            shudder.isAdditive = true
            shudder.values = [0, -r * 0.05, r * 0.038, -r * 0.024, r * 0.011, 0]
            shudder.keyTimes = [0, 0.09, 0.22, 0.38, 0.56, 1]
            let group = CAAnimationGroup()
            group.animations = [kick, shudder]
            group.duration = 0.7
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            play(paced(group, 60))
            fireShockwave(count: 3, duration: 1.5, stagger: 0.16, alpha: 0.8)
            if Settings.shared.particleEffects { fireBurst() }
            flareGlow(duration: 1.5)

        case .orange:
            // Avarice. It arrives as a grab: the emblem clenches down hard
            // first, then throws itself open wider than it rests. Red kicks
            // outward and shudders sideways; this one clutches, and doesn't
            // shudder at all.
            let clutch = CAKeyframeAnimation(keyPath: "transform.scale")
            clutch.values = [1, 0.875, 1.105, 0.975, 1.02, 1]
            clutch.keyTimes = [0, 0.14, 0.34, 0.55, 0.78, 1]
            clutch.duration = 0.62
            clutch.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.2, 1)
            play(paced(clutch, 60))
            fireShockwave(count: 1, duration: 1.1, alpha: 0.85)
            if Settings.shared.particleEffects { fireBurst() }
            flareGlow(duration: 1.2)

        case .black:
            // Death. Nothing flares: the light goes out, and what comes back
            // is already black. One long fall and one slow ring, and the bloom
            // is snuffed rather than spiked — which no other corps does.
            let fall = CAKeyframeAnimation(keyPath: "opacity")
            fall.isAdditive = true
            let depth = Settings.shared.opacity
            fall.values = [0, -0.94, -0.80, -0.30, 0].map { $0 * depth }
            fall.keyTimes = [0, 0.30, 0.47, 0.72, 1]
            let sink = CAKeyframeAnimation(keyPath: "transform.scale")
            sink.values = [1, 0.948, 1.006, 1]
            sink.keyTimes = [0, 0.44, 0.82, 1]
            let group = CAAnimationGroup()
            group.animations = [fall, sink]
            group.duration = 1.7
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            play(paced(group, 60))
            fireShockwave(count: 1, duration: 2.8, alpha: 0.35)
            snuffGlow(duration: 2.2)

        case .white:
            // Dawn. The one arrival that ends brighter than the lantern ever
            // rests: a long swell, three unhurried rings and a bloom held up
            // at its ceiling — the exact opposite of the black.
            let dawn = CAKeyframeAnimation(keyPath: "transform.scale")
            dawn.values = [1, 1.012, 1.075, 1.022, 1]
            dawn.keyTimes = [0, 0.18, 0.44, 0.75, 1]
            dawn.duration = 1.5
            dawn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            play(paced(dawn, 60))
            fireShockwave(count: 3, duration: 2.6, stagger: 0.30, alpha: 0.6)
            if Settings.shared.particleEffects { fireBurst() }
            flareGlow(duration: 2.6)

        case .blue:
            // Hope. It doesn't arrive so much as lift: the lantern rises a
            // little, brightens, and settles back. The only flourish that
            // moves the emblem off its centre without shaking it.
            let lift = CAKeyframeAnimation(keyPath: "position.y")
            lift.isAdditive = true
            lift.values = [0, r * 0.055, r * 0.012, 0]
            lift.keyTimes = [0, 0.38, 0.72, 1]
            let rise = CAKeyframeAnimation(keyPath: "transform.scale")
            rise.values = [1, 1.035, 1.006, 1]
            rise.keyTimes = [0, 0.40, 0.74, 1]
            let group = CAAnimationGroup()
            group.animations = [lift, rise]
            group.duration = 1.4
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            play(paced(group, 60))
            fireShockwave(count: 2, duration: 2.2, stagger: 0.42, alpha: 0.5)
            flareGlow(duration: 2.0)

        case .sapphire:
            // Love. It arrives as a heartbeat — two beats, the second softer.
            // Nothing else in the set pulses twice, which is the whole of how
            // you tell it from the green's single swell.
            let beat = CAKeyframeAnimation(keyPath: "transform.scale")
            beat.values = [1, 1.062, 1.008, 1.040, 1.002, 1]
            beat.keyTimes = [0, 0.11, 0.26, 0.38, 0.56, 1]
            beat.duration = 1.3
            beat.timingFunction = CAMediaTimingFunction(name: .easeOut)
            play(paced(beat, 60))
            // Two rings, staggered to land with the two beats.
            fireShockwave(count: 2, duration: 1.8, stagger: 0.35, alpha: 0.6)
            flareGlow(duration: 1.6)

        case .indigo:
            // Compassion. The one arrival that barely moves the emblem at all:
            // it holds nearly still and lets three rings go out from it, evenly
            // spaced rather than thrown. Every other flourish is something
            // happening *to* the lantern; this one is something leaving it.
            let steady = CAKeyframeAnimation(keyPath: "transform.scale")
            steady.values = [1, 1.018, 1.004, 1]
            steady.keyTimes = [0, 0.45, 0.78, 1]
            steady.duration = 1.8
            steady.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            play(paced(steady, 60))
            fireShockwave(count: 3, duration: 3.0, stagger: 0.62, alpha: 0.42)
            flareGlow(duration: 2.4)

        case .green:
            // Restored. No violence — the lantern swells once and settles.
            let swell = CAKeyframeAnimation(keyPath: "transform.scale")
            swell.values = [1, 1.045, 0.998, 1]
            swell.keyTimes = [0, 0.36, 0.75, 1]
            swell.duration = 1.2
            swell.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            play(paced(swell, 60))
            fireShockwave(count: 1, duration: 2.0, alpha: 0.5)
            flareGlow(duration: 1.8)
        }
    }

    // MARK: - Caption

    /// Rendered to an image once per value — not re-laid-out every frame.
    private func updateCaptionIfNeeded() {
        let shown = Settings.shared.showPercent
        let layout = captionLayout()
        let key = CaptionKey(bounds: bounds, scale: scale, text: layout.string.string,
                             corps: corps, shown: shown)
        guard key != captionKey else { return }
        captionKey = key
        captionLayer.isHidden = !shown
        guard shown else { return }

        let outgoing = captionLayer.contents
        let margin = ceil(captionFont.pointSize * 0.45 * 2 + 2)
        let size = layout.string.size()
        // The layer sits on whole pixels, so the compositor never resamples the
        // text; the fractional part of the position goes into the drawing.
        let frame = snapped(CGRect(x: layout.origin.x - margin, y: layout.origin.y - margin,
                                   width: size.width + margin * 2,
                                   height: size.height + margin * 2))
        let inset = CGPoint(x: layout.origin.x - frame.minX, y: layout.origin.y - frame.minY)
        captionLayer.contents = LanternArt.image(frame.size, scale: scale) { ctx in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            layout.string.draw(at: inset)
            NSGraphicsContext.restoreGraphicsState()
        }
        captionLayer.frame = frame
        captionLayer.contentsScale = scale
        // The digits are monospaced, so a shift's old and new captions are the
        // same width and cross-fade without wobbling.
        if let shift, let outgoing, captionLayer.contents != nil {
            let fade = CABasicAnimation(keyPath: "contents")
            fade.fromValue = outgoing
            fade.duration = shift.dissolve
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            captionLayer.add(paced(fade, 30), forKey: "corpsShift")
        }
    }

    /// `rect` with its origin rounded to whole device pixels and its size
    /// rounded up to them.
    private func snapped(_ rect: CGRect) -> CGRect {
        let s = scale
        let x = (rect.minX * s).rounded() / s, y = (rect.minY * s).rounded() / s
        return CGRect(x: x, y: y, width: (rect.width * s).rounded(.up) / s,
                      height: (rect.height * s).rounded(.up) / s)
    }

    // MARK: - Lifecycle

    override func setFrameSize(_ newSize: NSSize) {
        let resized = newSize != frame.size
        super.setFrameSize(newSize)
        if resized { update(force: true) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        update(force: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { update(force: true) }
    }

    // MARK: - Hit testing & interaction

    /// Only the emblem itself is clickable, so the rest of the window stays
    /// transparent to the desktop underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if Settings.shared.showPercent,
           captionLayout().ink.insetBy(dx: -8, dy: -6).contains(local) {
            return self
        }
        let e = emblemFrame
        let radius = e.width / 2
        let dx = local.x - e.midX, dy = local.y - e.midY
        return (dx * dx + dy * dy <= radius * radius) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(with: event)
            return
        }
        guard !Settings.shared.lockPosition else { return }
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) { showMenu(with: event) }

    private func showMenu(with event: NSEvent) {
        guard let contextMenu else { return }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
    }
}
