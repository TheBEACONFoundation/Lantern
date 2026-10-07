import Foundation
import IOKit
import IOKit.ps

struct BatteryInfo: Equatable {
    var hasBattery = false
    var level: Double = 1.0          // 0...1
    var isCharging = false
    var isPluggedIn = false
    var isCharged = false
    var minutesToEmpty: Int?         // nil when unknown / still calculating
    var minutesToFull: Int?

    // From the AppleSmartBattery registry node — absent on desktops.
    var cycleCount: Int?
    var healthPercent: Int?
    var temperatureC: Double?
    var wattage: Double?             // negative = draining, positive = charging

    var percent: Int { Int((level * 100).rounded()) }

    var statusLine: String {
        if !hasBattery { return "No battery detected" }
        if isCharged && isPluggedIn { return "Fully charged" }
        if isCharging {
            if let m = minutesToFull { return "Charging — \(Self.format(m)) to full" }
            return "Charging"
        }
        if isPluggedIn { return "Plugged in, not charging" }
        if let m = minutesToEmpty { return "\(Self.format(m)) remaining" }
        return "On battery"
    }

    static func format(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

/// Polls IOKit for power-source state and notifies on change. Uses the system's
/// own power-source change notification, with a slow timer as a safety net for
/// values (time estimates, temperature) that change without firing it.
final class BatteryMonitor {

    private(set) var info = BatteryInfo()
    var onChange: ((BatteryInfo) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?

    func start() {
        refresh()

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.refresh()
        }, ctx)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        var next = readPowerSources()
        mergeSmartBattery(into: &next)
        guard next != info else { return }
        info = next
        onChange?(next)
    }

    // MARK: - IOPowerSources

    private func readPowerSources() -> BatteryInfo {
        var out = BatteryInfo()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return out }

        // A Get-rule function: the string isn't ours to release.
        out.isPluggedIn = (IOPSGetProvidingPowerSourceType(blob)?
            .takeUnretainedValue() as String?) == kIOPSACPowerValue

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            out.hasBattery = true
            out.level = max > 0 ? Double(current) / Double(max) : 0
            out.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            out.isCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                out.isPluggedIn = state == kIOPSACPowerValue
            }
            // IOKit reports -1 while it is still working out an estimate.
            if let m = desc[kIOPSTimeToEmptyKey] as? Int, m > 0 { out.minutesToEmpty = m }
            if let m = desc[kIOPSTimeToFullChargeKey] as? Int, m > 0 { out.minutesToFull = m }
            break
        }
        return out
    }

    // MARK: - AppleSmartBattery registry

    private static let smc = try? SMC()

    /// Battery temperature from the SMC sensor TB0T: a little-endian float, °C.
    private static func smcBatteryTemperature() -> Double? {
        guard let bytes = try? smc?.read("TB0T"), bytes.count == 4 else { return nil }
        let value = bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) }
        return value > -40 && value < 120 ? Double(value) : nil
    }

    private func mergeSmartBattery(into out: inout BatteryInfo) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return }

        out.cycleCount = props["CycleCount"] as? Int

        // Capacity figures sat at the top level until the Darwin 27 update,
        // which moved them into BatteryData; read either.
        let data = props["BatteryData"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Int? { props[key] as? Int ?? data[key] as? Int }

        // Apple silicon exposes NominalChargeCapacity; Intel used AppleRawMaxCapacity.
        let design = value("DesignCapacity")
        let nominal = value("NominalChargeCapacity") ?? value("AppleRawMaxCapacity")
        if let design, let nominal, design > 0 {
            out.healthPercent = Int((Double(nominal) / Double(design) * 100).rounded())
        }

        if let raw = props["Temperature"] as? Int {
            out.temperatureC = Double(raw) / 100.0   // reported in centi-degrees
        } else {
            // Darwin 27 dropped it from the registry; the SMC's battery sensor
            // still has it, and reading that needs no privileges.
            out.temperatureC = Self.smcBatteryTemperature()
        }
        if let mv = props["Voltage"] as? Int, let ma = props["Amperage"] as? Int {
            out.wattage = Double(mv) / 1000.0 * Double(ma) / 1000.0
        }
    }
}
