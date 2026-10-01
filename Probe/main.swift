import Foundation
import IOKit

// Tests charging-control candidates one at a time. Every write, including a
// rejected write, is followed by a verified restoration before another test.
let defaultCandidates = [
    Candidate(key: "CHIE", test: [0x01],
              why: "1-byte hex_ flag; 1 is the conventional 'inhibit' encoding"),
    Candidate(key: "CHIE", test: [0x02],
              why: "same flag; CH0B used 02 to inhibit on M1–M4"),
]

let usage = """
Usage: lantern-probe [--key KEY [--value HEX]]

Tests the default candidates, or one four-byte ASCII SMC key. HEX must contain
complete hexadecimal byte pairs (for example 02, 0x02, or "01 02").
Requires root, external power, and an actively charging battery.
"""

// Parse the entire command before checking privileges or opening the SMC.
let candidates: [Candidate]
do {
    switch try ProbeArguments.parse(Array(CommandLine.arguments.dropFirst()),
                                    defaults: defaultCandidates) {
    case .help:
        print(usage)
        exit(0)
    case .run(let parsed):
        candidates = parsed
    }
} catch {
    fputs("Invalid arguments: \(error)\n\n\(usage)\n", stderr)
    exit(1)
}

guard getuid() == 0 else {
    fputs("This probe writes SMC keys and must run as root. Run it with sudo.\n", stderr)
    exit(1)
}

extension SMC: ProbeSMC {}

struct BatteryState {
    let charging: Bool
    let plugged: Bool
    let current: Int
    let percent: Int
    var activelyCharging: Bool { plugged && charging && current > 0 }
}

func batteryState() throws -> BatteryState {
    let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                              IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { throw ProbeFailure("Cannot find the battery") }
    defer { IOObjectRelease(service) }
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let values = properties?.takeRetainedValue() as? [String: Any],
          let charging = values["IsCharging"] as? Bool,
          let plugged = values["ExternalConnected"] as? Bool,
          let current = values["InstantAmperage"] as? Int ?? values["Amperage"] as? Int,
          let percent = values["CurrentCapacity"] as? Int else {
        throw ProbeFailure("Cannot read the battery's charging state")
    }
    return BatteryState(charging: charging, plugged: plugged, current: current, percent: percent)
}

// Dispatch handlers only request interruption. All IOKit work, rollback and
// reporting remain on this thread; no signal handler touches the SMC or Swift
// runtime. Keep the sources alive until the process finishes.
let interruption = ProbeInterruption()
let signalQueue = DispatchQueue(label: "lantern.probe.signals")
let signalSources = [SIGINT, SIGTERM].map { signalNumber -> DispatchSourceSignal in
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
    source.setEventHandler { interruption.request(signalNumber) }
    source.resume()
    return source
}

struct Finding {
    let key: String
    let value: [UInt8]
    let effect: ProbeEffect
    let detail: String
}

var restorer: ProbeRestorer?
var exitStatus: Int32 = 0

