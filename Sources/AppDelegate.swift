import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private let monitor = BatteryMonitor()
    private let oath = OathListener()
    private let charge = ChargeController()
    private var window: DesktopWindow!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private lazy var oathReference = OathReferenceWindowController()

    private let settings = Settings.shared

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        window = DesktopWindow(size: CGSize(width: settings.size, height: settings.size))
        window.delegate = self
        window.lantern.contextMenu = menu
        window.resizeEmblem(to: settings.size)
        window.restorePosition()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self   // drives menuWillOpen -> fresh readings
        buildMenu()

        oath.onAccepted = { [weak self] sworn in self?.oathAccepted(sworn) }
        oath.onStateChange = { [weak self] _ in self?.refreshMenuHeader() }
        charge.onChange = { [weak self] _ in
            self?.updateLanternGate()
            // The menu-bar icon draws the sworn corps too, so it follows the
            // gate rather than only the battery.
            self?.refreshStatusItem()
            self?.refreshMenuHeader()
        }
        updateLanternGate()

        settings.onChange = { [weak self] in self?.applySettings() }
        monitor.onChange = { [weak self] info in self?.apply(info) }
        monitor.start()

        apply(monitor.info)
        applySettings()

        if settings.oathListening { oath.start() }

        // `--snapshot-menu <file.png> [corps]`: opens the real menu, captures
        // it, quits. A development aid, like `--export-preview`, for checking
        // its design. The optional corps swears the lantern first — without
        // the microphone — so the menu can be checked in the state an oath
        // actually leaves it in: sworn, and no longer listening.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-menu"),
           i + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[i + 1]
            let corps = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : nil
            if let corps, let sworn = OathListener.oaths.first(where: {
                $0.name.lowercased().contains(corps.lowercased())
            }) {
                oathAccepted(sworn)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.snapshotMenu(to: path)
            }
        }
    }

    private func snapshotMenu(to path: String) {
        let capture = Timer(timeInterval: 0.8, repeats: false) { [weak self] _ in
            guard let self else { return }
            let mine = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                        as? [[String: Any]] ?? [])
                .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() }
                .filter { ($0[kCGWindowNumber as String] as? Int) != self.window.windowNumber }
            func height(_ w: [String: Any]) -> CGFloat {
                (w[kCGWindowBounds as String] as? [String: CGFloat])?["Height"] ?? 0
            }
            // The menu is the tallest of our windows that isn't the lantern.
            if let id = mine.max(by: { height($0) < height($1) })?[kCGWindowNumber as String]
                as? CGWindowID,
               let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id,
                                                   [.boundsIgnoreFraming, .bestResolution]),
               let png = NSBitmapImageRep(cgImage: image).representation(using: .png,
                                                                         properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            self.menu.cancelTracking()
            NSApp.terminate(nil)
        }
        // Common modes include event tracking, which is where an open menu runs.
        RunLoop.main.add(capture, forMode: .common)
        statusItem.button?.performClick(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        oath.stop()
        monitor.stop()
    }

    func windowDidMove(_ notification: Notification) {
        guard window.isVisible else { return }
        settings.center = CGPoint(x: window.frame.midX, y: window.frame.midY)
    }

    // MARK: - State plumbing

    private var lastInfo = BatteryInfo()

    private func apply(_ info: BatteryInfo) {
        charge.batteryChanged(from: lastInfo, to: info)
        lastInfo = info
        window.lantern.info = info
        updateLanternGate()
        refreshStatusItem()
        refreshMenuHeader()
    }

    private func applySettings() {
        window.applyLevel()
        window.resizeEmblem(to: settings.size)
        if settings.showOnDesktop {
            window.orderFront(nil)
        } else {
            window.orderOut(nil)
        }
        window.lantern.settingsDidChange()
        refreshStatusItem()
        syncMenuState()
    }

    /// The held-back look while sealed on the charger, and the corps the oath
    /// swore the lantern to. Ceremonial: the battery still charges, and the
    /// menu's reading says so.
    private func updateLanternGate() {
        window.lantern.gateSealed = charge.gate == .sealed
        window.lantern.swornCorps = charge.sworn
    }

    // MARK: - Status item

    /// Redrawn only when the battery state changes. It used to animate at
    /// 15fps while charging, which at 19pt was barely visible and cost more
    /// CPU than the entire desktop widget.
    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let info = monitor.info
        let side: CGFloat = 19
        let time = CACurrentMediaTime()

        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let state = LanternRenderer.State(
                level: info.hasBattery ? info.level : 1.0,
                charging: info.isCharging,
                pluggedIn: info.isPluggedIn,
                time: time,
                glow: 0,      // at 19pt any bloom reaches the image edge and gets
                              // cut into a faint square, and it barely reads anyway
                sworn: self.charge.sworn)
            let canvas = LanternGlyph.canvas(center: CGPoint(x: rect.midX, y: rect.midY),
                                             emblemDiameter: rect.width * 0.83)
            LanternRenderer.draw(in: ctx, rect: canvas, state: state)
            return true
        }
        image.isTemplate = false
        button.image = image
        button.imagePosition = settings.menuBarPercent ? .imageLeading : .imageOnly
        button.title = settings.menuBarPercent && info.hasBattery ? " \(info.percent)%" : ""
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.toolTip = "\(info.percent)% — \(info.statusLine)"
    }

    // MARK: - Menu

    private enum Tag: Int {
        case showOnDesktop = 1, floatAbove, lockPosition, showPercent, particles
        case menuBarPercent, launchAtLogin, sealAction
    }

    // Custom rows, in the style of Apple's own menu-bar extras.
    private let headerView = BatteryHeaderView()
    private let oathRow = OathRowView()
    private let sizeRow = SliderRowView(title: "Size")
    private let opacityRow = SliderRowView(title: "Opacity")
    /// The size slider's stops: Small, Medium, Large, Extra Large.
    private static let sizes: [CGFloat] = [140, 190, 260, 340]

    private func item(_ title: String, _ action: Selector?, tag: Tag? = nil,
                      key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        if let tag { i.tag = tag.rawValue }
        return i
    }

    private func row(_ view: NSView) -> NSMenuItem {
        let i = NSMenuItem()
        i.view = view
        return i
    }

    /// Small grey section titles, as Apple's menus use.
    private func section(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) { return .sectionHeader(title: title) }
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func buildMenu() {
        menu.removeAllItems()
        menu.autoenablesItems = false

        menu.addItem(row(headerView))

        menu.addItem(.separator())
        menu.addItem(section("Desktop Lantern"))
        menu.addItem(item("Show on Desktop", #selector(toggleShowOnDesktop),
                          tag: .showOnDesktop))
        menu.addItem(item("Float Above Windows", #selector(toggleFloatAbove),
                          tag: .floatAbove))
        menu.addItem(item("Lock Position", #selector(toggleLock),
                          tag: .lockPosition))
        menu.addItem(item("Show Percentage", #selector(toggleShowPercent),
                          tag: .showPercent))
        menu.addItem(item("Particle Effects", #selector(toggleParticles),
                          tag: .particles))

        let size = sizeRow.slider
        size.minValue = 0
        size.maxValue = Double(Self.sizes.count - 1)
        size.numberOfTickMarks = Self.sizes.count
        size.allowsTickMarkValuesOnly = true
        size.isContinuous = false       // a resize redraws the artwork; do it on release
        size.target = self
        size.action = #selector(sizeChanged(_:))
        menu.addItem(row(sizeRow))

        let opacity = opacityRow.slider
        opacity.minValue = 0.3
        opacity.maxValue = 1
        opacity.isContinuous = true     // opacity is just a layer property — live
        opacity.target = self
        opacity.action = #selector(opacityChanged(_:))
        menu.addItem(row(opacityRow))

        menu.addItem(item("Reset Position", #selector(resetPosition)))

        menu.addItem(.separator())
        menu.addItem(section("The Oath"))
        menu.addItem(item("View All Oaths…", #selector(showOathReference)))
        oathRow.toggle.target = self
        oathRow.toggle.action = #selector(toggleOathListening)
        menu.addItem(row(oathRow))
        menu.addItem(item("Seal the Lantern", #selector(sealLantern),
                          tag: .sealAction))

        menu.addItem(.separator())
        menu.addItem(item("Percentage in Menu Bar", #selector(toggleMenuBarPercent),
                          tag: .menuBarPercent))
        menu.addItem(item("Launch at Login", #selector(toggleLaunchAtLogin),
                          tag: .launchAtLogin))
        menu.addItem(item("Battery Settings…", #selector(openBatterySettings)))

        menu.addItem(.separator())
        menu.addItem(item("Quit Lantern", #selector(quit), key: "q"))

        syncMenuState()
        refreshMenuHeader()
    }

    /// The lantern itself, for the header. At this size it gets its full detail.
    private func headerEmblem(for info: BatteryInfo) -> NSImage {
        NSImage(size: CGSize(width: 42, height: 42), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let canvas = LanternGlyph.canvas(center: CGPoint(x: rect.midX, y: rect.midY),
                                             emblemDiameter: rect.width * 0.96)
            // No glow: it would be cut off square at the image's edge.
            LanternRenderer.draw(in: ctx, rect: canvas, state: .init(
                level: info.hasBattery ? info.level : 1, charging: info.isCharging,
                pluggedIn: info.isPluggedIn, time: 0, glow: 0,
                sworn: self.charge.sworn))
            return true
        }
    }

    private func refreshMenuHeader() {
        let info = monitor.info
        let tint = LanternGlyph.palette(level: info.hasBattery ? info.level : 1,
                                        charging: info.isCharging,
                                        sworn: charge.sworn).bright
        headerView.update(info: info, emblemImage: headerEmblem(for: info), tint: tint)
        oathRow.update(open: charge.gate == .open, detail: oathDetail,
                       corps: charge.sworn.map(OathListener.name(of:)),
                       listening: oath.isListening, tint: tint)
        menu.item(withTag: Tag.sealAction.rawValue)?.isEnabled = (charge.gate == .open)
    }

    /// The oath row's second line: what to do next, or what it's hearing.
    private var oathDetail: String {
        if case .off = oath.state {
            // The row's title already names the corps, so the detail says what
            // to do about it instead of repeating it — and fits without
            // truncating away the one instruction it carries.
            if charge.sworn != nil { return "Seal to release it" }
            return charge.gate == .sealed ? "Switch on, then say an oath"
                                          : "Seals again when you unplug"
        }
        return oathDescription
    }

    private func syncMenuState() {
        func check(_ tag: Tag, _ on: Bool) {
            menu.item(withTag: tag.rawValue)?.state = on ? .on : .off
        }
        check(.showOnDesktop, settings.showOnDesktop)
        check(.floatAbove, settings.floatAboveWindows)
        check(.lockPosition, settings.lockPosition)
        check(.showPercent, settings.showPercent)
        check(.particles, settings.particleEffects)
        check(.menuBarPercent, settings.menuBarPercent)
        check(.launchAtLogin, SMAppService.mainApp.status == .enabled)

        let nearest = Self.sizes.indices.min {
            abs(Self.sizes[$0] - settings.size) < abs(Self.sizes[$1] - settings.size)
        } ?? 1
        sizeRow.slider.doubleValue = Double(nearest)
        opacityRow.slider.doubleValue = Double(settings.opacity)
        oathRow.toggle.state = oath.isListening ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleShowOnDesktop() { settings.showOnDesktop.toggle() }
    @objc private func toggleFloatAbove() { settings.floatAboveWindows.toggle() }
    @objc private func toggleLock() { settings.lockPosition.toggle() }
    @objc private func toggleShowPercent() { settings.showPercent.toggle() }
    @objc private func toggleParticles() { settings.particleEffects.toggle() }
    @objc private func toggleMenuBarPercent() { settings.menuBarPercent.toggle() }

    @objc private func sizeChanged(_ slider: NSSlider) {
        let i = max(0, min(Self.sizes.count - 1, Int(slider.doubleValue.rounded())))
        if settings.size != Self.sizes[i] { settings.size = Self.sizes[i] }
    }

    @objc private func opacityChanged(_ slider: NSSlider) {
        settings.opacity = CGFloat(slider.doubleValue)
    }

    @objc private func resetPosition() {
        window.centerOnScreen()
        settings.center = CGPoint(x: window.frame.midX, y: window.frame.midY)
    }

    @objc private func openBatterySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    @objc private func showOathReference() {
        oathReference.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        oathReference.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = """
                \(error.localizedDescription)

                This usually means the app needs to live in /Applications and be \
                launched from there at least once.
                """
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        syncMenuState()
    }

    private var oathDescription: String {
        switch oath.state {
        case .off: return "Not listening"
        case .requestingPermission: return "Asking for microphone access…"
        case .denied(let why): return why
        case .unavailable(let why): return why
        case .listening: return "Listening for an oath…"
        case .heard(let text): return "Heard: \(text.suffix(46))"
        case .accepted(let corps): return "Sworn to the \(corps)"
        }
    }

    /// An oath lands. The gate opens, the lantern swears to that corps — which
    /// starts the dissolve into its figure and colour — and the oath's own
    /// flare goes over the top of it.
    ///
    /// Then listening switches itself off. An oath is said once to change the
    /// lantern, not held open afterwards: leaving the microphone live would
    /// keep it running for a change nobody is waiting to make, and let the
    /// tail of the same recitation swear the lantern again. Turning the switch
    /// back on is how you ask for the next one.
    private func oathAccepted(_ sworn: OathListener.Oath) {
        charge.swear(to: sworn.corps)
        window.lantern.triggerOathFlare()
        oath.stop()
        settings.oathListening = false
        syncMenuState()
        refreshMenuHeader()
    }

    @objc private func toggleOathListening() {
        if oath.isListening {
            oath.stop()
            settings.oathListening = false
        } else {
            oath.start()
            settings.oathListening = true
        }
        syncMenuState()
        refreshMenuHeader()
    }

    /// Seals the gate and releases the corps, handing the lantern back to the
    /// battery — which dissolves it into whichever corps the charge calls for.
    @objc private func sealLantern() {
        charge.set(.sealed)
        refreshMenuHeader()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        monitor.refresh()
        refreshMenuHeader()
        syncMenuState()
    }
}
