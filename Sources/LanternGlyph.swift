import AppKit

/// Vector reconstruction of the lantern emblems: an outer ring enclosing a
/// figure. Three figures are drawn — the Green Lantern's (a wide bar top and
/// bottom, curved brackets down each side, and a bordered hub circle between
/// them), the Sinestro Corps' (a broken middle band tied to a chunkier hub by
/// four spokes), and the Red Lantern Corps' (two straight side bars that jog
/// outward partway up, around a hub that sits low).
///
/// All geometry is expressed in *unit* coordinates centred on the origin,
/// where 1.0 is the outer radius of the ring. `path(in:emblem:)` maps that onto
/// a concrete rect, so the emblems are resolution independent.
enum LanternGlyph {

    /// Which corps' figure sits inside the ring.
    ///
    /// The lantern's colour already tracks the charge, and the figure follows
    /// it: as the light turns yellow and then red, so does the allegiance.
    enum Emblem {
        case green      // Green Lantern Corps
        case sinestro   // Sinestro Corps
        case red        // Red Lantern Corps
        case orange     // Orange Lantern Corps — sworn only, never the charge's
        case black      // Black Lantern Corps — the last 1%, or its oath
        case white      // White Lantern Corps — a full charge, or its oath
        case blue       // Blue Lantern Corps — sworn only, like the orange
        case sapphire   // Star Sapphire Corps — sworn only as well
        case indigo     // Indigo Tribe — sworn only, the last of them
    }

    // MARK: - Proportions
    //
    // Modelled on the Lanterns ring: the lantern's sides are separate curved
    // brackets standing off from a bordered hub circle, rather than the hub
    // band itself reaching out to the bars. The dark crescents that leaves
    // between bracket and hub are what give the emblem its depth.

    /// Outer ring: outer edge at 1.0, inner edge at 0.872. Shared by both
    /// figures — the ring is the vessel, and the comet, the sweep and the held
    /// pulse all ride on it, so it stays put when the figure inside changes.
    static let ringInner: CGFloat = 0.872
    /// Half-width of the top and bottom bars.
    static let barHalfWidth: CGFloat = 0.515
    /// Bars occupy |y| in 0.315...0.575.
    static let barInnerY: CGFloat = 0.315
    static let barOuterY: CGFloat = 0.575
    /// The curved brackets down the left and right sides.
    static let shoulderInner: CGFloat = 0.450
    static let shoulderOuter: CGFloat = 0.508
    /// How far each bracket sweeps either side of horizontal. Wide enough that
    /// both its edges finish inside the bars, so the join is seamless.
    static let shoulderSweep: CGFloat = 58 * .pi / 180
    /// The hub circle, which meets the bars top and bottom.
    static let hubOuter: CGFloat = 0.375
    static let hubInner: CGFloat = 0.295

    // MARK: Sinestro proportions
    //
    // Measured off the Corps emblem and rescaled so its outer ring matches the
    // Green Lantern one. A solid hub, a middle band broken in four places, and
    // three arms carrying that band out to the ring and joining it there — one
    // on each flank and a wider one at the bottom. The ring itself is notched
    // just outboard of each flank arm.
    //
    // Nothing bridges hub to band: the hub hangs in the middle on its own, and
    // the band hangs off the ring.

    /// Everything inside the ring is drawn this much smaller than the measured
    /// emblem. The drawn one separates its figure from its ring with a dark
    /// gap; with the ring kept at the shared width there is no room for that,
    /// so the figure gives the ground instead and the gap is the emblem's own
    /// empty space rather than paint.
    static let sinestroInset: CGFloat = 0.92

    /// The hub: a bordered ring around a bore, in the same proportion the Green
    /// Lantern one wears, so the engraved core sits in this figure too. The
    /// drawn emblem fills its centre solid; the widget keeps its own detail
    /// there instead, which is what makes the six centres read alike.
    static let sinestroHubOuter: CGFloat = 0.347 * sinestroInset
    static let sinestroHubInner: CGFloat = sinestroHubOuter * (hubInner / hubOuter)

    /// The middle band.
    static let bandInner: CGFloat = 0.522 * sinestroInset
    static let bandOuter: CGFloat = 0.702 * sinestroInset

    /// Where the band is broken, as (centre, half-width) in degrees: a pair
    /// high on the flanks, a pair low.
    static let sinestroBandGaps: [(centre: CGFloat, half: CGFloat)] = [
        (90 - 28.5, 7), (90 + 28.5, 7), (270 - 20.75, 7.25), (270 + 20.75, 7.25),
    ]

    /// The arms out to the ring. The bottom one is much the widest, and is what
    /// the drawn emblem stands on.
    static let sinestroArms: [(centre: CGFloat, half: CGFloat)] = [
        (90 - 57.5, 8.5), (90 + 57.5, 8.5), (270, 14),
    ]
    /// How far out an arm reaches. Past the ring's inner edge, so the join is
    /// inside the ring rather than a seam against it.
    static let armOuter: CGFloat = 0.930

    /// The drawn emblem notches its ring either side of top centre. This one
    /// doesn't: the ring is the same unbroken band every other corps wears,
    /// which is what keeps the six of them a set. The separation the notches
    /// give the drawing is got here by holding the figure clear of the ring
    /// instead — see `sinestroInset`.

    // MARK: Blue Lantern proportions
    //
    // Measured off the Corps emblem, rescaled so its outer ring matches the
    // shared one, and inset for the same reason the Sinestro figure is. Built
    // like that one — a bordered hub, a broken band, arms out to the ring —
    // but with six breaks rather than four and four arms rather than three.

