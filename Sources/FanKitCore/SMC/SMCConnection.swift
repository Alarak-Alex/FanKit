import Foundation
import IOKit

/// The 80-byte (`0x50`) request/reply struct the `AppleSMC` user client exchanges.
///
/// Offsets verified with a C probe on this machine:
/// `keyInfo.dataSize` 28, `dataType` 32, `dataAttributes` 36, `result` 40,
/// `status` 41, `data8` 42, `data32` 44, `bytes` 48.
///
/// The padding fields are load-bearing: `vers` is six bytes and `keyInfo` is
/// twelve, so the kernel struct relies on natural alignment to place `result`
/// at 40. Swift does not reuse C's padding silently, so it is spelled out.
struct SMCKeyData {
    var key: UInt32 = 0
    var versMajor: UInt8 = 0
    var versMinor: UInt8 = 0
    var versBuild: UInt8 = 0
    var versReserved: UInt8 = 0
    var versRelease: UInt16 = 0
    var paddingAfterVersion: UInt16 = 0

    var limitVersion: UInt16 = 0
    var limitLength: UInt16 = 0
    var limitCPU: UInt32 = 0
    var limitGPU: UInt32 = 0
    var limitMemory: UInt32 = 0

    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var paddingAfterAttributes: (UInt8, UInt8, UInt8) = (0, 0, 0)

    var result: UInt8 = 0
    var status: UInt8 = 0
    /// Selects the operation: 5 = read bytes, 6 = write bytes, 8 = key by index, 9 = read key info.
    var data8: UInt8 = 0
    var paddingAfterData8: UInt8 = 0
    var data32: UInt32 = 0

    var payload: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    init() {}

    /// The full 32-byte payload window, before truncation to a key's real size.
    var payloadBytes: [UInt8] {
        withUnsafeBytes(of: payload) { Array($0) }
    }

    mutating func setBytes(_ source: [UInt8]) {
        var padded = [UInt8](repeating: 0, count: 32)
        for (index, byte) in source.prefix(32).enumerated() {
            padded[index] = byte
        }
        payload = (padded[0], padded[1], padded[2], padded[3],
                   padded[4], padded[5], padded[6], padded[7],
                   padded[8], padded[9], padded[10], padded[11],
                   padded[12], padded[13], padded[14], padded[15],
                   padded[16], padded[17], padded[18], padded[19],
                   padded[20], padded[21], padded[22], padded[23],
                   padded[24], padded[25], padded[26], padded[27],
                   padded[28], padded[29], padded[30], padded[31])
    }

    /// Fails loudly at development time if the layout ever drifts from the kernel ABI.
    static func validateLayout() {
        assert(MemoryLayout<SMCKeyData>.size == 80, "SMCKeyData must be 80 bytes")
        assert(MemoryLayout<SMCKeyData>.offset(of: \.dataSize) == 28)
        assert(MemoryLayout<SMCKeyData>.offset(of: \.dataType) == 32)
        assert(MemoryLayout<SMCKeyData>.offset(of: \.dataAttributes) == 36)
        assert(MemoryLayout<SMCKeyData>.offset(of: \.result) == 40)
        assert(MemoryLayout<SMCKeyData>.offset(of: \.status) == 41)
        assert(MemoryLayout<SMCKeyData>.offset(of: \.data8) == 42)
        assert(MemoryLayout<SMCKeyData>.offset(of: \.data32) == 44)
        assert(MemoryLayout<SMCKeyData>.offset(of: \.payload) == 48)
    }
}

public enum SMCError: Error, CustomStringConvertible {
    case serviceNotFound
    case connectionFailed(kern_return_t)
    case requestFailed(SMCKey, kern_return_t)
    case unsupportedSize(Int)
    case unsupportedType(SMCDataType)
    case writeNotPermitted(SMCKey)

    public var description: String {
        switch self {
        case .serviceNotFound:
            return "AppleSMC service was not found in the IORegistry"
        case .connectionFailed(let code):
            return "IOServiceOpen failed: \(Self.kern(code))"
        case .requestFailed(let key, let code):
            return "SMC request for \(key) failed: \(Self.kern(code))"
        case .unsupportedSize(let size):
            return "Unsupported SMC data size: \(size)"
        case .unsupportedType(let type):
            return "Unsupported SMC data type: \(type)"
        case .writeNotPermitted(let key):
            return "Writing \(key) requires the privileged helper"
        }
    }

