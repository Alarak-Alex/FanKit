import Foundation

/// A four-character SMC key, packed big-endian exactly like `(c0 << 24) | (c1 << 16) | (c2 << 8) | c3`.
public struct SMCKey: Hashable, CustomStringConvertible, Sendable {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ string: String) {
        precondition(string.utf8.count == 4, "SMC keys are exactly four ASCII characters")
        var value: UInt32 = 0
        for byte in string.utf8 {
            value = (value << 8) | UInt32(byte)
        }
        self.rawValue = value
    }

    public var string: String {
        let bytes: [UInt8] = [
            UInt8((rawValue >> 24) & 0xff),
            UInt8((rawValue >> 16) & 0xff),
            UInt8((rawValue >> 8) & 0xff),
            UInt8(rawValue & 0xff),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    public var description: String { string }

    // MARK: - Fan keys
    //
    // Fan keys use the classic per-fan naming: `F<index>` plus a two-letter
    // suffix such as `Ac`, `Mn`, `Mx`, `Tg` or `Md`.

    public static func fanActual(_ index: Int) -> SMCKey { .init("F\(index)Ac") }
    public static func fanMinimum(_ index: Int) -> SMCKey { .init("F\(index)Mn") }
    public static func fanMaximum(_ index: Int) -> SMCKey { .init("F\(index)Mx") }
    public static func fanTarget(_ index: Int) -> SMCKey { .init("F\(index)Tg") }
    /// 0 = automatic, 1 = forced/manual. Present on Apple Silicon.
    public static func fanMode(_ index: Int) -> SMCKey { .init("F\(index)Md") }
    public static func fanIdentifier(_ index: Int) -> SMCKey { .init("F\(index)ID") }
    public static func fanSafe(_ index: Int) -> SMCKey { .init("F\(index)Sf") }

    public static let fanCount = SMCKey("FNum")
    /// Bitmask of forced fans. Absent on Apple Silicon, where `F{i}Md` is used instead.
    public static let fansForceBitmask = SMCKey("FS! ")
    public static let keyCount = SMCKey("#KEY")
}

/// The `dataType` an SMC key reports.
///
/// The value is the four type characters packed in the same big-endian order as
/// a key, so `flt ` arrives as `0x666c7420`.
public struct SMCDataType: Hashable, CustomStringConvertible, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ string: String) {
        var value: UInt32 = 0
        for byte in string.utf8 {
            value = (value << 8) | UInt32(byte)
        }
        self.rawValue = value
    }

    public var string: String {
        let bytes: [UInt8] = [
            UInt8((rawValue >> 24) & 0xff),
            UInt8((rawValue >> 16) & 0xff),
            UInt8((rawValue >> 8) & 0xff),
            UInt8(rawValue & 0xff),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    public var description: String { string }

    public static let fpe2 = SMCDataType("fpe2")
    public static let flt = SMCDataType("flt ")
    public static let ui8 = SMCDataType("ui8 ")
    public static let ui16 = SMCDataType("ui16")
    public static let ui32 = SMCDataType("ui32")
    public static let sp78 = SMCDataType("sp78")
    public static let sp69 = SMCDataType("sp69")
}