    static let blueInset: CGFloat = 0.92
    static let blueHubOuter: CGFloat = 0.358 * blueInset
    static let blueHubInner: CGFloat = blueHubOuter * (hubInner / hubOuter)
    static let blueBandInner: CGFloat = 0.515 * blueInset
    static let blueBandOuter: CGFloat = 0.725 * blueInset

    /// Six breaks: three around the top, three around the bottom, leaving the
    /// band whole down each flank.
    static let blueBandGaps: [(centre: CGFloat, half: CGFloat)] = [
        (90, 7.5), (90 - 39.5, 7.5), (90 + 39.5, 7.5),
        (270, 7.5), (270 - 38, 7.5), (270 + 38, 7.5),
    ]
    /// Four arms out to the ring, each at the outer end of a band piece and
    /// finer than the Sinestro emblem's.
    static let blueArms: [(centre: CGFloat, half: CGFloat)] = [
        (90 - 28, 4), (90 + 28, 4), (270 - 27.5, 4), (270 + 27.5, 4),
    ]

    // MARK: Star Sapphire proportions
    //
    // Measured off the Corps emblem. Not a lantern figure at all: an eight-
    // pointed star inside the ring, with an upright ellipse cut out of its
    // middle. Its points alternate long and short — the four on the compass
    // reach the ring, the four diagonals stop well short — and the valleys
    // between them are *not* at the midpoints, which is what gives the long
    // points their taper.

    /// The star's three radii: the cardinal tips, the diagonal tips, and the
    /// valleys between.
    static let sapphireLong: CGFloat = 0.890
    static let sapphireShort: CGFloat = 0.680
    static let sapphireValley: CGFloat = 0.409
    /// How far a valley sits from the diagonal tip it flanks. At 15° it is
    /// nearer the short point than the long one, so each long point spreads
    /// over 60° of base and each short point over 30°.
    static let sapphireValleyOffset: CGFloat = 15

    /// The hole at the star's heart, an ellipse standing taller than it is wide.
    static let sapphireEyeWidth: CGFloat = 0.201
    static let sapphireEyeHeight: CGFloat = 0.276

    // MARK: Indigo Tribe proportions
    //
    // Measured off the Tribe's emblem and rescaled so its outer ring matches
    // the shared one. A bordered hub with a chevron above it and another
    // below, both mitred to a point and cut off square at the foot. The arms
    // run at 45°, which is what makes the mitre exactly √2 times the stroke's
    // half-width.

    static let indigoHubOuter: CGFloat = 0.472
    static let indigoHubInner: CGFloat = 0.329
    /// Where a chevron's arms meet, measured up from the emblem's centre.
    static let indigoChevronCorner: CGFloat = 0.762
    static let indigoChevronHalf: CGFloat = 0.0713
    /// The height its arms are cut off at — low enough that each foot lands on
    /// the hub rather than hanging above it, which is what joins the figure up.
    static let indigoChevronFoot: CGFloat = 0.329

    // MARK: Red Lantern proportions
    //
    // Measured off the Corps emblem and rescaled, like the Sinestro figure, so
    // its outer ring matches the Green Lantern one. Straight-edged where the
    // others are round: two vertical bars down the flanks, each jogging
    // outward partway up along a pair of parallel diagonals, and a hub that
    // sits well below the emblem's centre. Everything between them — the
    // crescents outside the bars, the body above the hub — is empty.

    /// The bars' lower stretch: inner edge, and the width both stretches share.
    static let redBarInner: CGFloat = 0.380
    static let redBarWidth: CGFloat = 0.133
    /// The upper stretch's inner edge, further out.
    static let redBarInnerTop: CGFloat = 0.478
    /// The jog between them, as the heights its inner diagonal runs between.
    /// The outer edge repeats it, translated by `redBarWidth`.
    static let redJogLow: CGFloat = 0.214
    static let redJogHigh: CGFloat = 0.385
    /// How far below the emblem's centre the hub's own centre sits.
    static let redHubDrop: CGFloat = 0.237
    static let redHubOuter: CGFloat = 0.461
    static let redHubInner: CGFloat = 0.298
    /// The bars stop on this radius. It is inside the ring's outer edge and
    /// outside its inner one, so both corners of each end are buried in the
    /// ring rather than notching its rim or hanging in the gap short of it.
    static let redCapRadius: CGFloat = 0.96

    // MARK: Orange Lantern proportions
    //
    // Measured off the Corps emblem and rescaled like the others. A spoked
    // wheel: a bordered hub with six bars running out to the ring, and the two
    // steep ones carrying on inward through the bore to meet at the centre —
    // the chevron the sign turns on.

    static let orangeHubInner: CGFloat = 0.339
    static let orangeHubOuter: CGFloat = 0.480
    /// Spokes are bars, not wedges: this is a perpendicular half-width, so
    /// they keep their thickness the whole way out instead of fanning.
    static let orangeSpokeHalf: CGFloat = 0.090
    /// Where the six spokes point. The two steep ones are carried on inward
    /// by the chevron below.
    static let orangeSteepSpokes: [CGFloat] = [90 - 27, 90 + 27]
    static let orangeOuterSpokes: [CGFloat] = [90 - 55.5, 90 + 55.5, 270 - 42, 270 + 42]

