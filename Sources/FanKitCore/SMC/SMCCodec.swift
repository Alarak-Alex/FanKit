import Foundation

/// Decodes the SMC numeric encodings used by fan and temperature keys.
public enum SMCCodec {
    /// RPM values arrive as `flt ` (Apple Silicon) or `fpe2` (Intel).
    public static func rpm(from bytes: [UInt8], type: SMCDataType) -> Double? {
        switch type {
        case .flt:
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))
        case .fpe2:
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0
        case .ui16:
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case .ui8:
            guard let first = bytes.first else { return nil }
            return Double(first)
        default:
            return nil
        }
    }

    /// Encodes an RPM the way the target key expects.
    public static func rpmBytes(_ rpm: Double, type: SMCDataType) -> [UInt8]? {
        switch type {
        case .flt:
            let bits = Float(rpm).bitPattern
            return [UInt8(bits & 0xff), UInt8((bits >> 8) & 0xff),
                    UInt8((bits >> 16) & 0xff), UInt8((bits >> 24) & 0xff)]
        case .fpe2:
            let scaled = UInt16(clamping: Int((rpm * 4).rounded()))
            return [UInt8(scaled >> 8), UInt8(scaled & 0xff)]
        case .ui16:
            let scaled = UInt16(clamping: Int(rpm.rounded()))
            return [UInt8(scaled >> 8), UInt8(scaled & 0xff)]
        case .ui8:
            return [UInt8(clamping: Int(rpm.rounded()))]
        default:
            return nil
        }
    }

    /// Temperatures use fixed point: `sp78` is signed 8.8, `sp69` is 6.9.
    public static func temperature(from bytes: [UInt8], type: SMCDataType) -> Double? {
        switch type {
        case .sp78:
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case .sp69:
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 64.0
        case .flt:
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))
        default:
            return nil
        }
    }
}