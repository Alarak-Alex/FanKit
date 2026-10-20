import FanKitCore
import SwiftUI

/// The main window: at-a-glance state, per-fan control, and the sensor list.
struct DashboardView: View {
    @Environment(FanStore.self) private var store
    @State private var selection: Section = .fans

    enum Section: String, CaseIterable, Identifiable {
        case fans = "Fans"
        case sensors = "Sensors"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fans: return L10n.string("Fans")
            case .sensors: return L10n.string("Sensors")
            }
        }

        var symbol: String {
            switch self {
            case .fans: return "fanblades"
            case .sensors: return "thermometer.medium"
            }
        }
    }

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            ScrollView {
                VStack(spacing: 18) {
                    overview
                    switch selection {
                    case .fans: fanSection
                    case .sensors: sensorSection
                    }
                }
                .padding(22)
            }
            .scrollIndicators(.never)

            Divider().opacity(0.5)
            footer
        }
        .background(WindowBackground())
        .frame(minWidth: 720, minHeight: 620)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.machineModel)
                    .font(.system(size: 19, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $selection) {
                ForEach(Section.allCases) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)

            controlToggle
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var subtitle: String {
        switch store.phase {
        case .starting:
            return L10n.string("Connecting to AppleSMC…")
        case .failed(let message):
            return message
        case .ready:
            let fans = store.fans.count
            let sensors = store.temperatures.count
            let fanText = L10n.format(fans == 1 ? "%d fan" : "%d fans", fans)
            let sensorText = L10n.format("%d sensors", sensors)
            return "\(fanText) · \(sensorText) · "
                + L10n.format("Helper: %@", store.helperState.label.lowercased())
        }
    }

    private var controlToggle: some View {
        @Bindable var store = store
        return Toggle(isOn: $store.isControlEnabled) {
            Text(L10n.string("Fan control"))
                .font(.system(size: 12, weight: .medium))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!store.helperState.isUsable || store.fans.isEmpty)
        .help(store.helperState.isUsable
              ? L10n.string("Take over the fans with the active preset")
              : L10n.string("Install the privileged helper to enable fan control"))
    }

    // MARK: - Overview

    private var overview: some View {
        HStack(spacing: 14) {
            StatTile(title: L10n.string("CPU"),
                     value: store.cpuTemperature.map { String(format: "%.1f", $0) } ?? "—",
                     unit: "°C",
                     symbol: "cpu",
                     tint: ThermalPalette.color(for: store.cpuTemperature),
                     detail: store.cpuTemperature.map(thermalNote))

            StatTile(title: L10n.string("Hottest"),
                     value: store.hottestTemperature.map { String(format: "%.1f", $0) } ?? "—",
                     unit: "°C",
                     symbol: "flame",
                     tint: ThermalPalette.color(for: store.hottestTemperature),
                     detail: store.temperatures.max(by: { $0.celsius < $1.celsius })?.name)

            StatTile(title: L10n.string("Total airflow"),
                     value: "\(Int(store.totalRPM.rounded()))",
                     unit: "rpm",
                     symbol: "wind",
                     tint: Color(red: 0.36, green: 0.56, blue: 0.96),
                     detail: store.fans.isEmpty ? nil
                        : L10n.format(store.fans.count == 1 ? "%d fan" : "%d fans",
                                      store.fans.count))
        }
    }

    private func thermalNote(_ celsius: Double) -> String {
        switch celsius {
        case ..<50: return L10n.string("Cool")
        case ..<65: return L10n.string("Normal")
        case ..<78: return L10n.string("Warm")
        case ..<88: return L10n.string("Hot")
        default: return L10n.string("Very hot")
        }
    }

    // MARK: - Fans

    private var fanSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: L10n.string("Fans"),
                          subtitle: store.isControlEnabled
                            ? L10n.format("Preset: %@", store.activePreset.displayName)
                            : L10n.string("macOS is controlling the fans")) {
                Menu {
                    ForEach(store.presets) { preset in
                        Button(preset.displayName) {
                            store.activePreset = preset.resized(to: max(store.fans.count, 1))
                        }
                    }
                    Divider()
                    Button(L10n.string("Save Current as Preset…")) { savePrompt = true }
                } label: {
                    Label(store.activePreset.displayName, systemImage: "square.stack.3d.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if store.fans.isEmpty {
                Card {
                    EmptyHint(symbol: "fanblades",
                              title: L10n.string("No fans detected"),
                              message: store.phase == .ready
                                ? L10n.string("This Mac reports no controllable fans through AppleSMC.")
                                : L10n.string("Waiting for the SMC connection."))
                }
            } else {
                ForEach(store.fans) { fan in
                    FanRow(fan: fan,
                           mode: store.activePreset.mode(forFan: fan.id),
                           temperature: store.temperature(
                            forSensor: sensorID(for: store.activePreset.mode(forFan: fan.id))
                           ),
                           isLive: store.isControlEnabled) { mode in
                        store.setMode(mode, forFan: fan.id)
                    }
                }
            }
        }
        .sheet(isPresented: $savePrompt) { SavePresetSheet() }
    }

    private func sensorID(for mode: FanControlMode) -> String {
        if case .sensor(let curve) = mode { return curve.sensorID }
        return TemperatureReader.cpuAverageID
    }

    @State private var savePrompt = false

    // MARK: - Sensors

    private var sensorSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: L10n.string("Sensors"),
                          subtitle: L10n.string("Reported by the Apple Silicon thermal telemetry")) {
                Text("\(store.temperatures.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if store.temperatures.isEmpty {
                Card {
                    EmptyHint(symbol: "thermometer.slash",
                              title: L10n.string("No temperature sensors"),
                              message: L10n.string("The HID sensor service did not return any readings."))
                }
            } else {
                Card(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.temperatures
                            .sorted { $0.celsius > $1.celsius }
                            .enumerated()), id: \.element.id) { index, reading in
                            SensorRow(reading: reading)
                            if index < store.temperatures.count - 1 {
                                Divider().opacity(0.35).padding(.leading, 42)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.phase == .ready ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(store.phase == .ready ? L10n.string("Live") : L10n.string("Connecting"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            if let lastUpdate = store.lastUpdate {
                Text("· " + L10n.format("updated %@",
                                       lastUpdate.formatted(date: .omitted, time: .standard)))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if let error = store.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HelperStatusButton()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// One row in the sensor list.
struct SensorRow: View {
    let reading: TemperatureReading

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: reading.group.symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ThermalPalette.color(for: reading.celsius))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(reading.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(reading.group.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(String(format: "%.1f °C", reading.celsius))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ThermalPalette.color(for: reading.celsius))
                }
                TemperatureBar(celsius: reading.celsius)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

/// Shows helper state and offers the install / remove actions.
struct HelperStatusButton: View {
    @Environment(FanStore.self) private var store
    @State private var isBusy = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(L10n.format("Helper: %@", store.helperState.label))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            if store.helperState == .missing {
                Button(L10n.string("Install")) { run { await store.installHelper() } }
                    .controlSize(.mini)
                    .disabled(isBusy)
            } else if store.helperState == .stopped {
                Button(L10n.string("Reconnect")) { run { await store.connectHelper() } }
                    .controlSize(.mini)
                    .disabled(isBusy)
                Button(L10n.string("Reinstall")) { run { await store.installHelper() } }
                    .controlSize(.mini)
                    .disabled(isBusy)
            }
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        isBusy = true
        Task {
            await action()
            isBusy = false
        }
    }

    private var icon: String {
        switch store.helperState {
        case .connected: return "checkmark.shield.fill"
        case .missing: return "shield.slash"
        case .stopped: return "shield.lefthalf.filled"
        case .unknown: return "shield"
        }
    }

    private var tint: Color {
        switch store.helperState {
        case .connected: return .green
        case .missing: return .orange
        case .stopped: return .yellow
        case .unknown: return .secondary
        }
    }
}

/// Soft vertical wash behind the window content.
struct WindowBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor).opacity(0.85),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// Prompts for a name when saving the current preset.
struct SavePresetSheet: View {
    @Environment(FanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("Save preset"))
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.string("Stores the control mode of every fan under a name you can recall from the menu."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(L10n.string("Preset name"), text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(L10n.string("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("Save")) {
                    store.savePreset(named: name.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
    }
}
