import Foundation
import IOKit

/// Minimal AppleSMC client. Reads are unprivileged; writes require root.
///
/// The struct layout below mirrors AppleSMC's `SMCParamStruct` exactly — field
/// order and padding both matter, and `Connection.init` asserts the size.
enum SMCError: Error, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(key: String, kern_return_t)
    case keyNotFound(String)
    case smcError(key: String, UInt8)
    case notWritable(String)
    case sizeMismatch(key: String, expected: Int, got: Int)

    var description: String {
        switch self {
        case .serviceNotFound: return "AppleSMC service not found"
        case .openFailed(let kr): return String(format: "IOServiceOpen failed (0x%x)", kr)
        case .callFailed(let key, let kr): return String(format: "%@: call failed (0x%x)", key, kr)
        case .keyNotFound(let key): return "\(key): key not present on this machine"
        case .smcError(let key, let r): return "\(key): SMC returned result \(r)"
        case .notWritable(let key): return "\(key): key is not writable"
        case .sizeMismatch(let key, let e, let g): return "\(key): expected \(e) bytes, got \(g)"
        }
    }
}

private struct SMCVersion {
    var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
    var release: UInt16 = 0
}
private struct SMCPLimitData {
    var version: UInt16 = 0, length: UInt16 = 0
    var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
}
private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0
}
private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

struct SMCKeyInfo {
    var size: Int
    var type: String
    var attributes: UInt8
    /// SMC attribute bit 0x40 marks a key the firmware will accept writes for.
    var isWritable: Bool { attributes & 0x40 != 0 }
    var isReadable: Bool { attributes & 0x80 != 0 }
}

final class SMC {
    private var connection: io_connect_t = 0

    private static let kRead: UInt8 = 5
    private static let kWrite: UInt8 = 6
    private static let kGetKeyInfo: UInt8 = 9
    private static let kSuccess: UInt8 = 0
    private static let kKeyNotFound: UInt8 = 132

    init() throws {
        precondition(MemoryLayout<SMCParamStruct>.size == 80,
                     "SMCParamStruct must match the C layout (80 bytes)")
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == kIOReturnSuccess else { throw SMCError.openFailed(kr) }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func typeString(_ v: UInt32) -> String {
        let b = [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff),
                 UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        return String(bytes: b.filter { $0 != 0 }, encoding: .ascii) ?? "?"
    }

    private func call(_ input: inout SMCParamStruct, key: String) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.size
        let kr = IOConnectCallStructMethod(connection, 2, &input,
                                           MemoryLayout<SMCParamStruct>.size,
                                           &output, &outSize)
        guard kr == kIOReturnSuccess else { throw SMCError.callFailed(key: key, kr) }
        return output
    }

    func info(_ key: String) throws -> SMCKeyInfo {
        var input = SMCParamStruct()
        input.key = Self.fourCC(key)
        input.data8 = Self.kGetKeyInfo
        let out = try call(&input, key: key)
        if out.result == Self.kKeyNotFound { throw SMCError.keyNotFound(key) }
        guard out.result == Self.kSuccess else { throw SMCError.smcError(key: key, out.result) }
        return SMCKeyInfo(size: Int(out.keyInfo.dataSize),
                          type: Self.typeString(out.keyInfo.dataType),
                          attributes: out.keyInfo.dataAttributes)
    }

    func read(_ key: String) throws -> [UInt8] {
        let meta = try info(key)
        var input = SMCParamStruct()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = UInt32(meta.size)
        input.data8 = Self.kRead
        let out = try call(&input, key: key)
        guard out.result == Self.kSuccess else { throw SMCError.smcError(key: key, out.result) }
        // The payload is a fixed 32-byte C tuple. Reading it as raw bytes drops
        // both the reflection and the force-cast that went with it, and
        // `prefix` clamps if the firmware ever declares a longer key.
        return withUnsafeBytes(of: out.bytes) { Array($0.prefix(meta.size)) }
    }

    /// Requires root. Refuses keys the firmware doesn't advertise as writable,
    /// and refuses a payload that isn't exactly the key's declared width.
    func write(_ key: String, bytes: [UInt8]) throws {
        let meta = try info(key)
        guard meta.isWritable else { throw SMCError.notWritable(key) }
        guard bytes.count == meta.size else {
            throw SMCError.sizeMismatch(key: key, expected: meta.size, got: bytes.count)
        }
        var input = SMCParamStruct()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = UInt32(meta.size)
        input.data8 = Self.kWrite
        withUnsafeMutableBytes(of: &input.bytes) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
        }
        let out = try call(&input, key: key)
        guard out.result == Self.kSuccess else { throw SMCError.smcError(key: key, out.result) }
    }
}
