import Foundation

/// Turns a preset plus live temperatures into fan writes.
///
/// The engine is deliberately conservative about changing speed: fans are heavy
/// and audible, so writes are debounced and the ramp is slewed. Spin-up is fast
/// because heat is the risk; spin-down is slow because it is only noise.
public final class ControlEngine {
    /// Tunables, exposed so the settings pane can adjust them later.
    public struct Tuning: Sendable {
        /// Fastest upward ramp, in rpm per second.
        public var risePerSecond: Double = 600
        /// Fastest downward ramp, in rpm per second.
        public var fallPerSecond: Double = 150
        /// Speed changes smaller than this are ignored.
        public var deadband: Double = 20
        /// Minimum gap between two writes to the same fan.
        public var writeInterval: TimeInterval = 1.5
        /// Weight of each new temperature sample in the moving average.
        public var temperatureSmoothing: Double = 0.35

        public init() {}
    }

    private struct FanState {
        var smoothedTemperature: Double?
        var lastWrittenRPM: Double?
        var lastWriteTime: Date = .distantPast
        var lastDesiredRPM: Double
    }

    private var states: [Int: FanState] = [:]
    public var tuning = Tuning()

    public init() {}

    public func reset() {
        states.removeAll()
    }

    /// One evaluation pass. Returns only the fans that need a write now.
    public func evaluate(preset: FanPreset,
                         fans: [FanSnapshot],
                         temperatures: [TemperatureReading],
                         now: Date = Date()) -> [FanCommand] {
        var commands: [FanCommand] = []

        for fan in fans {
            let mode = preset.mode(forFan: fan.id)
            switch mode {
            case .automatic:
                states[fan.id] = nil
                commands.append(FanCommand(fanIndex: fan.id, rpm: 0, forced: false))

            case .constant(let rpm):
                let target = clamp(rpm, for: fan)
                var state = states[fan.id] ?? FanState(smoothedTemperature: nil,
                                                       lastWrittenRPM: nil,
                                                       lastWriteTime: .distantPast,
                                                       lastDesiredRPM: target)
                let elapsed = max(now.timeIntervalSince(state.lastWriteTime), 0)
                // Hold the speed after the first write instead of re-sending it
                // every tick; the SMC keeps the value until something changes it.
                let moved = state.lastWrittenRPM.map {
                    abs($0 - target) >= tuning.deadband
                } ?? true
                if moved && elapsed >= tuning.writeInterval {
                    state.lastWrittenRPM = target
                    state.lastWriteTime = now
                    commands.append(FanCommand(fanIndex: fan.id, rpm: target, forced: true))
                }
                state.lastDesiredRPM = target
                states[fan.id] = state

            case .sensor(let curve):
                guard let raw = TemperatureReader.value(forSensor: curve.sensorID,
                                                        readings: temperatures)
                else { continue }

                var state = states[fan.id] ?? FanState(smoothedTemperature: nil,
                                                       lastWrittenRPM: nil,
                                                       lastWriteTime: .distantPast,
                                                       lastDesiredRPM: fan.minimumRPM)
                let smoothed = state.smoothedTemperature.map {
                    $0 + (raw - $0) * tuning.temperatureSmoothing
                } ?? raw
                state.smoothedTemperature = smoothed

                let span = fan.maximumRPM - fan.minimumRPM
                let desired = clamp(fan.minimumRPM + curve.load(temperature: smoothed) * span,
                                    for: fan)

                // Slew from the last commanded speed, or from where the fan
                // actually is when the engine has not commanded anything yet.
                let reference = state.lastWrittenRPM ?? min(max(fan.actualRPM, fan.minimumRPM),
                                                            fan.maximumRPM)
                let elapsed = max(now.timeIntervalSince(state.lastWriteTime), 0)
                let limit = desired >= reference
                    ? tuning.risePerSecond * max(elapsed, 1)
                    : tuning.fallPerSecond * max(elapsed, 1)
                let slewed = reference + min(max(desired - reference, -limit), limit)
                state.lastDesiredRPM = desired

                let needsWrite = state.lastWrittenRPM == nil
                    || abs(slewed - reference) >= tuning.deadband
                let intervalElapsed = elapsed >= tuning.writeInterval

                if needsWrite && intervalElapsed {
                    state.lastWrittenRPM = slewed
                    state.lastWriteTime = now
                    commands.append(FanCommand(fanIndex: fan.id, rpm: slewed, forced: true))
                }
                states[fan.id] = state
            }
        }
        return commands
    }

    private func clamp(_ rpm: Double, for fan: FanSnapshot) -> Double {
        min(max(rpm.rounded(), fan.minimumRPM), max(fan.maximumRPM, fan.minimumRPM))
    }
}
