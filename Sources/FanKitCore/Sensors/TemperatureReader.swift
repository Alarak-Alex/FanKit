import CHIDTemperature
import Foundation

/// One temperature reading, with enough context for the UI to group and label it.
public struct TemperatureReading: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case cpu
        case gpu
        case memory
        case storage
        case power
        case battery
        case ambient
        case other

        public var displayName: String {
            switch self {
            case .cpu: return L10n.string("CPU")
            case .gpu: return L10n.string("GPU")
            case .memory: return L10n.string("Memory")
            case .storage: return L10n.string("Storage")
            case .power: return L10n.string("Power")
            case .battery: return L10n.string("Battery")
            case .ambient: return L10n.string("Ambient")
            case .other: return L10n.string("Other")
            }
        }

        /// Sort order for grouped presentation.
        public var rank: Int {
            switch self {
            case .cpu: return 0
            case .gpu: return 1
            case .power: return 2
            case .memory: return 3
            case .storage: return 4
            case .battery: return 5
            case .ambient: return 6
            case .other: return 7
            }
        }

        /// SF Symbol used in the sensor list.
        public var symbolName: String {
            switch self {
            case .cpu: return "cpu"
            case .gpu: return "square.stack.3d.up"
            case .memory: return "memorychip"
            case .storage: return "internaldrive"
            case .power: return "bolt"
            case .battery: return "battery.75percent"
            case .ambient: return "thermometer.medium"
            case .other: return "sensor"
            }
        }
    }

    public let id: String
    public let name: String
    public let celsius: Double
    public let group: Group

    public init(id: String, name: String, celsius: Double, group: Group) {
        self.id = id
        self.name = name
        self.celsius = celsius
        self.group = group
    }
}

/// Reads temperatures from the HID thermal services.
///
/// On Apple Silicon the SMC exposes almost no temperature keys; the sensors are
/// published as HID event services with `PrimaryUsagePage 0xff00`, `PrimaryUsage 5`.
/// The event API is called through a small C shim because `IOHIDEvent.h` is no
/// longer part of the public SDK and the Swift `dlsym` bridge does not carry the
/// opaque pointer arguments correctly.
///
/// On Intel Macs the SMC key table (`TC0P`, `TG0D`, …) is the primary source and
/// is used as a fallback when HID reports nothing.
public enum TemperatureReader {
    /// Aggregate identifier for the CPU-group average used by sensor presets.
    public static let cpuAverageID = "cpu_average"

    /// Sensor names mapped to the group they belong to. Longer prefixes win, so
    /// the list is sorted before use.
    private static let nameGroups: [(prefix: String, group: TemperatureReading.Group)] = [
        ("PMU2 tdie", .cpu),
        ("PMU2 tdev", .cpu),
        ("PMU tdie", .cpu),
        ("PMU tdev", .cpu),
        ("SOC MTR", .cpu),
        ("pACC", .cpu),
        ("eACC", .cpu),
        ("tcal", .other),
        ("NAND", .storage),
        ("SSD", .storage),
        ("gas gauge", .battery),
        ("battery", .battery),
        ("Charger", .power),
        ("GPU", .gpu),
        ("gpu", .gpu),
        ("ANE", .other),
        ("ISP", .other),
    ].sorted { $0.prefix.count > $1.prefix.count }

    /// Intel SMC keys worth probing, in preference order per group.
    private static let smcFallbackKeys: [(key: SMCKey, name: String, group: TemperatureReading.Group)] = [
        (.init("TC0P"), "CPU Proximity", .cpu),
        (.init("TC0D"), "CPU Die", .cpu),
        (.init("TC0E"), "CPU Die 2", .cpu),
        (.init("TG0P"), "GPU Proximity", .gpu),
        (.init("TG0D"), "GPU Die", .gpu),
        (.init("TM0P"), "Memory Proximity", .memory),
        (.init("TB0T"), "Battery", .battery),
        (.init("TH0A"), "Drive", .storage),
    ]

    /// Reads every temperature sensor. HID first, SMC as the Intel fallback.
    public static func read(connection: SMCConnection? = nil) -> [TemperatureReading] {
        let hid = readHID()
        if !hid.isEmpty { return hid }
        guard let connection else { return [] }
        return readSMC(connection: connection)
    }

    public static func readHID() -> [TemperatureReading] {
        var buffer = [fankit_temperature](
            repeating: fankit_temperature(name: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
                                     celsius: 0),
            count: 128
        )

        let count = Int(fankit_read_temperatures(&buffer, Int32(buffer.count)))
        guard count > 0 else { return [] }

        var readings: [TemperatureReading] = []
        readings.reserveCapacity(count)
        for entry in buffer.prefix(count) {
            let name = withUnsafePointer(to: entry.name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
            }
            guard !name.isEmpty else { continue }
            readings.append(
                TemperatureReading(
                    id: "hid:\(name)",
                    name: name,
                    celsius: entry.celsius,
                    group: group(for: name)
                )
            )
        }
        return readings
    }

    public static func readSMC(connection: SMCConnection) -> [TemperatureReading] {
        smcFallbackKeys.compactMap { entry in
            guard let info = try? connection.keyInfo(entry.key),
                  let bytes = try? connection.read(entry.key),
                  let celsius = SMCCodec.temperature(from: bytes, type: info.type),
                  celsius > -20, celsius < 150
            else { return nil }
            return TemperatureReading(
                id: "smc:\(entry.key.string)",
                name: entry.name,
                celsius: celsius,
                group: entry.group
            )
        }
    }

    /// The reading a sensor preset should follow: the CPU group average.
    public static func cpuAverage(from readings: [TemperatureReading]) -> Double? {
        let cpu = readings.filter { $0.group == .cpu }.map(\.celsius)
        guard !cpu.isEmpty else { return nil }
        return cpu.reduce(0, +) / Double(cpu.count)
    }

    /// Resolves a stored sensor identifier to a live value.
    ///
    /// Supported identifiers are `cpu_average`, `hottest`, or an exact sensor
    /// name / reading id such as `PMU tdie1`.
    public static func value(forSensor identifier: String, readings: [TemperatureReading]) -> Double? {
        switch identifier {
        case cpuAverageID:
            return cpuAverage(from: readings)
        case "hottest":
            return readings.map(\.celsius).max()
        default:
            return readings.first { $0.id == identifier || $0.name == identifier }?.celsius
        }
    }

    private static func group(for name: String) -> TemperatureReading.Group {
        for entry in nameGroups where name.localizedCaseInsensitiveContains(entry.prefix) {
            return entry.group
        }
        return .other
    }
}
