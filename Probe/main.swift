import Foundation
import IOKit

// Identifies which SMC key gates charging on this Mac, by testing candidates
// one at a time and restoring each immediately.
//
// The classic Apple Silicon inhibit keys (CH0B/CH0C/CH0I) are absent on M5, so
// the candidates below are informed guesses. Each one states its rationale, and
// nothing is assumed about what a key means.
//
// Safety rules this tool holds to:
//   * only one key is modified at a time
//   * the original value is captured first and restored straight after
//   * restore also runs on SIGINT/SIGTERM and on any error path
//   * it refuses to run unless the Mac is plugged in AND actively charging,
//     because otherwise there is no effect to observe
//   * if charging fails to resume after a restore, it stops immediately

struct Candidate {
    let key: String
    let test: [UInt8]
    let why: String
}

// Enumerating every SMC key on this Mac (3,794 of them, after the OS update to
// Darwin 27) leaves CHIE as the only writable charging control. CHTE, which an
// earlier OS exposed, is gone. ACLC is writable but changes by itself with the
// power source — 03 on battery, 04 while charging — so it looks like a status
// value, not a switch; it's left out, though `--key ACLC` can still test it.
let defaultCandidates = [
    Candidate(key: "CHIE", test: [0x01],
              why: "1-byte hex_ flag; 1 is the conventional 'inhibit' encoding"),
    Candidate(key: "CHIE", test: [0x02],
              why: "same flag; CH0B used 02 to inhibit on M1–M4"),
]

func parseHex(_ s: String) -> [UInt8]? {
    let cleaned = s.replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "0x", with: "")
    guard cleaned.count % 2 == 0 else { return nil }
    return stride(from: 0, to: cleaned.count, by: 2).compactMap {
        let i = cleaned.index(cleaned.startIndex, offsetBy: $0)
        return UInt8(cleaned[i...cleaned.index(i, offsetBy: 1)], radix: 16)
    }
}

// `--key CHIE --value 02` tests one specific key/value instead of the defaults.
var candidates = defaultCandidates
let args = CommandLine.arguments
if let ki = args.firstIndex(of: "--key"), ki + 1 < args.count {
    let key = args[ki + 1]
    var value: [UInt8] = [0x01]
    if let vi = args.firstIndex(of: "--value"), vi + 1 < args.count,
       let parsed = parseHex(args[vi + 1]) { value = parsed }
    candidates = [Candidate(key: key, test: value, why: "specified on the command line")]
}

func batteryState() -> (charging: Bool, plugged: Bool, current: Int, percent: Int) {
    let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                              IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return (false, false, 0, 0) }
    defer { IOObjectRelease(service) }
    var u: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &u, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let p = u?.takeRetainedValue() as? [String: Any] else { return (false, false, 0, 0) }
    return (p["IsCharging"] as? Bool ?? false,
            p["ExternalConnected"] as? Bool ?? false,
            p["InstantAmperage"] as? Int ?? p["Amperage"] as? Int ?? 0,
            p["CurrentCapacity"] as? Int ?? 0)
}

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }
func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

final class Restorer {
    var pending: (key: String, bytes: [UInt8])?
    let smc: SMC
    init(smc: SMC) { self.smc = smc }
    func restore(_ reason: String) {
        guard let p = pending else { return }
        pending = nil
        do {
            try smc.write(p.key, bytes: p.bytes)
            print("  restored \(p.key) -> \(hex(p.bytes))  [\(reason)]")
        } catch {
            print("""

              !! FAILED to restore \(p.key) to \(hex(p.bytes)): \(error)
                 Shut the Mac down fully, wait 30s, then power it back on.
            """)
        }
    }
}

// Declared before the signal handlers, which can't capture context and so
// have to reach it as a global.
var restorerGlobal: Restorer?

guard getuid() == 0 else {
    print("""
    This probe writes SMC keys, so it must run as root:

        sudo "\(args[0])"
    """)
    exit(1)
}

let smc: SMC
do { smc = try SMC() } catch { print("Cannot open SMC: \(error)"); exit(1) }
let restorer = Restorer(smc: smc)
restorerGlobal = restorer

for sig in [SIGINT, SIGTERM] {
    signal(sig) { _ in
        print("\n interrupted — restoring")
        restorerGlobal?.restore("signal")
        exit(130)
    }
}

