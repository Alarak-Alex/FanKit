import FanKitCore
import SwiftUI

/// One fan: current speed, the range it can use, and how it is being driven.
struct FanRow: View {
    let fan: FanSnapshot
    let mode: FanControlMode
    let temperature: Double?
    let isLive: Bool
    let onChange: (FanControlMode) -> Void

    @State private var draftRPM: Double
    @State private var isEditing = false

    init(fan: FanSnapshot,
         mode: FanControlMode,
         temperature: Double?,
         isLive: Bool,
         onChange: @escaping (FanControlMode) -> Void) {
        self.fan = fan
        self.mode = mode
        self.temperature = temperature
        self.isLive = isLive
        self.onChange = onChange
        let fallback = mode.constantRPM ?? fan.minimumRPM
        _draftRPM = State(initialValue: fallback)
    }

    private var accent: Color {
        switch mode {
        case .automatic: return .secondary
        case .constant: return Color(red: 0.36, green: 0.56, blue: 0.96)
        case .sensor: return ThermalPalette.color(for: temperature)
        }
    }

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    RingGauge(fraction: fan.loadFraction,
                              tint: mode.isAutomatic ? .secondary : accent,
                              lineWidth: 8,
                              size: 56)
                        .overlay {
                            Image(systemName: "fanblades.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(mode.isAutomatic ? .secondary : accent)
                                .rotationEffect(.degrees(isLive ? 0 : 0))
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(fan.name)
                                .font(.system(size: 14, weight: .semibold))
                            StatusPill(
                                text: fan.isForced ? L10n.string("Manual") : L10n.string("SMC"),
                                tint: fan.isForced ? accent : .secondary,
                                symbol: fan.isForced ? "hand.raised.fill" : "checkmark.seal.fill"
                            )
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(fan.actualRPM.rounded()))")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: fan.actualRPM))
                            Text("rpm")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("· " + L10n.format("target %d", Int(fan.targetRPM.rounded())))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(fan.minimumRPM.rounded()))–\(Int(fan.maximumRPM.rounded()))")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(L10n.string("rpm range"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Picker(L10n.string("Fan control"), selection: Binding(
                    get: { ModeTag(mode) },
                    set: { tag in apply(tag) }
                )) {
                    Text(L10n.string("Automatic")).tag(ModeTag.automatic)
                    Text(L10n.string("Constant")).tag(ModeTag.constant)
                    Text(L10n.string("Sensor")).tag(ModeTag.sensor)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch mode {
                case .automatic:
                    Text(L10n.string("The SMC keeps this fan at the speed macOS asks for."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                case .constant:
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.string("Speed"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(L10n.format("%d rpm", Int(draftRPM.rounded())))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(accent)
                        }
                        Slider(value: Binding(
                            get: { draftRPM },
                            set: { newValue in
                                draftRPM = newValue
                                onChange(.constant(rpm: newValue.rounded()))
                            }
                        ), in: fan.minimumRPM...max(fan.maximumRPM, fan.minimumRPM + 1), step: 25)
                        .tint(accent)
                    }

                case .sensor(let curve):
                    SensorCurveEditor(fan: fan,
                                      curve: curve,
                                      temperature: temperature,
                                      accent: accent,
                                      onChange: { onChange(.sensor($0)) })
                }
            }
        }
        .onChange(of: mode) { _, newValue in
            if let rpm = newValue.constantRPM {
                draftRPM = min(max(rpm, fan.minimumRPM), fan.maximumRPM)
            }
        }
    }

    private func apply(_ tag: ModeTag) {
        switch tag {
        case .automatic:
            onChange(.automatic)
        case .constant:
            let start = mode.constantRPM ?? fan.targetRPM
            draftRPM = min(max(start, fan.minimumRPM), fan.maximumRPM)
            onChange(.constant(rpm: draftRPM))
        case .sensor:
            if case .sensor = mode { return }
            onChange(.sensor(.init(sensorID: TemperatureReader.cpuAverageID,
                                   startCelsius: 58,
                                   maxCelsius: 85)))
        }
    }
}

