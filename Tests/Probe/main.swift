import Foundation

var checks = 0
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    checks += 1
    do {
        guard try condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    } catch {
        fputs("FAIL: \(message): \(error)\n", stderr)
        exit(1)
    }
}

@discardableResult
func expectFailure(_ message: String, _ body: () throws -> Void) -> Error {
    do {
        try body()
        fputs("FAIL: \(message): expected an error\n", stderr)
        exit(1)
    } catch {
        checks += 1
        return error
    }
}

final class FakeSMC: ProbeSMC {
    var values: [String: [UInt8]]
    var readFailures: Set<Int> = []
    var writeFailures: Set<Int> = []
    var ignoredWrites: Set<Int> = []
    private(set) var reads = 0
    private(set) var writes = 0
    private(set) var events: [String] = []
    private(set) var allAccessOnMainThread = true

    init(_ values: [String: [UInt8]] = ["TEST": [0x00]]) { self.values = values }

    func read(_ key: String) throws -> [UInt8] {
        allAccessOnMainThread = allAccessOnMainThread && Thread.isMainThread
        reads += 1
        events.append("read \(key)")
        if readFailures.contains(reads) { throw ProbeFailure("read failure \(reads)") }
        guard let value = values[key] else { throw ProbeFailure("missing \(key)") }
        return value
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        allAccessOnMainThread = allAccessOnMainThread && Thread.isMainThread
        writes += 1
        events.append("write \(key) \(hex(bytes))")
        // Failed writes may have changed the device before reporting an error.
        if !ignoredWrites.contains(writes) { values[key] = bytes }
        if writeFailures.contains(writes) { throw ProbeFailure("write failure \(writes)") }
    }
}

let defaults = [Candidate(key: "CHIE", test: [0x01], why: "default")]
func parsed(_ arguments: [String]) throws -> [Candidate] {
    guard case .run(let candidates) = try ProbeArguments.parse(arguments, defaults: defaults) else {
        throw ProbeFailure("Expected runnable arguments")
    }
    return candidates
}
expect(try parsed([]) == defaults, "An empty command must use the defaults")
expect(try parsed(["--key", "CHIE"])[0].test == [1], "An omitted value must use 01")
expect(try parsed(["--value", "0X0A ff", "--key", "CHIE"])[0].test == [10, 255],
       "Arguments may be reordered and byte groups may use a hex prefix")
expect(try parsed(["--key", "CHIE", "--value", "0102"])[0].test == [1, 2],
       "Contiguous byte pairs must preserve all bytes")
expect(try ProbeArguments.parseHex("01\t0x02\n03") == [1, 2, 3],
       "Whitespace between groups must be accepted")
expect(try ProbeArguments.parseHex(String(repeating: "ab", count: 32)).count == 32,
       "The full 32-byte SMC payload must be accepted")
for arguments in [
    ["--key", "CHIE", "--value", "02zz"],
    ["--key", "CHIE", "--value", "2"],
    ["--key", "CHIE", "--value", "01 2"],
    ["--key", "CHIE", "--value", "0x"],
    ["--key", "CHIE", "--value", ""],
    ["--key", "CHIE", "--value", String(repeating: "aa", count: 33)],
    ["--key", "CHIE", "--value", "01;02"],
    ["--key", "CHIE", "--value", "０１"],
    ["--key", "ABC"], ["--key", "ABCDE"], ["--key", "éABC"],
    ["--key", "ABC\n"], ["--key"], ["--value", "01"],
    ["--key", "CHIE", "--value"], ["--key", "CHIE", "--bogus", "02"],
    ["--key", "CHIE", "--key", "CHIE"],
    ["--key", "CHIE", "--value", "01", "--value", "02"],
    ["--help", "--key", "CHIE"], ["--unknown"], ["extra"],
] {
    expectFailure("Malformed command must fail: \(arguments)") { _ = try parsed(arguments) }
}
for arguments in [["--help"], ["-h"]] {
    guard case .help = try ProbeArguments.parse(arguments, defaults: defaults) else {
        fputs("FAIL: help command must succeed\n", stderr)
        exit(1)
    }
    checks += 1
}