    /// The chevron in the bore, continuing the line of the two steep spokes
    /// down to a point. Its arms are finer than the spokes, and its corner
    /// sits *above* the emblem's centre — the mitre reaches back down past the
    /// middle, and the notch it leaves at the hub's top is the gap between the
    /// arms' inner edges.
    static let orangeChevronHalf: CGFloat = 0.064
    static let orangeChevronCorner: CGFloat = 0.090
    /// How far each arm runs, ending inside the hub's band.
    static let orangeChevronArm: CGFloat = 0.38
    /// Spokes stop on this radius — inside the ring's outer edge, so no corner
    /// notches its rim.
    static let orangeCapRadius: CGFloat = 0.94

    // MARK: Black Lantern proportions
    //
    // Measured off the Corps emblem and rescaled like the others. Not a ring
    // figure at all: five bars across the top under a shared dome, and below
    // them an inverted triangle drawn as an outline.

    /// The grille: five bars, by half-width and centre-to-centre spacing.
    static let blackBarHalf: CGFloat = 0.090
    static let blackBarPitch: CGFloat = 0.296
    /// Where they stop, short of the band below — the gap between is the
    /// figure's, not an accident.
    static let blackBarFoot: CGFloat = 0.129
    /// The arc their tops are cut against, a little inside the ring.
    static let blackBarDome: CGFloat = 0.807

    /// The triangle below, as an outer shape with a hollow punched out of it.
    /// The outer point falls beyond the emblem, so it is cut flat low down
    /// where the ring covers the cut.
    static let blackTriangleTop: CGFloat = 0.016
    static let blackTriangleHalf: CGFloat = 0.879
    static let blackTriangleCut: CGFloat = -0.92
    static let blackTriangleCutHalf: CGFloat = 0.130
    static let blackHollowTop: CGFloat = -0.134
    static let blackHollowHalf: CGFloat = 0.569
    static let blackHollowApex: CGFloat = -0.874

    // MARK: White Lantern proportions
    //
    // Measured off the Corps emblem and rescaled like the others. Seven spikes
    // fanning out of the middle, a crescent beneath them, and an inverted
    // triangle of the same kind the Black Lantern ends in.

    /// The fan: seven spikes running out to the ring, evenly spaced about the
    /// vertical — but *aimed* at a point low in the triangle's mouth rather
    /// than at the emblem's centre. Fitting the drawn emblem's ray angles to a
    /// common origin puts that origin here, and nowhere near the middle: aimed
    /// at the centre the same rays are visibly uneven.
    static let whiteRayAim: CGFloat = -0.55
    static let whiteRayStep: CGFloat = 16.0      // degrees between them, about the aim
    /// Where the spikes come to their points. They are staggered rather than
    /// level: the middle one stops furthest from the triangle, and each step
    /// out from it stops a little closer. Measured off the drawn emblem, whose
    /// tips run from +0.057 at the centre down to -0.032 at the flanks — level
    /// tips read as a solid arc of needles rather than a fan.
    static let whiteRayFoot: CGFloat = 0.045
    static let whiteRayStagger: CGFloat = 0.028
    static let whiteRayBase: CGFloat = 0.947     // where a spike meets the ring
    static let whiteRayHalf: CGFloat = 0.118     // half-width there
    /// They are not all the same weight: each step out from the vertical takes
    /// this much off the half-width, so the fan thins toward the horizontal
    /// the way the drawn emblem's does.
    static let whiteRayTaper: CGFloat = 0.145

    /// The crescent beneath the fan. Its arcs are struck from a centre well
    /// below the emblem's, which is why it sits deeper at the sides than at
    /// the top; `whiteCrescentSpan` stops its ends inside the ring.
    static let whiteCrescentDrop: CGFloat = 0.546
    static let whiteCrescentInner: CGFloat = 0.916
    static let whiteCrescentOuter: CGFloat = 1.019
    static let whiteCrescentSpan: CGFloat = 20

    /// The triangle below — the Black Lantern's shape, a little wider.
    static let whiteTriangleTop: CGFloat = -0.129
    static let whiteTriangleHalf: CGFloat = 0.655
    static let whiteTriangleCut: CGFloat = -0.906
    static let whiteTriangleCutHalf: CGFloat = 0.132
    static let whiteHollowTop: CGFloat = -0.283
    static let whiteHollowHalf: CGFloat = 0.390
    static let whiteHollowApex: CGFloat = -0.867

    /// Room around the emblem, as a fraction of the canvas half-width. The
    /// bloom has to fade to nothing inside this: if it reaches the edge of the
    /// transparent window it gets cut off in straight lines, and the window
    /// shows up as a faint green box.
    static let glowPadding: CGFloat = 0.40

    /// Emblem diameter for a Size menu value. Those values date from when the
    /// emblem filled 83% of its window; keeping that ratio keeps the lantern
    /// the same size on screen now that the window carries more padding.
    static func emblemDiameter(forSize size: CGFloat) -> CGFloat { size * 0.83 }

    /// Side of the square canvas that draws an emblem of diameter `d`.
    static func canvasSide(forEmblemDiameter d: CGFloat) -> CGFloat {
        (d / (1 - glowPadding)).rounded()
    }

    /// Canvas rect, centred on `c`, that draws an emblem of diameter `d`.
    static func canvas(center c: CGPoint, emblemDiameter d: CGFloat) -> CGRect {
        let side = d / (1 - glowPadding)
        return CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
    }

    // MARK: - Path construction

    /// The complete emblem (ring + figure) as a single non-zero-winding path.
    /// Sub-paths are wound deliberately: counter-clockwise adds material,
    /// clockwise punches holes, so the bars can overlap the hub without the
    /// overlap cancelling out the way an even-odd fill would.
    /// Below this emblem radius the fine detail — the Green Lantern's brackets,
    /// the Sinestro band's gaps — is thinner than a pixel or two and turns to
    /// mush, so `path` falls back to a coarser figure. Chiefly the menu-bar icon.
    static let detailThreshold: CGFloat = 16

