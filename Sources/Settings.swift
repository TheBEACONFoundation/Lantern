import AppKit

/// UserDefaults-backed preferences. `onChange` fires after any mutation so the
/// window and menu can re-sync from a single place.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    var onChange: (() -> Void)?

    private enum Key {
        static let size = "emblemSize"
        static let originX = "originX"
        static let originY = "originY"
        static let hasOrigin = "hasOrigin"
        static let centerX = "centerX"
        static let centerY = "centerY"
        static let hasCenter = "hasCenter"
        static let showOnDesktop = "showOnDesktop"
        static let floatAbove = "floatAboveWindows"
        static let locked = "lockPosition"
        static let showPercent = "showPercent"
        static let menuBarPercent = "menuBarPercent"
        static let opacity = "opacity"
        static let oathListening = "oathListening"
        static let particles = "particleEffects"
    }

    private init() {
        defaults.register(defaults: [
            Key.size: 190.0,
            Key.showOnDesktop: true,
            Key.floatAbove: false,
            Key.locked: false,
            Key.showPercent: true,
            Key.menuBarPercent: true,
            Key.opacity: 1.0,
            Key.oathListening: false,
            Key.particles: true,
        ])
    }

    private func set(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }

    var size: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.size)) }
        set { set(Double(newValue), Key.size) }
    }
    var showOnDesktop: Bool {
        get { defaults.bool(forKey: Key.showOnDesktop) }
        set { set(newValue, Key.showOnDesktop) }
    }
    var floatAboveWindows: Bool {
        get { defaults.bool(forKey: Key.floatAbove) }
        set { set(newValue, Key.floatAbove) }
    }
    var lockPosition: Bool {
        get { defaults.bool(forKey: Key.locked) }
        set { set(newValue, Key.locked) }
    }
    var showPercent: Bool {
        get { defaults.bool(forKey: Key.showPercent) }
        set { set(newValue, Key.showPercent) }
    }
    var menuBarPercent: Bool {
        get { defaults.bool(forKey: Key.menuBarPercent) }
        set { set(newValue, Key.menuBarPercent) }
    }
    var oathListening: Bool {
        get { defaults.bool(forKey: Key.oathListening) }
        set { set(newValue, Key.oathListening) }
    }
    var particleEffects: Bool {
        get { defaults.bool(forKey: Key.particles) }
        set { set(newValue, Key.particles) }
    }
    var opacity: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.opacity)) }
        set { set(Double(newValue), Key.opacity) }
    }

    /// Saved centre of the emblem, or nil the first time the app runs.
    ///
    /// The centre is stored rather than the window origin so the window's size
    /// and padding can change without moving the lantern.
    var center: CGPoint? {
        get {
            if defaults.bool(forKey: Key.hasCenter) {
                return CGPoint(x: defaults.double(forKey: Key.centerX),
                               y: defaults.double(forKey: Key.centerY))
            }
            // Earlier builds saved the window origin, with the emblem filling a
            // `size`-wide square at the top of a window `size + caption` tall.
            guard defaults.bool(forKey: Key.hasOrigin) else { return nil }
            let side = Double(size)
            let caption = showPercent ? side * 0.18 : 0
            return CGPoint(x: defaults.double(forKey: Key.originX) + side / 2,
                           y: defaults.double(forKey: Key.originY) + caption + side / 2)
        }
        set {
            // Deliberately no onChange: moving the window shouldn't re-lay it out.
            guard let newValue else {
                defaults.set(false, forKey: Key.hasCenter)
                defaults.set(false, forKey: Key.hasOrigin)
                return
            }
            defaults.set(true, forKey: Key.hasCenter)
            defaults.set(Double(newValue.x), forKey: Key.centerX)
            defaults.set(Double(newValue.y), forKey: Key.centerY)
        }
    }
}