// A successful round trip must write and read the original before clearing
// the pending record. The audit compares against the initial value.
do {
    let smc = FakeSMC()
    let recovery = ProbeRestorer(smc: smc)
    let observed = try recovery.withTestValue(key: "TEST", value: [1]) {
        expect(smc.values["TEST"] == [1], "The observation must see the test value")
        expect(recovery.pending == ProbeSnapshot(key: "TEST", bytes: [0]),
               "The recovery record must exist during the observation")
        return 42
    }
    expect(observed == 42 && recovery.pending == nil && smc.values["TEST"] == [0],
           "Successful restoration must return the observation and clear pending state")
    expect(smc.events == ["read TEST", "write TEST 01", "write TEST 00", "read TEST"],
           "Restoration must read back the original before returning")
    expect(try recovery.audit() == [ProbeSnapshot(key: "TEST", bytes: [0])],
           "The final audit must verify the captured original")
    expect(try recovery.restore() == nil && smc.writes == 2,
           "Already restored keys must not be written again")
}

// Even a rejected write can have partially changed hardware. Recovery is
// necessary before reporting its failure, and the operation must not succeed.
do {
    let smc = FakeSMC()
    smc.writeFailures = [1]
    let recovery = ProbeRestorer(smc: smc)
    var observed = false
    let error = expectFailure("A failed test write must propagate") {
        try recovery.withTestValue(key: "TEST", value: [1]) { observed = true }
    }
    expect(String(describing: error).contains("write failure 1"), "Keep the original write error")
    expect(!observed && smc.values["TEST"] == [0] && recovery.pending == nil,
           "A partially failed write must restore and verify without observing")
    expect(smc.events == ["read TEST", "write TEST 01", "write TEST 00", "read TEST"],
           "A rejected write must still perform verified rollback")
}

// A readback mismatch leaves the recovery record intact and prevents any
// subsequent test. A retry may clear it only after verifying the same original.
do {
    let smc = FakeSMC(["TEST": [0], "NEXT": [5]])
    smc.ignoredWrites = [2]
    let recovery = ProbeRestorer(smc: smc)
    let error = expectFailure("An ignored restoration must be detected") {
        try recovery.withTestValue(key: "TEST", value: [1]) {}
    }
    expect(String(describing: error).contains("restore read back 01; expected 00"),
           "A mismatch must report actual and expected values")
    expect(recovery.pending == ProbeSnapshot(key: "TEST", bytes: [0]),
           "Readback mismatch must preserve the original rollback record")
    let events = smc.events
    expectFailure("No next candidate may run while restoration is pending") {
        try recovery.withTestValue(key: "NEXT", value: [1]) {}
    }
    expect(smc.events == events && smc.values["NEXT"] == [5],
           "Failed restoration must block all access to another candidate")
    expectFailure("The final audit may not succeed with a pending restoration") { _ = try recovery.audit() }
    expect(try recovery.restore() == ProbeSnapshot(key: "TEST", bytes: [0]),
           "Retry must restore the originally captured bytes")
    expect(recovery.pending == nil && smc.values["TEST"] == [0],
           "Successful verified retry must clear the pending record")
}

for failWrite in [true, false] {
    let smc = FakeSMC()
    if failWrite { smc.writeFailures = [2] } else { smc.readFailures = [2] }
    let recovery = ProbeRestorer(smc: smc)
    expectFailure("Restoration \(failWrite ? "write" : "read") errors must propagate") {
        try recovery.withTestValue(key: "TEST", value: [1]) {}
    }
    expect(recovery.pending == ProbeSnapshot(key: "TEST", bytes: [0]),
           "Every failed rollback step must preserve recovery state")
    try recovery.restore()
    expect(recovery.pending == nil && smc.values["TEST"] == [0],
           "A retry must verify rollback after a transient error")
}

do {
    let smc = FakeSMC()
    smc.writeFailures = [1, 2]
    let recovery = ProbeRestorer(smc: smc)
    let error = expectFailure("Test and rollback errors must both be reported") {
        try recovery.withTestValue(key: "TEST", value: [1]) {}
    }
    let description = String(describing: error)
    expect(description.contains("write failure 1") && description.contains("write failure 2"),
           "A failed rollback must not hide the error that triggered it")
    expect(recovery.pending != nil, "Combined failures must retain the rollback record")
    try recovery.restore()
}