    static func isSimplified(in rect: CGRect) -> Bool {
        min(rect.width, rect.height) / 2 * (1 - glowPadding) < detailThreshold
    }

    static func path(in rect: CGRect, emblem: Emblem) -> CGPath {
        let radius = min(rect.width, rect.height) / 2 * (1 - glowPadding)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let p = CGMutablePath()

        /// Unit coordinates — origin at the emblem's centre, 1.0 its radius —
        /// mapped onto the rect.
        func unit(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: c.x + x * radius, y: c.y + y * radius)
        }

        /// `dy` drops the circle below the emblem's centre, for the Red
        /// Lantern hub.
        func disc(_ r: CGFloat, hole: Bool, dy: CGFloat = 0) {
            let o = unit(0, dy)
            // Without an explicit move, addArc joins to the previous subpath's
            // current point and draws a chord straight across the emblem.
            p.move(to: CGPoint(x: o.x + r * radius, y: o.y))
            p.addArc(center: o, radius: r * radius,
                     startAngle: hole ? 2 * .pi : 0,
                     endAngle: hole ? 0 : 2 * .pi,
                     clockwise: hole)
            p.closeSubpath()
        }

        func bar(minY: CGFloat, maxY: CGFloat) {
            let x0 = c.x - barHalfWidth * radius, x1 = c.x + barHalfWidth * radius
            let y0 = c.y + minY * radius, y1 = c.y + maxY * radius
            // Counter-clockwise: right along the bottom, up, left, down.
            p.move(to: CGPoint(x: x0, y: y0))
            p.addLine(to: CGPoint(x: x1, y: y0))
            p.addLine(to: CGPoint(x: x1, y: y1))
            p.addLine(to: CGPoint(x: x0, y: y1))
            p.closeSubpath()
        }

        /// One annular wedge, angles in degrees: out along the outer arc,
        /// across, back along the inner arc. A closed band, so it adds material
        /// under non-zero winding wherever it overlaps its neighbours. `dy`
        /// drops the centre it is struck from, for the White Lantern crescent.
        func wedge(from d0: CGFloat, to d1: CGFloat, inner: CGFloat, outer: CGFloat,
                   dy: CGFloat = 0) {
            let o = unit(0, dy)
            let a0 = d0 * .pi / 180, a1 = d1 * .pi / 180
            func point(_ r: CGFloat, _ a: CGFloat) -> CGPoint {
                CGPoint(x: o.x + cos(a) * r * radius, y: o.y + sin(a) * r * radius)
            }
            p.move(to: point(outer, a0))
            p.addArc(center: o, radius: outer * radius,
                     startAngle: a0, endAngle: a1, clockwise: false)
            p.addLine(to: point(inner, a1))
            p.addArc(center: o, radius: inner * radius,
                     startAngle: a1, endAngle: a0, clockwise: true)
            p.closeSubpath()
        }

        /// One Red Lantern side bar: a vertical strip that jogs outward
        /// partway up, its ends cut on `redCapRadius` so they finish inside
        /// the ring. `side` is +1 for the right bar and -1 for the left; the
        /// left one's vertices are mirrored *and* reversed, so both wind
        /// counter-clockwise and both add material.
        func redBar(side: CGFloat, simple: Bool) {
            let i0 = redBarInner + (simple ? 0.020 : 0)
            let w = redBarWidth + (simple ? 0.030 : 0)
            let i1 = redBarInnerTop, o0 = i0 + w, o1 = i1 + w
            func capHeight(_ u: CGFloat) -> CGFloat {
                (redCapRadius * redCapRadius - u * u).squareRoot()
            }
            let bottom = -capHeight(o0), top = capHeight(simple ? o0 : o1)
            var pts = [CGPoint(x: i0, y: bottom), CGPoint(x: o0, y: bottom)]
            if simple {
                // The jog is under a pixel at menu-bar size; one straight bar.
                pts += [CGPoint(x: o0, y: top), CGPoint(x: i0, y: top)]
            } else {
                pts += [CGPoint(x: o0, y: redJogLow), CGPoint(x: o1, y: redJogHigh),
                        CGPoint(x: o1, y: top), CGPoint(x: i1, y: top),
                        CGPoint(x: i1, y: redJogHigh), CGPoint(x: i0, y: redJogLow)]
            }
            if side < 0 { pts = pts.reversed().map { CGPoint(x: -$0.x, y: $0.y) } }
            p.move(to: unit(pts[0].x, pts[0].y))
            for q in pts.dropFirst() { p.addLine(to: unit(q.x, q.y)) }
            p.closeSubpath()
        }

        /// One Orange Lantern spoke: a bar of constant width along `degrees`,
        /// running from `r0` out to the cap radius. Wound counter-clockwise
        /// whatever its angle, so the two that cross at the centre pile up
        /// rather than cancelling.
        func spoke(_ degrees: CGFloat, from r0: CGFloat, half: CGFloat) {
            let a = degrees * .pi / 180
            let dx = cos(a), dy = sin(a), nx = -sin(a), ny = cos(a)
            func corner(_ r: CGFloat, _ side: CGFloat) -> CGPoint {
                unit(dx * r + nx * half * side, dy * r + ny * half * side)
            }
            p.move(to: corner(r0, -1))
            p.addLine(to: corner(orangeCapRadius, -1))
            p.addLine(to: corner(orangeCapRadius, 1))
            p.addLine(to: corner(r0, 1))
            p.closeSubpath()
        }

