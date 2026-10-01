import AppKit
import QuartzCore

// Exercise actual Core Animation state without opening windows or changing
// system accessibility settings. Preferences live only in this process.
_ = NSApplication.shared
UserDefaults.standard.setVolatileDomain([
    "showPercent": true,
    "particleEffects": true,
    "opacity": 1.0,
], forName: UserDefaults.argumentDomain)

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func descendants(of layer: CALayer) -> [CALayer] {
    [layer]
        + (layer.mask.map { descendants(of: $0) } ?? [])
        + (layer.sublayers ?? []).flatMap { descendants(of: $0) }
}

struct Artwork {
    let root: CALayer
    let emblem: CALayer
    let caption: CALayer
    let strip: CALayer
    let sweep: CALayer
    let held: CALayer
    let emberEmitter: CAEmitterLayer
    let burstEmitter: CAEmitterLayer

    init(_ view: LanternView) {
        root = view.layer!
        emblem = root.sublayers![0]
        caption = root.sublayers![1]
        let lit = emblem.sublayers![5]
        strip = lit.sublayers![0]
        sweep = lit.sublayers![2]
        held = lit.sublayers![3]
        emberEmitter = emblem.sublayers![6] as! CAEmitterLayer
        burstEmitter = emblem.sublayers![8] as! CAEmitterLayer
    }

    func expectStill(_ context: String) {
        for layer in descendants(of: root) {
            expect((layer.animationKeys() ?? []).isEmpty,
                   "\(context): unexpected animations \(layer.animationKeys() ?? [])")
            if let emitter = layer as? CAEmitterLayer {
                expect(emitter.birthRate == 0, "\(context): particle emission remains active")
            }
        }
        expect(emberEmitter.isHidden && burstEmitter.isHidden,
               "\(context): existing particles must be hidden immediately")
        expect(strip.contents != nil && !strip.isHidden,
               "\(context): static battery fill must remain visible")
        expect(caption.contents != nil && !caption.isHidden,
               "\(context): battery percentage must remain visible")
    }
}

func accessibilitySettingsChanged() {
    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: nil)
}

let frame = NSRect(x: 0, y: 0, width: 300, height: 300)
var reduced = false
let view = LanternView(frame: frame, reduceMotionPreference: { reduced })
let art = Artwork(view)
var battery = BatteryInfo()
battery.hasBattery = true
battery.level = 0.21
view.info = battery
battery.level = 0.20
view.info = battery
expect(art.strip.animation(forKey: "corpsShift") != nil,
       "Entering low battery must preserve the fill dissolve")
expect(art.strip.animation(forKey: "slide") != nil,
       "Normal motion must still animate the liquid")

battery.level = 0.10
view.info = battery
battery.isCharging = true
battery.isPluggedIn = true
view.info = battery
expect(art.strip.animation(forKey: "corpsShift") != nil,
       "Starting charging must preserve the red-to-green fill dissolve")
expect(art.sweep.animation(forKey: "corpsShift") != nil,
       "Starting charging must preserve the sweep artwork dissolve")
expect(art.held.animation(forKey: "corpsShift") != nil,
       "Updating motion must preserve the held-ring artwork dissolve")
expect(art.strip.animation(forKey: "breath") != nil,
       "Charging must resume the liquid's breathing animation")

view.setFrameSize(NSSize(width: 280, height: 280))
for layer in descendants(of: art.root) {
    expect(layer.animation(forKey: "corpsShift") == nil,
           "Resizing must remove dissolves from the previous artwork geometry")
}
expect(art.strip.animation(forKey: "slide") != nil && art.sweep.animation(forKey: "spin") != nil,
       "Resizing must restore ambient motion at the new geometry")

view.swornCorps = .red
view.triggerOathFlare()
expect(art.emblem.animation(forKey: "corpsFlourish") != nil,
       "The test must enable Reduce Motion during an active flourish")
expect(art.burstEmitter.birthRate > 0,
       "The test must enable Reduce Motion during an active particle burst")
reduced = true
accessibilitySettingsChanged()
art.expectStill("Enabling Reduce Motion live")
expect(!art.sweep.isHidden, "Charging must retain its static ring indicator")

let oldFill = art.strip.contents as! CGImage
battery.level = 0.65
view.info = battery
expect(oldFill !== (art.strip.contents as! CGImage),
       "Battery level changes must update the static fill")
