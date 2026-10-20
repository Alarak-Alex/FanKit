import FanKitCore
import SwiftUI

/// What the menu bar item displays.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case temperature
    case fanSpeed
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .temperature: return L10n.string("Temperature")
        case .fanSpeed: return L10n.string("Fan speed")
        case .both: return L10n.string("Both")
        }
    }
}

/// The popover that opens from the menu bar item.
struct MenuBarPanel: View {
    @Environment(FanStore.self) private var store
    @AppStorage("menuBarStyle") private var style: MenuBarStyle = .both
    @AppStorage("menuBarTwoLines") private var twoLines = true

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    temperatureSummary
                    if !store.fans.isEmpty { fanSummary }
                    presetRow
                }
                .padding(16)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 420)

            Divider().opacity(0.4)
            panelFooter
        }
        .frame(width: 330)
        .background(.regularMaterial)
    }

    private var panelHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.machineModel)
                    .font(.system(size: 13, weight: .semibold))
                Text(store.isControlEnabled
                     ? L10n.format("Controlling · %@", store.activePreset.displayName)
                     : L10n.string("macOS thermal control"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { store.isControlEnabled },
                set: { store.isControlEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .disabled(!store.helperState.isUsable || store.fans.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var temperatureSummary: some View {
        HStack(spacing: 10) {
            RingGauge(fraction: temperatureFraction,
                      tint: ThermalPalette.color(for: store.menuBarTemperature),
                      lineWidth: 6,
                      size: 44)
                .overlay {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ThermalPalette.color(for: store.menuBarTemperature))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(store.menuBarTemperature.map { String(format: "%.1f °C", $0) } ?? "—")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(L10n.format("CPU average · %d sensors", store.temperatures.count))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var temperatureFraction: Double {
        guard let value = store.menuBarTemperature else { return 0 }
        return min(max((value - 30) / 70, 0), 1)
    }

    private var fanSummary: some View {
        VStack(spacing: 6) {
            ForEach(store.fans) { fan in
                HStack(spacing: 8) {
                    Image(systemName: "fanblades.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(fan.isForced
                                         ? ThermalPalette.color(for: store.menuBarTemperature)
                                         : .secondary)
                        .frame(width: 16)
                    Text(fan.name)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("\(Int(fan.actualRPM.rounded()))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("rpm")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(store.presets) { preset in
                    Button(preset.displayName) {
                        store.activePreset = preset.resized(to: max(store.fans.count, 1))
                    }
                }
            } label: {
                Label(store.activePreset.displayName, systemImage: "square.stack.3d.up")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                MainWindowController.shared.show()
            } label: {
                Label(L10n.string("Details"), systemImage: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.link)
        }
    }

    private var panelFooter: some View {
        HStack(spacing: 12) {
            Button {
                MainWindowController.shared.show()
            } label: {
                Label(L10n.string("Open FanKit"), systemImage: "macwindow")
                    .font(.system(size: 11))
            }
            .buttonStyle(.link)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(L10n.string("Quit FanKit and release the fans"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// The label drawn in the menu bar itself.
struct MenuBarLabel: View {
    @Environment(FanStore.self) private var store
    @AppStorage("menuBarStyle") private var style: MenuBarStyle = .both
    @AppStorage("menuBarTwoLines") private var twoLines = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))

            if twoLines {
                VStack(alignment: .leading, spacing: -1) {
                    if let primary {
                        Text(primary)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    if let secondary {
                        Text(secondary)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .opacity(0.75)
                    }
                }
            } else if let primary {
                Text(primary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private var symbol: String {
        guard let celsius = store.menuBarTemperature else { return "fanblades" }
        switch celsius {
        case ..<60: return "fanblades"
        case ..<80: return "fanblades.fill"
        default: return "flame.fill"
        }
    }

    private var primary: String? {
        switch style {
        case .temperature:
            return store.menuBarTemperature.map { String(format: "%.0f°", $0) }
        case .fanSpeed:
            return "\(Int(store.totalRPM.rounded()))"
        case .both:
            guard let celsius = store.menuBarTemperature else { return nil }
            return String(format: "%.0f°", celsius)
        }
    }

    private var secondary: String? {
        guard twoLines else { return nil }
        switch style {
        case .temperature:
            return "\(Int(store.totalRPM.rounded()))rpm"
        case .fanSpeed:
            return store.menuBarTemperature.map { String(format: "%.0f°", $0) }
        case .both:
            return "\(Int(store.totalRPM.rounded()))rpm"
        }
    }
}
