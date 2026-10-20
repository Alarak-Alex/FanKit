import Foundation

/// What an `SMCConnection` reports for one fan key bound to one index.
public struct FanKeys: Sendable {
    public let index: Int
    public let actual: SMCKey
    public let minimum: SMCKey
    public let maximum: SMCKey
    public let target: SMCKey
    public let mode: SMCKey
    public let identifier: SMCKey

    public init(index: Int) {
        self.index = index
        self.actual = .fanActual(index)
        self.minimum = .fanMinimum(index)
        self.maximum = .fanMaximum(index)
        self.target = .fanTarget(index)
        self.mode = .fanMode(index)
        self.identifier = .fanIdentifier(index)
    }
}

/// Snapshot of one fan at one instant.
public struct FanSnapshot: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let actualRPM: Double
    public let minimumRPM: Double
    public let maximumRPM: Double
    public let targetRPM: Double
    public let isForced: Bool

    public init(id: Int, name: String, actualRPM: Double, minimumRPM: Double,
                maximumRPM: Double, targetRPM: Double, isForced: Bool) {
        self.id = id
        self.name = name
        self.actualRPM = actualRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
        self.isForced = isForced
    }

    /// Position of the current speed inside the fan's usable range, clamped to 0…1.
    public var loadFraction: Double {
        let span = maximumRPM - minimumRPM
        guard span > 0 else { return 0 }
        return min(max((actualRPM - minimumRPM) / span, 0), 1)
    }
}

/// Reads fan topology and values. Split from writing because the two have
/// different privilege requirements.
public struct FanReader {
    private let connection: SMCConnection

    public init(connection: SMCConnection) {
        self.connection = connection
    }

    /// Reads the fan count from `FNum`.
    public func fanCount() throws -> Int {
        let bytes = try connection.read(.fanCount)
        guard let first = bytes.first else { return 0 }
        return Int(first)
    }

    public func snapshot(for index: Int) throws -> FanSnapshot {
        let keys = FanKeys(index: index)

        let actual = try value(keys.actual)
        let minimum = try value(keys.minimum)
        let maximum = try value(keys.maximum)
        let target = (try? value(keys.target)) ?? actual
        let modeByte = try? connection.read(keys.mode).first
        let name = (try? fanName(index: index)) ?? "Fan \(index + 1)"

        return FanSnapshot(
            id: index,
            name: name,
            actualRPM: actual,
            minimumRPM: minimum,
            maximumRPM: maximum,
            targetRPM: target,
            isForced: (modeByte.map { $0 == 1 }) ?? false
        )
    }

    public func snapshots() throws -> [FanSnapshot] {
        let count = try fanCount()
        return (0..<count).compactMap { try? snapshot(for: $0) }
    }

    private func value(_ key: SMCKey) throws -> Double {
        let info = try connection.keyInfo(key)
        let bytes = try connection.read(key)
        guard let value = SMCCodec.rpm(from: bytes, type: info.type) else {
            throw SMCError.unsupportedType(info.type)
        }
        return value
    }

    /// Fan names live in `F{i}ID` as a fixed-width string on Intel Macs.
    /// Apple Silicon exposes no such key, so the caller falls back to a generic label.
    public func fanName(index: Int) throws -> String {
        let key = SMCKey.fanIdentifier(index)
        let bytes = try connection.read(key)
        let trimmed = bytes.prefix { $0 != 0 }
        guard !trimmed.isEmpty else { throw SMCError.requestFailed(key, kIOReturnNotFound) }
        return String(decoding: trimmed, as: UTF8.self)
    }
}