        /// The Orange Lantern chevron: two arms meeting at a corner, drawn as
        /// one hexagon so the point comes out mitred rather than blunt.
        func chevron(half: CGFloat) {
            let phi = (90 - orangeSteepSpokes[1]) * .pi / 180   // off vertical
            let dx = sin(phi), dy = cos(phi)
            let c0 = orangeChevronCorner, arm = orangeChevronArm
            let miter = half / sin(phi)
            /// An arm's end corner: `sx` picks the arm, `side` the edge.
            func end(_ sx: CGFloat, _ side: CGFloat) -> CGPoint {
                unit(sx * (arm * dx - side * half * dy), c0 + arm * dy + side * half * dx)
            }
            p.move(to: unit(0, c0 - miter))     // the point
            p.addLine(to: end(1, -1))           // up the right arm's outer edge
            p.addLine(to: end(1, 1))            // across its end
            p.addLine(to: unit(0, c0 + miter))  // down to the inner mitre
            p.addLine(to: end(-1, 1))           // up the left arm's inner edge
            p.addLine(to: end(-1, -1))          // across its end
            p.closeSubpath()
        }

        /// One grille bar: a straight strip whose top is cut by the dome the
        /// five of them share.
        func grilleBar(from x0: CGFloat, to x1: CGFloat, half: CGFloat) {
            func top(_ x: CGFloat) -> CGFloat {
                max(0, blackBarDome * blackBarDome - x * x).squareRoot()
            }
            p.move(to: unit(x0, blackBarFoot))
            p.addLine(to: unit(x1, blackBarFoot))
            p.addLine(to: unit(x1, top(x1)))
            // Counter-clockwise along the dome, back to the left edge's top.
            p.addArc(center: c, radius: blackBarDome * radius,
                     startAngle: atan2(top(x1), x1), endAngle: atan2(top(x0), x0),
                     clockwise: false)
            p.closeSubpath()
        }

        /// One spike of the White Lantern's fan. Its axis runs out from the
        /// aiming point, so the seven of them converge on the triangle; the
        /// spike itself is the stretch of that axis from the foot line — where
        /// it comes to a point — out to a base buried in the ring.
        func ray(at degrees: CGFloat, half: CGFloat, foot: CGFloat) {
            let a = degrees * .pi / 180
            let dx = cos(a), dy = sin(a), nx = -dy, ny = dx
            let aim = whiteRayAim
            // Along the axis: this spike's own foot first, then the ring.
            let toFoot = (foot - aim) / dy
            let toBase = (-2 * aim * dy
                + (4 * aim * aim * dy * dy
                   - 4 * (aim * aim - whiteRayBase * whiteRayBase)).squareRoot()) / 2
            p.move(to: unit(dx * toFoot, aim + dy * toFoot))
            p.addLine(to: unit(dx * toBase - nx * half, aim + dy * toBase - ny * half))
            p.addLine(to: unit(dx * toBase + nx * half, aim + dy * toBase + ny * half))
            p.closeSubpath()
        }

        /// An inverted triangle drawn as an outline — an outer shape with a
        /// hollow punched through it. Both the Black and the White Lantern
        /// figures end in one; only the proportions differ.
        func hollowTriangle(top: CGFloat, half: CGFloat, cut: CGFloat, cutHalf: CGFloat,
                            hollowTop: CGFloat, hollowHalf: CGFloat, hollowApex: CGFloat,
                            shrink: CGFloat) {
            p.move(to: unit(-half, top))
            p.addLine(to: unit(-cutHalf, cut))
            p.addLine(to: unit(cutHalf, cut))
            p.addLine(to: unit(half, top))
            p.closeSubpath()
            // Clockwise, which punches it through.
            p.move(to: unit(-hollowHalf + shrink, hollowTop + shrink))
            p.addLine(to: unit(hollowHalf - shrink, hollowTop + shrink))
            p.addLine(to: unit(0, hollowApex - shrink))
            p.closeSubpath()
        }

        /// A band broken at the given places, drawn as the arcs between them.
        /// `widen` opens every break, for the simplified figure.
        func brokenBand(_ gaps: [(centre: CGFloat, half: CGFloat)],
                        inner: CGFloat, outer: CGFloat, widen: CGFloat) {
            let sorted = gaps.sorted { $0.centre < $1.centre }
            for (i, gap) in sorted.enumerated() {
                let next = sorted[(i + 1) % sorted.count]
                let start = gap.centre + gap.half + widen
                var end = next.centre - next.half - widen
                if end < start { end += 360 }
                wedge(from: start, to: end, inner: inner, outer: outer)
            }
        }

        /// Arms carrying a band out to the ring and joining it there. They
        /// overlap both, so the joins vanish under non-zero winding rather
        /// than leaving seams.
        func armsToRing(_ arms: [(centre: CGFloat, half: CGFloat)],
                        from inner: CGFloat, widen: CGFloat) {
            for arm in arms {
                wedge(from: arm.centre - arm.half - widen,
                      to: arm.centre + arm.half + widen,
                      inner: inner, outer: armOuter)
            }
        }

