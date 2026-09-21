import AppKit

/// A transparent, borderless panel that sits on the desktop (or floats above
/// everything, if the user prefers). Non-activating so clicking it never steals
/// focus from whatever you're actually working in.
final class DesktopWindow: NSPanel {

    let lantern: LanternView

    init(size: CGSize) {
        lantern = LanternView(frame: CGRect(origin: .zero, size: size))
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        contentView = lantern
        applyLevel()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Desktop-icon level keeps the emblem on the wallpaper, behind real
    /// windows; floating puts it over everything.
    func applyLevel() {
        if Settings.shared.floatAboveWindows {
            level = .floating
        } else {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        }
    }

    /// The window is a square canvas much larger than the emblem, so the glow
    /// fades out completely before reaching the window edge. Resizing keeps
    /// the emblem's centre fixed, so the lantern doesn't crawl across the screen.
    func resizeEmblem(to size: CGFloat) {
        let side = LanternGlyph.canvasSide(
            forEmblemDiameter: LanternGlyph.emblemDiameter(forSize: size))
        let center = CGPoint(x: frame.midX, y: frame.midY)
        setFrame(CGRect(x: center.x - side / 2, y: center.y - side / 2,
                        width: side, height: side),
                 display: true)
        lantern.frame = CGRect(x: 0, y: 0, width: side, height: side)
    }

    /// Restore the saved emblem centre, falling back to the lower-right of the
    /// main screen. A centre whose emblem is off every screen (a monitor that
    /// went away) is re-anchored. Only the emblem is checked, not the padding.
    func restorePosition() {
        let visible = NSScreen.screens.map(\.visibleFrame)
        let d = LanternGlyph.emblemDiameter(forSize: Settings.shared.size)
        if let c = Settings.shared.center {
            let emblem = CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
            if visible.contains(where: { $0.intersects(emblem.insetBy(dx: 20, dy: 20)) }) {
                moveCenter(to: c)
                return
            }
        }
        guard let screen = NSScreen.main?.visibleFrame else { return }
        moveCenter(to: CGPoint(x: screen.maxX - 60 - d / 2,
                               y: screen.minY + 60 + d * 0.72))
    }

    /// Puts the emblem in the middle of the screen it is currently on, or the
    /// main screen if it isn't on any — which is the case most worth rescuing.
    /// Uses the screen's full frame, so "middle" is the literal middle rather
    /// than the middle of the area left over by the menu bar and Dock.
    func centerOnScreen() {
        let current = CGPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(current) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        moveCenter(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
    }

    private func moveCenter(to c: CGPoint) {
        setFrameOrigin(CGPoint(x: c.x - frame.width / 2, y: c.y - frame.height / 2))
    }
}
