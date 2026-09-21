import AppKit

// Custom rows for the status menu, in the style of Apple's own menu-bar
// extras (Wi-Fi, Sound, Control Center): a header card, a switch row, and
// slider rows. Everything uses system fonts and semantic colours, so it tracks
// light and dark mode and the accent colour like Apple's menus do.

/// Width of the menu's custom rows; it sets the menu's width too.
let menuRowWidth: CGFloat = 300
/// Apple's menu rows inset their content by 14pt.
private let inset: CGFloat = 14

private func label(_ size: CGFloat, _ weight: NSFont.Weight = .regular,
                   _ color: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(labelWithString: "")
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    return l
}

private func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: weight))
}

// MARK: - Header

/// The battery at a glance: the lantern, the percentage in large rounded
/// figures, what it's doing, a charge bar, and a row of vitals.
final class BatteryHeaderView: NSView {
    private let emblem = NSImageView()
    private let title = label(26, .semibold)
    private let subtitle = label(12, .regular, .secondaryLabelColor)
    private let badge = NSImageView()
    private let bar = ChargeBar()
    private let stats = NSStackView()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 120))
        if let rounded = NSFont.systemFont(ofSize: 26, weight: .semibold)
            .fontDescriptor.withDesign(.rounded).flatMap({ NSFont(descriptor: $0, size: 26) }) {
            title.font = rounded
        }
        emblem.frame = NSRect(x: inset, y: 12, width: 42, height: 42)
        title.frame = NSRect(x: 66, y: 9, width: 170, height: 32)
        subtitle.frame = NSRect(x: 67, y: 39, width: menuRowWidth - 67 - inset, height: 16)
        badge.frame = NSRect(x: menuRowWidth - inset - 22, y: 16, width: 22, height: 22)
        bar.frame = NSRect(x: inset, y: 66, width: menuRowWidth - inset * 2, height: 6)
        stats.frame = NSRect(x: inset, y: 82, width: menuRowWidth - inset * 2, height: 30)
        stats.orientation = .horizontal
        stats.distribution = .fillEqually
        stats.alignment = .top
        [emblem, title, subtitle, badge, bar, stats].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(info: BatteryInfo, emblemImage: NSImage, tint: NSColor) {
        emblem.image = emblemImage
        title.stringValue = info.hasBattery ? "\(info.percent)%" : "Power Adapter"
        subtitle.stringValue = info.statusLine.replacingOccurrences(of: " — ", with: " · ")

        if info.isCharging {
            badge.image = symbol("bolt.fill", 15, .semibold)
            badge.contentTintColor = tint
        } else if info.isPluggedIn {
            badge.image = symbol("powerplug.fill", 14, .medium)
            badge.contentTintColor = .secondaryLabelColor
        } else {
            badge.image = nil
        }

        bar.level = info.hasBattery ? info.level : 1
        bar.tint = tint
        bar.isHidden = !info.hasBattery

        stats.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var vitals: [(String, String)] = []
        if let h = info.healthPercent { vitals.append(("\(h)%", "Health")) }
        if let c = info.cycleCount { vitals.append(("\(c)", "Cycles")) }
        if let t = info.temperatureC { vitals.append((String(format: "%.0f °C", t), "Temperature")) }
        if let w = info.wattage, abs(w) > 0.05 {
            vitals.append((String(format: "%.1f W", abs(w)), w > 0 ? "Input" : "Draw"))
        }
        for (value, name) in vitals { stats.addArrangedSubview(Stat(value: value, name: name)) }

        setAccessibilityLabel("Battery \(title.stringValue), \(subtitle.stringValue)")
    }

    /// One vital: the figure, and what it is beneath it.
    private final class Stat: NSView {
        init(value: String, name: String) {
            super.init(frame: .zero)
            let v = label(13, .semibold)
            let n = label(10, .regular, .secondaryLabelColor)
            v.stringValue = value
            n.stringValue = name
            let stack = NSStackView(views: [v, n])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 1
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError("not used") }
    }
}

/// A rounded capacity bar, filled in the lantern's current colour.
final class ChargeBar: NSView {
    var level: Double = 1 { didSet { needsDisplay = true } }
    var tint: NSColor = .systemGreen { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let width = max(bounds.height, bounds.width * CGFloat(max(0, min(1, level))))
        tint.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height),
                     xRadius: radius, yRadius: radius).fill()
    }
}

// MARK: - The oath

/// The lantern's state as a Control Center-style row: a round badge, a title
/// and status line, and a switch for listening.
final class OathRowView: NSView {
    private let badge = NSView()
    private let glyph = NSImageView()
    private let title = label(13, .medium)
    private let detail = label(11, .regular, .secondaryLabelColor)
    let toggle = NSSwitch()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 46))
        badge.frame = NSRect(x: inset, y: 8, width: 30, height: 30)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 15
        glyph.frame = badge.bounds
        glyph.imageScaling = .scaleNone
        badge.addSubview(glyph)

        toggle.controlSize = .small
        toggle.sizeToFit()
        toggle.frame.origin = NSPoint(x: menuRowWidth - inset - toggle.frame.width,
                                      y: (46 - toggle.frame.height) / 2)
        toggle.setAccessibilityLabel("Listen for the Oath")

        let textX: CGFloat = inset + 30 + 10
        let textWidth = toggle.frame.minX - 10 - textX
        title.frame = NSRect(x: textX, y: 6, width: textWidth, height: 17)
        detail.frame = NSRect(x: textX, y: 23, width: textWidth, height: 15)
        [badge, title, detail, toggle].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(open: Bool, detail text: String, corps: String?,
                listening: Bool, tint: NSColor) {
        title.stringValue = open ? (corps ?? "Open") : "Sealed"
        detail.stringValue = text
        detail.toolTip = text
        // Like Control Center: on, a white glyph on the colour; off, the label
        // colour on a neutral fill, so it reads in light and dark mode alike.
        // A layer takes a fixed CGColor, so resolve it in this view's appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            badge.layer?.backgroundColor = (open ? tint : NSColor.tertiaryLabelColor).cgColor
        }
        glyph.image = symbol(open ? "lock.open.fill" : "lock.fill", 13, .semibold)
        glyph.contentTintColor = open ? .white : .labelColor
        toggle.state = listening ? .on : .off
    }
}

// MARK: - Sliders

/// A labelled slider row, like the Display and Sound sliders. The label sits
/// where menu item titles do — past the checkmark column — so it lines up
/// with the items around it. (This macOS draws no icons on menu items, so the
/// row carries none either.)
final class SliderRowView: NSView {
    let slider = NSSlider()

    /// Where NSMenu draws item titles in a menu with a checkmark column.
    static let titleX: CGFloat = 30

    override var isFlipped: Bool { true }

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 30))
        let name = label(13)
        name.stringValue = title
        // A label field insets its text by 2pt; back it off so the text lines up.
        name.frame = NSRect(x: Self.titleX - 2, y: 6, width: 70, height: 17)
        slider.controlSize = .small
        let sliderX = Self.titleX + 72
        slider.frame = NSRect(x: sliderX, y: 5, width: menuRowWidth - inset - sliderX,
                              height: 20)
        slider.setAccessibilityLabel(title)
        [name, slider].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
}
