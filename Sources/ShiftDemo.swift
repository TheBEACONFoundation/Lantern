import AppKit

/// Development aid: drives the desktop emblem through the corps shifts on a
/// loop, in a window of its own, so the transitions can be watched — and
/// captured — without waiting for the battery to actually drain.
///
/// `speed` scales Core Animation's clock for the emblem's layer tree, so the
/// same animations can be stepped through slowly. The motion is unchanged;
/// only its rate is.
///
/// Invoked via `Lantern --demo-shift [step-seconds] [speed]`.
enum ShiftDemo {

    /// What it walks: a charge level, and the corps an oath has sworn the
    /// lantern to (nil for none — the charge's own).
    ///
    /// The levels straddle the thresholds closely on purpose: in use the charge
    /// crosses a tier by a point or two, so a shift barely moves the fill, and
    /// a demo that jumped 55% → 16% would overstate how much it dissolves.
    private typealias Step = (level: Double, sworn: LanternGlyph.Emblem?, note: String)
    private static let script: [Step] = [
        (0.24, nil, "24% — green, on the charge's terms"),
        (1.00, nil, "100% — the charge reaches the White Lantern"),
        (0.24, nil, "24% — back down to green"),
        (0.17, nil, "17% — the charge crosses into Sinestro"),
        (0.07, nil, "7% — the charge crosses into Red Lantern"),
        (0.17, nil, "17% — charging back up into Sinestro"),
        (0.24, nil, "24% — back to green"),
        (0.24, .sinestro, "the Sinestro oath, sworn over a 24% charge"),
        (0.24, .red, "the Red Lantern oath, sworn over the same charge"),
        (0.24, .green, "the Green Lantern oath"),
        (0.24, .orange, "the Orange Lantern oath — a corps no charge can reach"),
        (0.24, .blue, "the Blue Lantern oath — the other corps only an oath reaches"),
        (0.24, .sapphire, "the Star Sapphire oath — the third of them"),
        (0.24, .indigo, "the Indigo Tribe's oath — the last of them"),
        (0.24, .white, "the White Lantern oath, sworn short of a full charge"),
        (0.24, .black, "the Black Lantern oath, sworn well clear of the last 1%"),
        (0.24, nil, "sealed — released back to the charge"),
        (0.07, nil, "7% — red, on the charge's terms"),
        (0.07, .green, "the Green Lantern oath, sworn over a flat battery"),
        (0.07, nil, "sealed — released back to red"),
        (0.01, nil, "1% — the charge falls to the Black Lantern"),
        (0.01, .green, "the Green Lantern oath, sworn over the last 1%"),
        (0.01, nil, "sealed — released back to black"),
    ]

    static func run(step: Double, speed: Double) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let side = LanternGlyph.canvasSide(
            forEmblemDiameter: LanternGlyph.emblemDiameter(forSize: 260))
        let lantern = LanternView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: side, height: side),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.contentView = lantern
        // A known spot on the main screen, so a capture script can find it.
        if let screen = NSScreen.main {
            window.setFrameOrigin(CGPoint(x: screen.frame.midX - side / 2,
                                          y: screen.frame.midY - side / 2))
        }
        window.orderFrontRegardless()
        lantern.layer?.speed = Float(speed)

        func info(_ level: Double) -> BatteryInfo {
            var i = BatteryInfo()
            i.hasBattery = true
            i.level = level
            return i
        }
        func apply(_ step: Step) {
            let before = lantern.swornCorps
            lantern.info = info(step.level)
            lantern.swornCorps = step.sworn
            // An oath calls this immediately after swearing, so the demo does
            // too — otherwise it would be showing the corps flourish alone and
            // not what an actual recitation looks like.
            if let sworn = step.sworn, sworn != before { lantern.triggerOathFlare() }
        }
        apply(script[0])

        let frame = window.frame
        print("window \(Int(frame.minX)) \(Int(frame.minY)) \(Int(frame.width)) \(Int(frame.height))")
        print("step \(step)s  speed \(speed)x  \(script.count) steps")
        fflush(stdout)

        var index = 0
        Timer.scheduledTimer(withTimeInterval: step, repeats: true) { _ in
            index = (index + 1) % script.count
            apply(script[index])
            print("[\(index)] \(script[index].note)")
            fflush(stdout)
        }
        app.run()
    }
}