        /// The Star Sapphire's eight-pointed star, as one closed polygon:
        /// sixteen vertices, tip and valley alternating.
        func star(long: CGFloat, short: CGFloat, valley: CGFloat, offset: CGFloat) {
            var first = true
            for quadrant in 0..<4 {
                let base = CGFloat(quadrant) * 90
                for (degrees, r) in [(base, long), (base + 45 - offset, valley),
                                     (base + 45, short), (base + 45 + offset, valley)] {
                    let a = degrees * .pi / 180
                    let point = unit(cos(a) * r, sin(a) * r)
                    if first { p.move(to: point); first = false } else { p.addLine(to: point) }
                }
            }
            p.closeSubpath()
        }

        /// The star's eye, wound clockwise so it punches through.
        func ellipseHole(width: CGFloat, height: CGFloat) {
            let steps = 72
            p.move(to: unit(width, 0))
            for i in stride(from: steps - 1, through: 0, by: -1) {
                let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
                p.addLine(to: unit(cos(t) * width, sin(t) * height))
            }
            p.closeSubpath()
        }

        /// One of the Indigo Tribe's chevrons: a mitred point whose arms run
        /// down at 45° and stop square. `up` gives the one above the hub; the
        /// one below is its mirror, traversed backwards so both wind the same
        /// way and both add material.
        func indigoChevron(up: Bool, half: CGFloat) {
            let corner = indigoChevronCorner, foot = indigoChevronFoot
            let mitre = half * (2 as CGFloat).squareRoot()
            let reach = corner - foot
            var pts = [
                CGPoint(x: 0, y: corner + mitre),        // the point
                CGPoint(x: -(reach + mitre), y: foot),   // left arm, outer edge
                CGPoint(x: -(reach - mitre), y: foot),   // across its foot
                CGPoint(x: 0, y: corner - mitre),        // the inner mitre
                CGPoint(x: reach - mitre, y: foot),      // right arm, inner edge
                CGPoint(x: reach + mitre, y: foot),      // across its foot
            ]
            if !up { pts = pts.reversed().map { CGPoint(x: $0.x, y: -$0.y) } }
            p.move(to: unit(pts[0].x, pts[0].y))
            for q in pts.dropFirst() { p.addLine(to: unit(q.x, q.y)) }
            p.closeSubpath()
        }

        let simple = isSimplified(in: rect)
        disc(1.0, hole: false)          // outer ring, outer edge
        disc(ringInner, hole: true)     // outer ring, inner edge