/// Segmented control needs a `Hashable` tag that is not the mode itself.
enum ModeTag: Hashable {
    case automatic
    case constant
    case sensor

    init(_ mode: FanControlMode) {
        switch mode {
        case .automatic: self = .automatic
        case .constant: self = .constant
        case .sensor: self = .sensor
        }
    }
}

extension FanControlMode {
    var constantRPM: Double? {
        if case .constant(let rpm) = self { return rpm }
        return nil
    }
}

/// A compact editable linear fan curve.
struct SensorCurveEditor: View {
    let fan: FanSnapshot
    let curve: FanControlMode.SensorCurve
    let temperature: Double?
    let accent: Color
    let onChange: (FanControlMode.SensorCurve) -> Void

    private var startRPM: Double { fan.minimumRPM }
    private var maxRPM: Double { fan.maximumRPM }

    private var targetRPM: Double {
        fan.minimumRPM + curve.load(temperature: temperature ?? curve.startCelsius)
            * (fan.maximumRPM - fan.minimumRPM)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("Curve"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let temperature {
                    Text(String(format: "%.0f °C", temperature))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                    Text("→")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(L10n.format("%d rpm", Int(targetRPM.rounded())))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }
            }

            CurveGraph(curve: curve, temperature: temperature, accent: accent,
                       minRPM: startRPM, maxRPM: maxRPM)
                .frame(height: 46)

            HStack(spacing: 12) {
                BoundField(title: L10n.string("Start"),
                           value: curve.startCelsius,
                           range: 30...90,
                           tint: accent) { newValue in
                    var updated = curve
                    updated.startCelsius = min(newValue, curve.maxCelsius - 3)
                    onChange(updated)
                }
                BoundField(title: L10n.string("Max"),
                           value: curve.maxCelsius,
                           range: 45...105,
                           tint: accent) { newValue in
                    var updated = curve
                    updated.maxCelsius = max(newValue, curve.startCelsius + 3)
                    onChange(updated)
                }
            }
        }
    }
}

/// Two labelled numeric steppers sharing one row.
struct BoundField: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let tint: Color
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                TextField("", value: Binding(
                    get: { value },
                    set: { onChange(min(max($0.rounded(), range.lowerBound), range.upperBound)) }
                ), format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12, design: .rounded))
                .monospacedDigit()

                Stepper("", value: Binding(
                    get: { value },
                    set: { onChange(min(max($0.rounded(), range.lowerBound), range.upperBound)) }
                ), in: range, step: 1)
                .labelsHidden()

                Text("°C")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Draws the ramp, the current temperature marker, and the resulting speed.
struct CurveGraph: View {
    let curve: FanControlMode.SensorCurve
    let temperature: Double?
    let accent: Color
    let minRPM: Double
    let maxRPM: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let startX = 0.0
            let endX = size.width
            let y = size.height - 4

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: startX, y: y))
                    path.addLine(to: CGPoint(x: endX, y: 4))
                    path.addLine(to: CGPoint(x: endX, y: y))
                }
                .fill(LinearGradient(colors: [accent.opacity(0.28), accent.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))

                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: startX, y: y))
                    path.addLine(to: CGPoint(x: endX, y: 4))
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let temperature {
                    let fraction = curve.load(temperature: temperature)
                    let x = size.width * fraction
                    let markerY = y - (y - 4) * fraction
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    .stroke(accent.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(.background, lineWidth: 1.5))
                        .position(x: x, y: markerY)
                        .animation(.smooth(duration: 0.35), value: fraction)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("\(Int(curve.startCelsius))°")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .offset(y: 12)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("\(Int(curve.maxCelsius))°")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .offset(y: 12)
            }
        }
        .padding(.bottom, 10)
    }
}
