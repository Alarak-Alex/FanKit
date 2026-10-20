import Foundation

/// A named set of per-fan modes.
public struct FanPreset: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var modes: [FanControlMode]

    public init(id: UUID = UUID(), name: String, modes: [FanControlMode]) {
        self.id = id
        self.name = name
        self.modes = modes
    }

    /// A preset sized to the machine's fan count, all automatic.
    public static func automatic(fanCount: Int) -> FanPreset {
        FanPreset(name: L10n.string("Automatic"),
                  modes: Array(repeating: .automatic, count: fanCount))
    }

    /// Names that belong to the built-in presets and should follow the UI language.
    private static let builtInNames: Set<String> = [
        "Balanced", "Quiet", "Automatic", "均衡", "安静", "自动",
    ]

    /// The preset name as it should be shown. Built-in presets are translated;
    /// names the user typed are kept verbatim.
    public var displayName: String {
        Self.builtInNames.contains(name) ? L10n.string(name) : name
    }

    public func mode(forFan index: Int) -> FanControlMode {
        guard modes.indices.contains(index) else { return .automatic }
        return modes[index]
    }

    /// Pads or trims the mode list so it matches the detected fan count.
    public func resized(to count: Int) -> FanPreset {
        var updated = self
        if modes.count < count {
            updated.modes += Array(repeating: .automatic, count: count - modes.count)
        } else if modes.count > count {
            updated.modes = Array(modes.prefix(count))
        }
        return updated
    }

    /// True when every fan is left to the SMC.
    public var isFullyAutomatic: Bool {
        modes.allSatisfy(\.isAutomatic)
    }

    // MARK: - Preset string format
    //
    // `base64(name|mode|mode|…)`, where a mode is `0` (automatic),
    // `1,<rpm>` (constant) or `2,<sensor>,<start>,<max>` (sensor).
    // An unsaved preset uses the literal name `UNSAVED`.

    public var serialized: String {
        let parts = [name] + modes.map(\.wireForm)
        let joined = parts.joined(separator: "|")
        return Data(joined.utf8).base64EncodedString()
    }

    public init?(serialized: String) {
        guard let data = Data(base64Encoded: serialized),
              let decoded = String(data: data, encoding: .utf8)
        else { return nil }
        let parts = decoded.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        var modes: [FanControlMode] = []
        for part in parts.dropFirst() {
            guard let mode = FanControlMode(wireForm: part) else { return nil }
            modes.append(mode)
        }
        self.id = UUID()
        self.name = parts[0]
        self.modes = modes
    }
}

extension FanControlMode {
    /// The string form stored in a preset.
    var wireForm: String {
        switch self {
        case .automatic:
            return "0"
        case .constant(let rpm):
            return "1,\(Int(rpm.rounded()))"
        case .sensor(let curve):
            return "2,\(curve.sensorID),\(Int(curve.startCelsius.rounded())),\(Int(curve.maxCelsius.rounded()))"
        }
    }

    init?(wireForm: String) {
        let fields = wireForm.split(separator: ",").map(String.init)
        guard let kind = fields.first else { return nil }
        switch kind {
        case "0":
            self = .automatic
        case "1":
            guard fields.count >= 2, let rpm = Double(fields[1]) else { return nil }
            self = .constant(rpm: rpm)
        case "2":
            guard fields.count >= 4,
                  let start = Double(fields[2]),
                  let maximum = Double(fields[3])
            else { return nil }
            self = .sensor(.init(sensorID: fields[1],
                                 startCelsius: start,
                                 maxCelsius: maximum))
        default:
            return nil
        }
    }
}

/// Persists presets in Application Support.
public final class PresetStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FanKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("presets.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public var url: URL { fileURL }

    public func load() -> [FanPreset] {
        guard let data = try? Data(contentsOf: fileURL),
              let presets = try? decoder.decode([FanPreset].self, from: data)
        else { return [] }
        return presets
    }

    public func save(_ presets: [FanPreset]) throws {
        let data = try encoder.encode(presets)
        try data.write(to: fileURL, options: .atomic)
    }
}