        switch emblem {
        case .green:
            // Simplified: one chunky hub that reaches the bars, standing in for
            // the hub and brackets together.
            disc(simple ? shoulderOuter : hubOuter, hole: false)
            disc(simple ? hubInner * 0.92 : hubInner, hole: true)
            bar(minY: barInnerY, maxY: barOuterY)
            bar(minY: -barOuterY, maxY: -barInnerY)
            if !simple {
                // Brackets down each side: the same annular wedge as the
                // Sinestro band, swept wide enough to finish inside the bars.
                let sweep = shoulderSweep * 180 / .pi
                wedge(from: -sweep, to: sweep,
                      inner: shoulderInner, outer: shoulderOuter)     // right
                wedge(from: 180 - sweep, to: 180 + sweep,
                      inner: shoulderInner, outer: shoulderOuter)     // left
            }

        case .sinestro:
            // Simplified: a fatter hub and band, wider breaks and wider arms,
            // so none of the figure falls under a pixel at menu-bar size.
            let bandIn = bandInner - (simple ? 0.025 : 0)
            let bandOut = bandOuter + (simple ? 0.025 : 0)
            let widen: CGFloat = simple ? 3 : 0

            // Simplified: a thicker border, since the true one is about a
            // pixel at menu-bar size.
            disc(sinestroHubOuter + (simple ? 0.025 : 0), hole: false)
            disc(sinestroHubInner - (simple ? 0.030 : 0), hole: true)

            brokenBand(sinestroBandGaps, inner: bandIn, outer: bandOut, widen: widen)
            armsToRing(sinestroArms, from: bandIn, widen: widen)

        case .blue:
            // Built like the Sinestro figure, with more of everything: six
            // breaks in the band instead of four, and four finer arms.
            let blueBandIn = blueBandInner - (simple ? 0.025 : 0)
            let blueBandOut = blueBandOuter + (simple ? 0.025 : 0)
            let blueWiden: CGFloat = simple ? 3 : 0
            disc(blueHubOuter + (simple ? 0.025 : 0), hole: false)
            disc(blueHubInner - (simple ? 0.030 : 0), hole: true)
            brokenBand(blueBandGaps, inner: blueBandIn, outer: blueBandOut,
                       widen: blueWiden)
            // Widened more than the Sinestro arms: at four degrees they are
            // under a pixel at menu-bar size.
            armsToRing(blueArms, from: blueBandIn, widen: simple ? 5 : 0)

        case .sapphire:
            // Simplified: a blunter star — the valleys pulled out and the eye
            // shrunk — so the points don't thin to nothing at menu-bar size.
            star(long: sapphireLong, short: sapphireShort,
                 valley: sapphireValley + (simple ? 0.045 : 0),
                 offset: sapphireValleyOffset)
            ellipseHole(width: sapphireEyeWidth - (simple ? 0.030 : 0),
                        height: sapphireEyeHeight - (simple ? 0.030 : 0))

        case .indigo:
            // Simplified: a thicker hub border and fatter chevrons.
            disc(indigoHubOuter + (simple ? 0.022 : 0), hole: false)
            disc(indigoHubInner - (simple ? 0.026 : 0), hole: true)
            let chevron = indigoChevronHalf + (simple ? 0.022 : 0)
            indigoChevron(up: true, half: chevron)
            indigoChevron(up: false, half: chevron)

        case .red:
            // Simplified: a slightly thicker hub, to go with the wider bars.
            disc(redHubOuter + (simple ? 0.022 : 0), hole: false, dy: -redHubDrop)
            disc(redHubInner - (simple ? 0.020 : 0), hole: true, dy: -redHubDrop)
            // The hub reaches past the bars' inner edges and overlaps them,
            // which non-zero winding merges; its bore clears them entirely, so
            // it stays a hole.
            redBar(side: 1, simple: simple)
            redBar(side: -1, simple: simple)

        case .orange:
            // Simplified: a thicker hub and fatter spokes. Six of them is a lot
            // to fit at menu-bar size, and thin ones turn to grey mush.
            let hubIn = orangeHubInner - (simple ? 0.028 : 0)
            let hubOut = orangeHubOuter + (simple ? 0.028 : 0)
            let half = orangeSpokeHalf + (simple ? 0.026 : 0)
            disc(hubOut, hole: false)
            disc(hubIn, hole: true)
            // All six start buried in the hub's band, so their inner ends never
            // show; the chevron carries the steep pair on into the bore.
            for angle in orangeOuterSpokes + orangeSteepSpokes {
                spoke(angle, from: (hubIn + hubOut) / 2, half: half)
            }
            chevron(half: orangeChevronHalf + (simple ? 0.022 : 0))

        case .black:
            // Simplified: fatter bars and a smaller hollow, so neither the
            // grille nor the triangle's outline thins to nothing.
            let half = blackBarHalf + (simple ? 0.022 : 0)
            for i in -2...2 {
                let centre = CGFloat(i) * blackBarPitch
                grilleBar(from: centre - half, to: centre + half, half: half)
            }
            hollowTriangle(top: blackTriangleTop, half: blackTriangleHalf,
                           cut: blackTriangleCut, cutHalf: blackTriangleCutHalf,
                           hollowTop: blackHollowTop, hollowHalf: blackHollowHalf,
                           hollowApex: blackHollowApex, shrink: simple ? 0.055 : 0)

        case .white:
            // Simplified: fatter spikes, a thicker crescent and a smaller
            // hollow. Seven rays is a lot to fit at menu-bar size.
            let half = whiteRayHalf + (simple ? 0.030 : 0)
            for k in -3...3 {
                let out = CGFloat(abs(k))
                ray(at: 90 + CGFloat(k) * whiteRayStep,
                    half: half * (1 - whiteRayTaper * out),
                    foot: whiteRayFoot - whiteRayStagger * out)
            }
            let spread = simple ? 0.030 : 0
            wedge(from: whiteCrescentSpan, to: 180 - whiteCrescentSpan,
                  inner: whiteCrescentInner - spread, outer: whiteCrescentOuter,
                  dy: -whiteCrescentDrop)
            hollowTriangle(top: whiteTriangleTop, half: whiteTriangleHalf,
                           cut: whiteTriangleCut, cutHalf: whiteTriangleCutHalf,
                           hollowTop: whiteHollowTop, hollowHalf: whiteHollowHalf,
                           hollowApex: whiteHollowApex, shrink: simple ? 0.055 : 0)
        }
        return p
    }

    /// The emblem's outline, with its internal seams removed.
    ///
    /// `path(in:emblem:)` is a pile of deliberately overlapping sub-paths, so
    /// stroking it draws every internal boundary too: the bracket end faces
    /// buried inside the bars, the hub circle where it crosses them, the spokes
    /// where they meet the band. Normalising merges the overlaps and leaves
    /// only the true outline and the holes.
    ///
    /// Cached, because normalising is far too slow to redo every frame.
    static func outline(in rect: CGRect, emblem: Emblem) -> CGPath {
        if let cached = outlineCache, cached.rect == rect, cached.emblem == emblem {
            return cached.path
        }
        let merged = path(in: rect, emblem: emblem).normalized(using: .winding)
        outlineCache = (rect, emblem, merged)
        return merged
    }
    private static var outlineCache: (rect: CGRect, emblem: Emblem, path: CGPath)?

    /// The hub's bore — a hole in the emblem, and where the core detail goes.
    /// The Red Lantern's sits below the emblem's centre, so this returns a
    /// centre as well as a radius and callers must not assume the middle.
    static func hubCore(in rect: CGRect, emblem: Emblem) -> (center: CGPoint, radius: CGFloat) {
        let radius = min(rect.width, rect.height) / 2 * (1 - glowPadding)
        let middle = CGPoint(x: rect.midX, y: rect.midY)
        switch emblem {
        case .green:    return (middle, hubInner * radius)
        case .sinestro: return (middle, sinestroHubInner * radius)
        case .blue:     return (middle, blueHubInner * radius)
        // The eye is an ellipse; the engraved core takes the circle inside it.
        case .sapphire: return (middle, sapphireEyeWidth * radius)
        case .indigo:   return (middle, indigoHubInner * radius)
        case .red:      return (CGPoint(x: middle.x, y: middle.y - redHubDrop * radius),
                                redHubInner * radius)
        case .orange:   return (middle, orangeHubInner * radius)
        // The Black Lantern figure has no bore: its middle is the band across
        // the triangle's top. A zero radius is how the core and the glint know
        // there is nowhere to sit.
        case .black:    return (middle, 0)
        case .white:    return (middle, 0)   // nor does the fan
        }
    }

    /// Bounding box of the drawn emblem inside `rect` — the fill level is
    /// measured against this, not the full view.
    static func emblemBounds(in rect: CGRect) -> CGRect {
        let radius = min(rect.width, rect.height) / 2 * (1 - glowPadding)
        return CGRect(x: rect.midX - radius, y: rect.midY - radius,
                      width: radius * 2, height: radius * 2)
    }

    // MARK: - Palette

    struct Palette {
        var bright: NSColor
        var deep: NSColor
        var ember: NSColor   // unlit portion of the emblem
        /// The figure that goes with this light: yellow is Sinestro's, red
        /// the Red Lantern Corps'.
        var emblem: Emblem = .green
    }

    /// The corps the charge alone would choose. Orange is never among them —
    /// it is reached only by swearing its oath.
    ///
    /// The black threshold is written against the *shown* percentage rather
    /// than the raw level: the caption rounds, so anything under 0.015 reads
    /// as 1% or 0%, and the emblem should turn exactly when the number does.
    static func corps(level: Double, charging: Bool) -> Emblem {
        // A full charge is the White Lantern's, plugged in or not — the same
        // 0.995 the widget already treats as full.
        if level >= 0.995 { return .white }
        if !charging && level <= 0.015 { return .black }
        if !charging && level <= 0.10 { return .red }
        if !charging && level <= 0.20 { return .sinestro }
        return .green
    }

    /// One corps' colours.
    static func palette(for emblem: Emblem) -> Palette {
        switch emblem {
        case .red:
            return Palette(bright: NSColor(srgbRed: 1.00, green: 0.30, blue: 0.26, alpha: 1),
                           deep:   NSColor(srgbRed: 0.62, green: 0.09, blue: 0.08, alpha: 1),
                           ember:  NSColor(srgbRed: 0.16, green: 0.04, blue: 0.04, alpha: 1),
                           emblem: .red)
        case .sinestro:
            return Palette(bright: NSColor(srgbRed: 1.00, green: 0.74, blue: 0.16, alpha: 1),
                           deep:   NSColor(srgbRed: 0.60, green: 0.36, blue: 0.03, alpha: 1),
                           ember:  NSColor(srgbRed: 0.15, green: 0.10, blue: 0.02, alpha: 1),
                           emblem: .sinestro)
        case .orange:
            return Palette(bright: NSColor(srgbRed: 1.00, green: 0.58, blue: 0.13, alpha: 1),
                           deep:   NSColor(srgbRed: 0.64, green: 0.29, blue: 0.02, alpha: 1),
                           ember:  NSColor(srgbRed: 0.17, green: 0.08, blue: 0.01, alpha: 1),
                           emblem: .orange)
        case .black:
            // A corps whose colour is the absence of one. Drawn in cold greys
            // rather than true black, which on a dark desktop would be an
            // emblem you couldn't see at all: the light has gone out of it,
            // not the lantern out of the wallpaper.
            return Palette(bright: NSColor(srgbRed: 0.86, green: 0.88, blue: 0.94, alpha: 1),
                           deep:   NSColor(srgbRed: 0.45, green: 0.46, blue: 0.54, alpha: 1),
                           ember:  NSColor(srgbRed: 0.24, green: 0.24, blue: 0.29, alpha: 1),
                           emblem: .black)
        case .white:
            // Kept just off true white, and with an ember light enough to read:
            // an emblem this pale needs its unlit parts to survive a pale
            // wallpaper as much as the black one needed to survive a dark one.
            return Palette(bright: NSColor(srgbRed: 1.00, green: 0.99, blue: 0.96, alpha: 1),
                           deep:   NSColor(srgbRed: 0.52, green: 0.55, blue: 0.64, alpha: 1),
                           ember:  NSColor(srgbRed: 0.33, green: 0.34, blue: 0.40, alpha: 1),
                           emblem: .white)
        case .blue:
            return Palette(bright: NSColor(srgbRed: 0.24, green: 0.62, blue: 1.00, alpha: 1),
                           deep:   NSColor(srgbRed: 0.02, green: 0.25, blue: 0.62, alpha: 1),
                           ember:  NSColor(srgbRed: 0.03, green: 0.08, blue: 0.19, alpha: 1),
                           emblem: .blue)
        case .sapphire:
            return Palette(bright: NSColor(srgbRed: 0.90, green: 0.35, blue: 0.82, alpha: 1),
                           deep:   NSColor(srgbRed: 0.48, green: 0.09, blue: 0.44, alpha: 1),
                           ember:  NSColor(srgbRed: 0.16, green: 0.03, blue: 0.15, alpha: 1),
                           emblem: .sapphire)
        case .indigo:
            return Palette(bright: NSColor(srgbRed: 0.44, green: 0.34, blue: 0.92, alpha: 1),
                           deep:   NSColor(srgbRed: 0.20, green: 0.13, blue: 0.50, alpha: 1),
                           ember:  NSColor(srgbRed: 0.07, green: 0.05, blue: 0.18, alpha: 1),
                           emblem: .indigo)
        case .green:
            return Palette(bright: NSColor(srgbRed: 0.24, green: 0.95, blue: 0.40, alpha: 1),
                           deep:   NSColor(srgbRed: 0.02, green: 0.52, blue: 0.16, alpha: 1),
                           ember:  NSColor(srgbRed: 0.04, green: 0.17, blue: 0.08, alpha: 1),
                           emblem: .green)
        }
    }

    /// The lantern's colours. `sworn` is the corps whose oath was spoken: it
    /// overrides the charge entirely until the lantern is sealed again.
    static func palette(level: Double, charging: Bool, sworn: Emblem? = nil) -> Palette {
        palette(for: sworn ?? corps(level: level, charging: charging))
    }
}
