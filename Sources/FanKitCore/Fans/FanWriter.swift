import Foundation

/// Low-level fan writes.
///
/// Writes only succeed when the process is root, so the app routes everything
/// through `FanKitHelper`. On Apple Silicon `F{i}Md` is the only mode key present;
/// Intel Macs additionally expose `FS! `, which is a bitmask over all fans.
public struct FanWriter {
    private let connection: SMCConnection

    public init(connection: SMCConnection) {
        self.connection = connection
    }

    /// Puts one fan under manual control (`forced: true`) or hands it back to
    /// the SMC (`forced: false`).
    public func setForced(_ forced: Bool, fanIndex: Int) throws {
        let modeKey = SMCKey.fanMode(fanIndex)
        if (try? connection.keyInfo(modeKey)) != nil {
            try connection.write(modeKey, bytes: [forced ? 1 : 0])
            return
        }
        // Intel fallback: `FS! ` carries one bit per fan.
        let mask = try controlMask()
        let bit = UInt16(1) << UInt16(fanIndex)
        let updated = forced ? (mask | bit) : (mask & ~bit)
        try connection.write(.fansForceBitmask, bytes: [
            UInt8((updated >> 8) & 0xff), UInt8(updated & 0xff),
        ])
    }

    private func controlMask() throws -> UInt16 {
        let bytes = try connection.read(.fansForceBitmask)
        guard bytes.count >= 2 else { return 0 }
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    /// Writes the target speed. The key's own type decides the encoding.
    public func setTarget(rpm: Double, fanIndex: Int) throws {
        let key = SMCKey.fanTarget(fanIndex)
        let info = try connection.keyInfo(key)
        guard let bytes = SMCCodec.rpmBytes(rpm, type: info.type) else {
            throw SMCError.unsupportedType(info.type)
        }
        try connection.write(key, bytes: bytes)
    }

    /// The speed the SMC currently aims for.
    public func target(fanIndex: Int) throws -> Double {
        let key = SMCKey.fanTarget(fanIndex)
        let info = try connection.keyInfo(key)
        let bytes = try connection.read(key)
        guard let value = SMCCodec.rpm(from: bytes, type: info.type) else {
            throw SMCError.unsupportedType(info.type)
        }
        return value
    }
}
