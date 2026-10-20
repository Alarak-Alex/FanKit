import SwiftUI

/// Temperature → colour ramp shared by every gauge and readout.
enum ThermalPalette {
    static func color(for celsius: Double?) -> Color {
        guard let celsius else { return .secondary }
        switch celsius {
        case ..<45: return Color(red: 0.29, green: 0.62, blue: 0.94)
        case ..<60: return Color(red: 0.30, green: 0.76, blue: 0.72)
        case ..<72: return Color(red: 0.55, green: 0.78, blue: 0.36)
        case ..<82: return Color(red: 0.95, green: 0.70, blue: 0.28)
        case ..<90: return Color(red: 0.95, green: 0.51, blue: 0.24)
        default: return Color(red: 0.91, green: 0.30, blue: 0.30)
        }
    }

    static func gradient(for celsius: Double?) -> LinearGradient {
        let base = color(for: celsius)
        return LinearGradient(colors: [base.opacity(0.75), base],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing)
    }
}

/// Rounded panel used for every card in the window.
struct Card<Content: View>: View {
    var radius: CGFloat = 18
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

/// A circular value indicator with a soft track.
struct RingGauge: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 9
    var size: CGFloat = 64

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.45), value: clamped)
        }
        .frame(width: size, height: size)
    }
}

/// Icon + label + big value, used in the overview strip.
struct StatTile: View {
    let title: String
    let value: String
    let unit: String?
    let symbol: String
    let tint: Color
    var detail: String?

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.primary)
                    if let unit {
                        Text(unit)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Small status pill, e.g. "Manual" or "SMC control".
struct StatusPill: View {
    let text: String
    let tint: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.14)))
        .foregroundStyle(tint)
    }
}

/// A horizontal bar showing one sensor's value relative to a 20–110 °C window.
struct TemperatureBar: View {
    let celsius: Double

    private var fraction: Double {
        min(max((celsius - 20) / 90, 0.02), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(ThermalPalette.gradient(for: celsius))
                    .frame(width: max(proxy.size.width * fraction, 6))
                    .animation(.smooth(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 6)
    }
}

/// Section header with an optional trailing control.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// Friendly empty state for lists with nothing to show yet.
struct EmptyHint: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
