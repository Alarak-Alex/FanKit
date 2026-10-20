import Foundation

/// How one fan should be driven.
///
/// The sensor case maps a temperature band linearly onto a speed range between
/// the fan's minimum and maximum.
public enum FanControlMode: Hashable, Sendable, Codable {
    /// Hand the fan back to the SMC's own thermal loop.
    case automatic
    /// Hold one fixed speed.
    case constant(rpm: Double)
    /// Follow a temperature sensor between two speeds.
    case sensor(SensorCurve)

    /// A sensor-driven ramp: `startCelsius` maps to the fan minimum and
    /// `maxCelsius` maps to its maximum.
    public struct SensorCurve: Hashable, Sendable, Codable {
        public var sensorID: String
        public var startCelsius: Double
        public var maxCelsius: Double

        public init(sensorID: String, startCelsius: Double, maxCelsius: Double) {
            self.sensorID = sensorID
            self.startCelsius = startCelsius
            self.maxCelsius = maxCelsius
        }

        /// Fraction of the fan range the current temperature calls for.
        public func load(temperature: Double) -> Double {
            let span = maxCelsius - startCelsius
            guard span > 0 else { return temperature >= maxCelsius ? 1 : 0 }
            return min(max((temperature - startCelsius) / span, 0), 1)
        }
    }

    public var isAutomatic: Bool {
        if case .automatic = self { return true }
        return false
    }

    /// Short label for rows and menu items.
    public var summary: String {
        switch self {
        case .automatic:
            return L10n.string("Automatic")
        case .constant(let rpm):
            return L10n.format("%d rpm", Int(rpm.rounded()))
        case .sensor(let curve):
            return "\(Int(curve.startCelsius.rounded()))–\(Int(curve.maxCelsius.rounded())) °C"
        }
    }
}

/// The target speed for one fan at one instant, plus why.
public struct FanCommand: Sendable {
    public let fanIndex: Int
    public let rpm: Double
    public let forced: Bool

    public init(fanIndex: Int, rpm: Double, forced: Bool) {
        self.fanIndex = fanIndex
        self.rpm = rpm
        self.forced = forced
    }
}

/// Resolves control modes into concrete fan speeds.
public struct FanControlResolver: Sendable {
    /// Fraction of the fan's maximum that a forced speed may never exceed.
    /// Leaving headroom lets the SMC spin the fan up further when it gets hot.
    public var maximumSafeFraction: Double = 1.0

    public init(maximumSafeFraction: Double = 1.0) {
        self.maximumSafeFraction = maximumSafeFraction
    }

    public func command(for fan: FanSnapshot,
                        mode: FanControlMode,
                        temperatures: [TemperatureReading]) -> FanCommand? {
        switch mode {
        case .automatic:
            return FanCommand(fanIndex: fan.id, rpm: 0, forced: false)

        case .constant(let rpm):
            return FanCommand(fanIndex: fan.id,
                              rpm: clamp(rpm, for: fan),
                              forced: true)

        case .sensor(let curve):
            guard let temperature = TemperatureReader.value(forSensor: curve.sensorID,
                                                            readings: temperatures)
            else { return nil }
            let span = fan.maximumRPM - fan.minimumRPM
            let target = fan.minimumRPM + curve.load(temperature: temperature) * span
            return FanCommand(fanIndex: fan.id, rpm: clamp(target, for: fan), forced: true)
        }
    }

    private func clamp(_ rpm: Double, for fan: FanSnapshot) -> Double {
        let ceiling = fan.maximumRPM * maximumSafeFraction
        return min(max(rpm.rounded(), fan.minimumRPM), max(ceiling, fan.minimumRPM))
    }
}
