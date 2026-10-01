import Foundation

struct Candidate: Equatable {
    let key: String
    let test: [UInt8]
    let why: String
}

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum ProbeArguments {
    case help
    case run([Candidate])

    static func parse(_ arguments: [String], defaults: [Candidate]) throws -> ProbeArguments {
        if arguments == ["--help"] || arguments == ["-h"] { return .help }
        var key: String?
        var value: [UInt8]?
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard flag == "--key" || flag == "--value" else {
                throw ProbeFailure("Unknown argument: \(flag)")
            }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw ProbeFailure("\(flag) needs a value")
            }
            let argument = arguments[index + 1]
            if flag == "--key" {
                guard key == nil else { throw ProbeFailure("--key may only be specified once") }
                let bytes = Array(argument.utf8)
                guard bytes.count == 4, bytes.allSatisfy({ (0x20...0x7e).contains($0) }) else {
                    throw ProbeFailure("--key must contain exactly four printable ASCII bytes")
                }
                key = argument
            } else {
                guard value == nil else { throw ProbeFailure("--value may only be specified once") }
                value = try parseHex(argument)
            }
            index += 2
        }
        guard let key else {
            guard value == nil else { throw ProbeFailure("--value requires --key") }
            return .run(defaults)
        }
        return .run([Candidate(key: key, test: value ?? [0x01], why: "specified on the command line")])
    }

    static func parseHex(_ text: String) throws -> [UInt8] {
        let groups = text.split(whereSeparator: { $0.isWhitespace })
        var result: [UInt8] = []
        for group in groups {
            let digits = group.hasPrefix("0x") || group.hasPrefix("0X") ? group.dropFirst(2) : group[...]
            let bytes = Array(digits.utf8)
            guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else {
                throw ProbeFailure("--value must contain complete hexadecimal byte pairs")
            }
            func nibble(_ byte: UInt8) -> UInt8? {
                switch byte {
                case 48...57: return byte - 48
                case 65...70: return byte - 65 + 10
                case 97...102: return byte - 97 + 10
                default: return nil
                }
            }
            for index in stride(from: 0, to: bytes.count, by: 2) {
                guard let high = nibble(bytes[index]), let low = nibble(bytes[index + 1]) else {
                    throw ProbeFailure("--value contains a non-hexadecimal byte")
                }
                result.append((high << 4) | low)
            }
        }
        guard (1...32).contains(result.count) else {
            throw ProbeFailure("--value must contain between 1 and 32 bytes")
        }
        return result
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

protocol ProbeSMC {
    func read(_ key: String) throws -> [UInt8]
    func write(_ key: String, bytes: [UInt8]) throws
}

struct ProbeSnapshot: Equatable {
    let key: String
    let bytes: [UInt8]
}

/// All SMC access stays on the calling thread, including interruption cleanup.
/// An unsuccessful write may still have changed hardware, so it also rolls back.
final class ProbeRestorer {
    private let smc: ProbeSMC
    private var originals: [String: [UInt8]] = [:]
    private(set) var pending: ProbeSnapshot?

    init(smc: ProbeSMC) { self.smc = smc }

    func withTestValue<T>(key: String, value: [UInt8], observe: () throws -> T) throws -> T {
        guard pending == nil else { throw ProbeFailure("A previous key still needs restoration") }
        let original = try smc.read(key)
        guard (1...32).contains(value.count), original.count == value.count else {
            throw ProbeFailure("\(key): test and original must have the same width, from 1 to 32 bytes")
        }
        if let baseline = originals[key], baseline != original {
            throw ProbeFailure("\(key): value changed since its verified restoration")
        }
        originals[key] = original
        pending = ProbeSnapshot(key: key, bytes: original)

        let result: T
        do {
            try smc.write(key, bytes: value)
            result = try observe()
        } catch {
            let operationError = error
            do { try restore() } catch {
                throw ProbeFailure("\(operationError); restoration also failed: \(error)")
            }
            throw operationError
        }
        try restore()
        return result
    }

    @discardableResult
    func restore() throws -> ProbeSnapshot? {
        guard let snapshot = pending else { return nil }
        try smc.write(snapshot.key, bytes: snapshot.bytes)
        let actual = try smc.read(snapshot.key)
        guard actual == snapshot.bytes else {
            throw ProbeFailure("\(snapshot.key): restore read back \(hex(actual)); expected \(hex(snapshot.bytes))")
        }
        // Preserve the rollback record until both the write and readback succeed.
        pending = nil
        return snapshot
    }

    func audit() throws -> [ProbeSnapshot] {
        guard pending == nil else { throw ProbeFailure("A key still needs restoration") }
        return try originals.keys.sorted().map { key in
            let actual = try smc.read(key)
            guard actual == originals[key] else {
                throw ProbeFailure("\(key): final audit read \(hex(actual)); expected \(hex(originals[key]!))")
            }
            return ProbeSnapshot(key: key, bytes: actual)
        }
    }
}

struct ProbeInterrupted: Error {
    let signal: Int32
}

/// Dispatch signal sources set this flag; the probe checks it between SMC calls.
final class ProbeInterruption {
    private let lock = NSLock()
    private var requestedSignal: Int32?

    func request(_ signal: Int32) {
        lock.lock()
        if requestedSignal == nil { requestedSignal = signal }
        lock.unlock()
    }

    func check() throws {
        lock.lock()
        let signal = requestedSignal
        lock.unlock()
        if let signal { throw ProbeInterrupted(signal: signal) }
    }

    func pause(_ seconds: Double) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while true {
            try check()
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { return }
            Thread.sleep(forTimeInterval: min(0.1, remaining))
        }
    }
}

enum ProbeEffect: String {
    case noEffect = "no effect on charging"
    case chargerDisconnected = "CHARGER DISCONNECTED (not charge-only inhibition)"
    case chargingStopped = "CHARGING STOPPED while external power stayed connected"

    static func classify(wasCharging: Bool, beforeCurrent: Int,
                         isCharging: Bool, duringCurrent: Int, isPluggedIn: Bool) -> ProbeEffect {
        if !isPluggedIn { return .chargerDisconnected }
        if (wasCharging && !isCharging) || (beforeCurrent > 200 && duringCurrent <= 0) {
            return .chargingStopped
        }
        return .noEffect
    }
}