    static func kern(_ code: kern_return_t) -> String {
        String(format: "0x%08x", UInt32(bitPattern: code))
    }
}

/// A read/write channel to `AppleSMC`.
///
/// Reads work from a normal user process. Writes are rejected by the kernel
/// (`kIOReturnNotPrivileged`) and must be routed through a privileged helper.
public final class SMCConnection {
    /// Selector 2 carries the `ReadKey`/`WriteKey` struct methods.
    private static let smcSelector: UInt32 = 2

    private var connection: io_connect_t = 0
    private let lock = NSLock()

    public init() throws {
        SMCKeyData.validateLayout()

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSMC")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess else {
            throw SMCError.connectionFailed(result)
        }
        defer { IOObjectRelease(iterator) }

        let device = IOIteratorNext(iterator)
        guard device != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(device) }

        var handle: io_connect_t = 0
        let opened = IOServiceOpen(device, mach_task_self_, 0, &handle)
        guard opened == kIOReturnSuccess else {
            throw SMCError.connectionFailed(opened)
        }
        connection = handle
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    private func call(_ input: SMCKeyData) throws -> SMCKeyData {
        var request = input
        var reply = SMCKeyData()
        var size = MemoryLayout<SMCKeyData>.size
        let result = withUnsafePointer(to: &request) { requestPointer in
            withUnsafeMutablePointer(to: &reply) { replyPointer in
                IOConnectCallStructMethod(
                    connection,
                    Self.smcSelector,
                    requestPointer,
                    MemoryLayout<SMCKeyData>.size,
                    replyPointer,
                    &size
                )
            }
        }
        guard result == kIOReturnSuccess else {
            throw SMCError.requestFailed(SMCKey(request.key), result)
        }
        return reply
    }

    public func keyInfo(_ key: SMCKey) throws -> (size: Int, type: SMCDataType, attributes: UInt8) {
        lock.lock()
        defer { lock.unlock() }
        let reply = try keyInfoLocked(key)
        return (Int(reply.dataSize), SMCDataType(rawValue: reply.dataType), reply.dataAttributes)
    }

    private func keyInfoLocked(_ key: SMCKey) throws -> SMCKeyData {
        var request = SMCKeyData()
        request.key = key.rawValue
        request.data8 = 9
        return try call(request)
    }

    /// Two-step read: ask for the key's shape, then fetch its payload.
    public func read(_ key: SMCKey) throws -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }

        let info = try keyInfoLocked(key)
        var request = SMCKeyData()
        request.key = key.rawValue
        request.dataSize = info.dataSize
        request.dataType = info.dataType
        request.dataAttributes = info.dataAttributes
        request.data8 = 5
        let reply = try call(request)
        // The reply echoes the key's shape; its own `dataSize` is not reliable,
        // so the payload is truncated with the size obtained from `keyInfo`.
        return Array(reply.payloadBytes.prefix(Int(info.dataSize)))
    }

    public func write(_ key: SMCKey, bytes: [UInt8]) throws {
        lock.lock()
        defer { lock.unlock() }

        let info = try keyInfoLocked(key)
        guard bytes.count == Int(info.dataSize) else {
            throw SMCError.unsupportedSize(bytes.count)
        }

        var request = SMCKeyData()
        request.key = key.rawValue
        request.dataSize = info.dataSize
        request.dataType = info.dataType
        request.dataAttributes = info.dataAttributes
        request.data8 = 6
        request.setBytes(bytes)

        do {
            _ = try call(request)
        } catch let error as SMCError {
            if case .requestFailed(_, let code) = error, code == kIOReturnNotPrivileged {
                throw SMCError.writeNotPermitted(key)
            }
            throw error
        }
    }

    /// Every key the SMC exposes, by walking `#KEY` and asking for each index.
    public func allKeys() throws -> [SMCKey] {
        let countBytes = try read(.keyCount)
        guard countBytes.count >= 4 else { return [] }
        let count = (UInt32(countBytes[0]) << 24) | (UInt32(countBytes[1]) << 16)
            | (UInt32(countBytes[2]) << 8) | UInt32(countBytes[3])

        var keys: [SMCKey] = []
        keys.reserveCapacity(Int(count))

        lock.lock()
        defer { lock.unlock() }
        for index in 0..<count {
            var request = SMCKeyData()
            request.data8 = 8
            request.data32 = index
            guard let reply = try? call(request) else { continue }
            keys.append(SMCKey(reply.key))
        }
        return keys
    }
}