view.swornCorps = .blue
view.triggerOathFlare()
art.expectStill("Battery and oath changes with Reduce Motion")
view.gateSealed = true
art.expectStill("Sealed while charging with Reduce Motion")
expect(!art.held.isHidden && art.held.opacity > 0 && art.sweep.isHidden,
       "A sealed lantern must retain the static held-ring indicator")

view.gateSealed = false
battery.isCharging = false
battery.isPluggedIn = false
battery.level = 0.10
view.swornCorps = nil
view.info = battery
art.expectStill("Low battery with Reduce Motion")
expect(art.sweep.isHidden && art.held.isHidden,
       "An unplugged lantern must hide charging and held indicators")
battery.level = 1
battery.isPluggedIn = true
view.info = battery
art.expectStill("Full battery with Reduce Motion")
expect(!art.sweep.isHidden, "A full plugged-in battery must retain its static ring")

battery.level = 0.65
battery.isCharging = true
view.info = battery
reduced = false
accessibilitySettingsChanged()
expect(art.strip.animation(forKey: "slide") != nil,
       "Disabling Reduce Motion must restore surface motion")
expect(art.sweep.animation(forKey: "spin") != nil,
       "Disabling Reduce Motion must restore charging motion")
expect(!art.emberEmitter.isHidden && art.emberEmitter.birthRate > 0,
       "Disabling Reduce Motion must restore particles")

let initiallyReduced = LanternView(frame: frame, reduceMotionPreference: { true })
initiallyReduced.info = battery
initiallyReduced.triggerOathFlare()
Artwork(initiallyReduced).expectStill("Launching with Reduce Motion")

weak var releasedView: LanternView?
autoreleasepool {
    let temporary = LanternView(frame: frame, reduceMotionPreference: { false })
    releasedView = temporary
}
expect(releasedView == nil, "The accessibility observer must not retain the view")

let reference = OathReferenceWindowController()
let referenceWindow = reference.window!
let referenceScroll = referenceWindow.contentView!.subviews[0] as! NSScrollView
let referenceText = referenceScroll.documentView as! NSTextView
expect(OathListener.oaths.count == 9, "The reference must cover all nine corps")
for oath in OathListener.oaths {
    expect(referenceText.string.contains(oath.name), "Missing reference heading: \(oath.name)")
    expect(referenceText.string.contains(oath.text), "Missing canonical oath: \(oath.name)")
}
expect(referenceText.isSelectable && !referenceText.isEditable,
       "The reference must allow oath copying while preventing edits")
expect(referenceText.accessibilityLabel() == "Lantern oath reference",
       "The reference must have a useful accessibility label")
expect(referenceScroll.hasVerticalScroller && !referenceScroll.hasHorizontalScroller,
       "The reference must scroll vertically and wrap lines")

var referenceHeights: [CGFloat] = []
for width: CGFloat in [580, 400] {
    referenceWindow.setContentSize(NSSize(width: width, height: 320))
    referenceScroll.layoutSubtreeIfNeeded()
    let container = referenceText.textContainer!
    let layout = referenceText.layoutManager!
    layout.ensureLayout(for: container)
    let used = layout.usedRect(for: container)
    referenceHeights.append(used.height)
    expect(used.maxX <= referenceScroll.contentSize.width - referenceText.textContainerInset.width * 2 + 1,
           "The oath reference must wrap within the viewport at width \(width)")
    expect(referenceText.frame.height >= used.maxY + referenceText.textContainerInset.height * 2,
           "The oath reference must size its document to include the final oath at width \(width)")
    expect(referenceText.frame.height > referenceScroll.contentSize.height,
           "The oath reference must make all content reachable by scrolling at width \(width)")
    referenceText.scrollRangeToVisible(NSRange(location: (referenceText.string as NSString).length - 1, length: 1))
    expect(referenceScroll.documentVisibleRect.maxY >= used.maxY + referenceText.textContainerInset.height,
           "The final oath must be scrollable into view at width \(width)")
}
expect(referenceHeights[1] > referenceHeights[0],
       "Narrowing the reference window must reflow the oath text")
referenceWindow.close()

print("Rendering regression checks passed (\(checks) assertions).")
