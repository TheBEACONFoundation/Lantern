import Foundation

/// The lantern's gate — ceremony, not control. It seals when you unplug, and
/// the oath opens it; the lantern shows a held-back pulse while it's sealed on
/// the charger, and flares when the oath lands.
///
/// Charging itself is never touched. The only writable charging control on
/// this M5 Max, the SMC key CHIE, doesn't stop the battery charging — it cuts
/// the charger off altogether, so the Mac runs from its battery. There's no way
/// to "run on the charger but don't charge", so the gate stays symbolic.
enum ChargeGate: Equatable {
    case sealed
    case open
}

final class ChargeController {

    private(set) var gate: ChargeGate = .sealed

    /// The corps whose oath was last spoken. While the gate is open the lantern
    /// shows this corps whatever the charge says; sealing hands it back.
    private(set) var sworn: LanternGlyph.Emblem?

    var onChange: ((ChargeGate) -> Void)?

    var statusLine: String {
        gate == .sealed ? "Sealed — say the oath" : "Open — the oath was spoken"
    }

    func set(_ newGate: ChargeGate) {
        // Sealing releases the corps as well as the gate — that is what hands
        // the lantern back to the battery.
        let next: LanternGlyph.Emblem? = newGate == .sealed ? nil : sworn
        guard gate != newGate || sworn != next else { return }
        gate = newGate
        sworn = next
        onChange?(newGate)
    }

    /// An oath lands: the gate opens and the lantern swears to that corps.
    func swear(to corps: LanternGlyph.Emblem) {
        guard gate != .open || sworn != corps else { return }
        gate = .open
        sworn = corps
        onChange?(gate)
    }

    /// Unplugging seals the gate, so every plug-in calls for the oath.
    func batteryChanged(from old: BatteryInfo, to new: BatteryInfo) {
        if old.isPluggedIn && !new.isPluggedIn { set(.sealed) }
    }
}