var start = batteryState()
// On Apple Silicon, CurrentCapacity is the charge percentage, not mAh.
print("Battery: \(start.percent)%  plugged=\(start.plugged)  charging=\(start.charging)  current=\(start.current) mA\n")

guard start.plugged else {
    print("""
    Not plugged in. Connect power and run this again.
    The probe works by trying to STOP an active charge, so it needs one running.
    """)
    exit(1)
}
// Charging takes a few seconds to begin after the cable goes in, so give it a
// moment rather than refusing straight away.
if !(start.charging && start.current > 0) {
    print("Plugged in but not charging yet — waiting up to 20s for it to start...")
    for _ in 0..<20 {
        pause(1)
        start = batteryState()
        if start.charging && start.current > 0 { break }
    }
}
guard start.charging, start.current > 0 else {
    print("""
    Still not charging after 20s (\(start.percent)%, \(start.current) mA).
    macOS won't top up a battery that's nearly full; below about 85% it always
    charges. If it's lower than that, check the cable and adapter.
    """)
    exit(1)
}
print("Charging at \(start.current) mA — starting.\n")

struct Finding { let key: String; let value: [UInt8]; let stopped: Bool; let detail: String }
var findings: [Finding] = []

for c in candidates {
    print("--- \(c.key) --- (\(c.why))")
    let meta: SMCKeyInfo
    let original: [UInt8]
    do {
        meta = try smc.info(c.key)
        original = try smc.read(c.key)
    } catch { print("  skipped: \(error)\n"); continue }

    guard meta.isWritable else { print("  skipped: firmware reports it read-only\n"); continue }
    guard c.test.count == meta.size else {
        print("  skipped: test value is \(c.test.count) bytes, key is \(meta.size)\n"); continue
    }
    print("  size=\(meta.size) type=\(meta.type) attr=0x\(String(format: "%02x", meta.attributes)) original=\(hex(original))")

    let before = batteryState()
    restorer.pending = (c.key, original)
    do {
        try smc.write(c.key, bytes: c.test)
        print("  wrote \(hex(c.test)), observing for 4s...")
    } catch {
        print("  write rejected: \(error)\n")
        restorer.pending = nil
        continue
    }

    pause(4)
    let during = batteryState()
    restorer.restore("test complete")
    // Charging takes several seconds to ramp back up once the inhibit clears —
    // on the first real run it hadn't restarted after 3s but had within a
    // minute — so poll for up to 30s before calling it a failure.
    var after = batteryState()
    for _ in 0..<30 where !(after.charging || after.current > 0) {
        pause(1)
        after = batteryState()
    }

    let stopped = (before.charging && !during.charging)
        || (before.current > 200 && during.current <= 0)
    let recovered = after.charging || after.current > 0

    print("  before: charging=\(before.charging) current=\(before.current) mA")
    print("  during: charging=\(during.charging) current=\(during.current) mA")
    print("  after:  charging=\(after.charging) current=\(after.current) mA")
    print("  => \(stopped ? "CHARGING STOPPED" : "no effect on charging"); recovered=\(recovered)\n")

    if !recovered {
        print("""
          !! Charging did not resume within 30s of restoring \(c.key).
             Stopping here. Try unplugging and plugging back in first; if it
             still won't charge, shut down fully, wait 30s, and power on.
        """)
        exit(2)
    }
    findings.append(Finding(key: c.key, value: c.test, stopped: stopped,
                            detail: "before=\(before.current)mA during=\(during.current)mA"))
}

// Final audit: every key back where it started.
print(String(repeating: "=", count: 62))
print("Verifying all candidates are back at their original values:")
for key in Set(candidates.map(\.key)).sorted() {
    if let v = try? smc.read(key) { print("  \(key) = \(hex(v))") }
}
print("")

let winners = findings.filter(\.stopped)
if winners.isEmpty {
    print("""
    No candidate gated charging.

    None of \(candidates.map(\.key).joined(separator: ", ")) stopped the charge.
    Charge control doesn't look reachable through these keys on this Mac. The
    oath still works — it just won't be able to hold the cable back.
    """)
} else {
    for w in winners {
        print("FOUND: \(w.key) gates charging — write \(hex(w.value)) to inhibit. \(w.detail)")
    }
    print("\nTell Claude which key won and it'll wire the oath to it.")
}