do {
    try interruption.check()
    var start = try batteryState()
    print("Battery: \(start.percent)%  plugged=\(start.plugged)  charging=\(start.charging)  current=\(start.current) mA\n")
    guard start.plugged else {
        throw ProbeFailure("Connect external power before probing an active charge")
    }
    if !start.activelyCharging {
        print("Plugged in but not charging yet — waiting up to 20s for it to start...")
        for _ in 0..<20 {
            try interruption.pause(1)
            start = try batteryState()
            guard start.plugged else { throw ProbeFailure("External power was disconnected") }
            if start.activelyCharging { break }
        }
    }
    guard start.activelyCharging else {
        throw ProbeFailure("Still not charging after 20s (\(start.percent)%, \(start.current) mA). Try again while the battery is actively charging")
    }
    try interruption.check()
    let smc = try SMC()
    let recovery = ProbeRestorer(smc: smc)
    restorer = recovery
    var findings: [Finding] = []
    print("Charging at \(start.current) mA — starting.\n")

    for candidate in candidates {
        try interruption.check()
        print("--- \(candidate.key) --- (\(candidate.why))")
        let metadata: SMCKeyInfo
        do {
            metadata = try smc.info(candidate.key)
        } catch {
            print("  skipped: \(error)\n")
            continue
        }
        guard metadata.isWritable else {
            print("  skipped: firmware reports it read-only\n")
            continue
        }
        guard candidate.test.count == metadata.size else {
            print("  skipped: test value is \(candidate.test.count) bytes, key is \(metadata.size)\n")
            continue
        }
        let before = try batteryState()
        guard before.activelyCharging else {
            throw ProbeFailure("Battery must still be plugged in and actively charging before testing \(candidate.key)")
        }
        try interruption.check()
        let during = try recovery.withTestValue(key: candidate.key, value: candidate.test) {
            try interruption.check()
            if let original = recovery.pending?.bytes {
                print("  size=\(metadata.size) type=\(metadata.type) attr=0x\(String(format: "%02x", metadata.attributes)) original=\(hex(original))")
            }
            print("  wrote \(hex(candidate.test)), observing for 4s...")
            try interruption.pause(4)
            return try batteryState()
        }
        print("  restored \(candidate.key); original value verified by readback")

        // The charger may need time to reconnect and ramp back up. Both the
        // connection and positive charging state must recover before proceeding.
        var after = try batteryState()
        for _ in 0..<30 {
            if after.activelyCharging { break }
            try interruption.pause(1)
            after = try batteryState()
        }
        let effect = ProbeEffect.classify(wasCharging: before.charging, beforeCurrent: before.current,
                                          isCharging: during.charging, duringCurrent: during.current,
                                          isPluggedIn: during.plugged)
        print("  before: plugged=\(before.plugged) charging=\(before.charging) current=\(before.current) mA")
        print("  during: plugged=\(during.plugged) charging=\(during.charging) current=\(during.current) mA")
        print("  after:  plugged=\(after.plugged) charging=\(after.charging) current=\(after.current) mA")
        print("  => \(effect.rawValue); recovered=\(after.activelyCharging)\n")
        guard after.activelyCharging else {
            throw ProbeFailure("Charging did not resume within 30s of restoring \(candidate.key). Stopping here; check the cable and adapter")
        }
        findings.append(Finding(key: candidate.key, value: candidate.test, effect: effect,
                                detail: "before=\(before.current)mA during=\(during.current)mA"))
    }

    try interruption.check()
    print(String(repeating: "=", count: 62))
    print("Comparing every tested key against its original value:")
    for snapshot in try recovery.audit() {
        print("  \(snapshot.key) = \(hex(snapshot.bytes)) (verified)")
    }
    print("")
    let winners = findings.filter { $0.effect == .chargingStopped }
    if winners.isEmpty {
        print("No candidate stopped charging while leaving external power connected.")
    } else {
        for winner in winners {
            print("FOUND: \(winner.key) gates charging — write \(hex(winner.value)) to inhibit. \(winner.detail)")
        }
    }
    try interruption.check()
} catch {
    // withTestValue already attempts rollback. If that failed, keep its record
    // and make one last verified recovery attempt, then exit without more tests.
    fputs("\nProbe stopped: \(error)\n", stderr)
    if let recovery = restorer, let pending = recovery.pending {
        do {
            try recovery.restore()
            fputs("Restored \(pending.key) to \(hex(pending.bytes)); readback verified. No further keys will be tested.\n", stderr)
        } catch {
            fputs("FAILED to restore \(pending.key) to \(hex(pending.bytes)): \(error)\nRecovery remains unverified. Shut the Mac down fully, wait 30s, then power it back on.\n", stderr)
        }
    }
    if let interrupted = error as? ProbeInterrupted {
        exitStatus = 128 + interrupted.signal
    } else {
        exitStatus = 2
    }
}

withExtendedLifetime(signalSources) {}
exit(exitStatus)