// An interruption or observation failure takes the same serialized rollback
// path; a signal request never performs its own concurrent hardware access.
do {
    let smc = FakeSMC()
    let recovery = ProbeRestorer(smc: smc)
    let interruption = ProbeInterruption()
    let error = expectFailure("Interruption must stop observation and restore") {
        try recovery.withTestValue(key: "TEST", value: [1]) {
            let signalDelivered = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                interruption.request(SIGTERM)
                signalDelivered.signal()
            }
            expect(signalDelivered.wait(timeout: .now() + 1) == .success,
                   "The asynchronous signal request must arrive")
            try interruption.pause(0.01)
        }
    }
    expect((error as? ProbeInterrupted)?.signal == SIGTERM, "Retain the received signal")
    expect(smc.values["TEST"] == [0] && recovery.pending == nil,
           "Interruption must restore and verify the pending value")
    expect(smc.allAccessOnMainThread, "Signal recovery must keep every SMC call on the probe thread")
    interruption.request(SIGINT)
    let repeated = expectFailure("An interruption remains pending") { try interruption.check() }
    expect((repeated as? ProbeInterrupted)?.signal == SIGTERM, "Preserve the first requested signal")
}

do {
    let smc = FakeSMC()
    let recovery = ProbeRestorer(smc: smc)
    expectFailure("Observation errors must propagate after restoration") {
        try recovery.withTestValue(key: "TEST", value: [1]) { throw ProbeFailure("battery unavailable") }
    }
    expect(smc.values["TEST"] == [0] && recovery.pending == nil,
           "Battery read errors during observation must still restore")
}

for invalidValue in [[], [1, 2], Array(repeating: UInt8(1), count: 33)] {
    let smc = FakeSMC()
    let recovery = ProbeRestorer(smc: smc)
    expectFailure("Invalid payload width must fail before writing") {
        try recovery.withTestValue(key: "TEST", value: invalidValue) {}
    }
    expect(smc.writes == 0 && recovery.pending == nil, "Invalid widths cannot modify hardware")
}

do {
    let smc = FakeSMC()
    let recovery = ProbeRestorer(smc: smc)
    smc.readFailures = [1]
    expectFailure("Initial read failure must fail before writing") {
        try recovery.withTestValue(key: "TEST", value: [1]) {}
    }
    expect(smc.writes == 0 && recovery.pending == nil, "No rollback value means no test write")
}

do {
    let smc = FakeSMC()
    let recovery = ProbeRestorer(smc: smc)
    try recovery.withTestValue(key: "TEST", value: [1]) {}
    smc.values["TEST"] = [9]
    let writes = smc.writes
    expectFailure("A second test must reject drift from the verified original") {
        try recovery.withTestValue(key: "TEST", value: [2]) {}
    }
    expect(smc.writes == writes && recovery.pending == nil,
           "Baseline drift must stop before overwriting the changed value")
    let error = expectFailure("The final audit must detect changed values") { _ = try recovery.audit() }
    expect(String(describing: error).contains("final audit read 09; expected 00"),
           "An audit mismatch must report the expected original")
    smc.values["TEST"] = [0]
    smc.readFailures = [smc.reads + 1]
    expectFailure("Final audit read errors cannot be ignored") { _ = try recovery.audit() }
}

expect(ProbeEffect.classify(wasCharging: true, beforeCurrent: 1000,
                           isCharging: false, duringCurrent: -200, isPluggedIn: false)
       == .chargerDisconnected,
       "A disconnected charger must never be called charge-only inhibition")
expect(ProbeEffect.classify(wasCharging: true, beforeCurrent: 1000,
                           isCharging: false, duringCurrent: 0, isPluggedIn: true)
       == .chargingStopped,
       "Charging stopped with external power connected is charge-only inhibition")
expect(ProbeEffect.classify(wasCharging: true, beforeCurrent: 1000,
                           isCharging: true, duringCurrent: 900, isPluggedIn: true)
       == .noEffect, "Ongoing charging must report no effect")
expect(ProbeEffect.classify(wasCharging: true, beforeCurrent: 1000,
                           isCharging: true, duringCurrent: 0, isPluggedIn: true)
       == .chargingStopped, "Current stopping must detect an effect even if the charging flag lags")

print("Probe regression checks passed (\(checks) assertions; fake SMC only).")
