import FanKitCore
import Foundation
import Observation
import SwiftUI

/// Everything the UI reads from and asks of the hardware.
@MainActor
@Observable
final class FanStore {
    static let shared = FanStore()

    enum Phase: Equatable {
        case starting
        case ready
        case failed(String)
    }

    enum HelperState: Equatable {
        case unknown
        case missing
        case stopped
        case connected

        var label: String {
            switch self {
            case .unknown: return L10n.string("Checking…")
            case .missing: return L10n.string("Not installed")
            case .stopped: return L10n.string("Installed, not responding")
            case .connected: return L10n.string("Connected")
            }
        }

        var isUsable: Bool { self == .connected }
    }

    // MARK: - Published state

    private(set) var phase: Phase = .starting
    private(set) var fans: [FanSnapshot] = []
    private(set) var temperatures: [TemperatureReading] = []
    private(set) var machineModel: String = "Mac"
    private(set) var lastUpdate: Date?
    private(set) var helperState: HelperState = .unknown
    private(set) var lastError: String?

    /// Bumped when the language changes so every view rebuilds its labels.
    private(set) var languageVersion = 0

    func reloadLocalizedText() {
        languageVersion += 1
        presets = presets.map { $0 }
    }

    /// True while the user has fan control switched on. Control is on by
    /// default; the flag is persisted so switching it off survives a relaunch.
    var isControlEnabled = UserDefaults.standard.object(forKey: FanStore.controlKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isControlEnabled, forKey: FanStore.controlKey)
            controlChanged()
        }
    }

    private static let controlKey = "fanControlEnabled"

    var activePreset: FanPreset = .automatic(fanCount: 1) {
        didSet { scheduleApply() }
    }

    private(set) var presets: [FanPreset] = []

    // MARK: - Private state

    private var connection: SMCConnection?
    private var reader: FanReader?
    private var engine = ControlEngine()
    private let helper = HelperClient()
    private let presetStore = PresetStore()
    private var pollTask: Task<Void, Never>?
    private var tickCount = 0
    private var forcedFans: Set<Int> = []
    private var isPushing = false
    private var applyTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        loadPresets()
        do {
            let connection = try SMCConnection()
            self.connection = connection
            self.reader = FanReader(connection: connection)
            self.machineModel = Self.machineModelName()
            phase = .ready
            refresh(temperaturesToo: true)
            activePreset = activePreset.resized(to: max(fans.count, 1))
        } catch {
            phase = .failed("\(error)")
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(FanKitConstants.refreshInterval))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
        helperState = HelperInstaller.isInstalled ? .stopped : .missing
        Task { await connectHelper() }
        Task { await installHelperIfNeeded() }
    }

    /// Installs or refreshes the helper on first launch.
    ///
    /// The app ships the helper inside its own bundle (`Contents/Library/Helper`)
    /// and installs it into `/Library/PrivilegedHelperTools` once, which is what
    /// macOS requires for a launchd job. A missing or stale copy is replaced
    /// automatically; only a first-time install asks for administrator rights.
    func installHelperIfNeeded() async {
        guard HelperInstaller.needsInstall else { return }
        guard HelperInstaller.rememberedPromptAnswer() else { return }
        await installHelper()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func tick() {
        tickCount += 1
        refresh(temperaturesToo: tickCount % 2 == 0)
        applyControls()
        if tickCount % 5 == 0 { sendHeartbeat() }
    }

    /// The helper hands the fans back to the SMC when it stops hearing from the
    /// app, so the app has to check in well inside its watchdog window.
    private func sendHeartbeat() {
        guard helperState.isUsable else { return }
        Task { [weak self] in
            guard let self else { return }
            let alive = await helper.heartbeat()
            if !alive, helperState == .connected { helperState = .stopped }
        }
    }

    private func refresh(temperaturesToo: Bool) {
        guard let reader else { return }
        if let snapshots = try? reader.snapshots() {
            fans = snapshots
            lastUpdate = Date()
        }
        if temperaturesToo {
            let readings = TemperatureReader.readHID()
            if !readings.isEmpty { temperatures = readings }
        }
    }

    // MARK: - Helper

    func connectHelper() async {
        guard HelperInstaller.isInstalled else {
            helperState = .missing
            return
        }
        do {
            let version = try await helper.handshake()
            helperState = version.isEmpty ? .stopped : .connected
            await releaseStaleForcedFans()
        } catch {
            helperState = .stopped
        }
    }

    func installHelper() async {
        do {
            try await Task.detached { try HelperInstaller.install() }.value
            HelperInstaller.rememberDeclined(false)
            try? await Task.sleep(for: .seconds(1))
            await connectHelper()
        } catch {
            // A cancelled password prompt means the user said no; do not ask
            // again on every launch.
            if HelperInstaller.isInstalled {
                lastError = "\(error)"
            } else {
                HelperInstaller.rememberDeclined(true)
            }
            helperState = HelperInstaller.isInstalled ? .stopped : .missing
        }
    }

    func removeHelper() async {
        isControlEnabled = false
        do {
            try await Task.detached { try HelperInstaller.uninstall() }.value
            HelperInstaller.rememberDeclined(true)
            helperState = .missing
        } catch {
            lastError = "\(error)"
        }
    }

    // MARK: - Control

    private func controlChanged() {
        applyEngineIfNeeded(sendAutomatic: !isControlEnabled)
        if isControlEnabled { scheduleApply() }
    }

    private var isAutomaticOnly: Bool { activePreset.isFullyAutomatic }

    private func applyControls() {
        guard isControlEnabled, helperState.isUsable else { return }
        applyEngineIfNeeded(sendAutomatic: isAutomaticOnly)
    }

    /// A fan left forced by a previous run would otherwise stay pinned: the app
    /// starts sending heartbeats again before the watchdog can release it.
    private func releaseStaleForcedFans() async {
        guard helperState.isUsable, let reader else { return }
        guard let snapshots = try? reader.snapshots() else { return }
        for fan in snapshots where fan.isForced {
            try? await helper.setForced(false, fanIndex: fan.id)
        }
    }

    /// Debounces preset edits so dragging a slider does not flood the helper.
    private func scheduleApply() {
        guard isControlEnabled else { return }
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            self.applyEngineIfNeeded(sendAutomatic: false)
        }
    }

    private func applyEngineIfNeeded(sendAutomatic: Bool) {
        guard helperState.isUsable, let reader else {
            if !helperState.isUsable { forcedFans.removeAll() }
            return
        }
        guard let snapshots = try? reader.snapshots(), !snapshots.isEmpty else { return }

        let preset = sendAutomatic ? .automatic(fanCount: snapshots.count) : activePreset
        let commands = engine.evaluate(preset: preset, fans: snapshots, temperatures: temperatures)

        var pending: [FanCommand] = []
        for command in commands {
            if command.forced {
                pending.append(command)
            } else if forcedFans.contains(command.fanIndex) {
                // Only release fans this session actually forced; sending an
                // automatic command every tick would be a write per second.
                pending.append(command)
            }
        }
        guard !pending.isEmpty, !isPushing else { return }
        isPushing = true
        Task { [weak self] in
            await self?.push(pending)
            self?.isPushing = false
        }
    }

    private func push(_ commands: [FanCommand]) async {
        for command in commands {
            do {
                if command.forced {
                    try await helper.apply(rpm: command.rpm, fanIndex: command.fanIndex)
                    forcedFans.insert(command.fanIndex)
                } else {
                    try await helper.setForced(false, fanIndex: command.fanIndex)
                    forcedFans.remove(command.fanIndex)
                }
            } catch {
                lastError = "\(error)"
                if case HelperError.notReachable = error { helperState = .stopped }
                return
            }
        }
    }

    /// Hands every fan back to the SMC. Called on quit and when control is switched off.
    func releaseAll() async {
        guard helperState.isUsable else { return }
        try? await helper.restoreAll()
        forcedFans.removeAll()
        engine.reset()
    }

    // MARK: - Presets

    func loadPresets() {
        let stored = presetStore.load()
        if stored.isEmpty {
            presets = [
                FanPreset(name: "Balanced", modes: [.sensor(.init(sensorID: TemperatureReader.cpuAverageID,
                                                                 startCelsius: 58,
                                                                 maxCelsius: 85))]),
                FanPreset(name: "Quiet", modes: [.sensor(.init(sensorID: TemperatureReader.cpuAverageID,
                                                              startCelsius: 70,
                                                              maxCelsius: 95))]),
            ].map { $0.resized(to: max(fans.count, 1)) }
        } else {
            presets = stored
        }
    }

    func savePreset(named name: String) {
        var preset = activePreset
        preset.name = name
        if let index = presets.firstIndex(where: { $0.name == name }) {
            preset.id = presets[index].id
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        activePreset = preset
        persistPresets()
    }

    func deletePreset(_ preset: FanPreset) {
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    private func persistPresets() {
        try? presetStore.save(presets)
    }

    func setMode(_ mode: FanControlMode, forFan index: Int) {
        guard activePreset.modes.indices.contains(index) else { return }
        activePreset.modes[index] = mode
        // Picking a manual mode is an explicit request to drive the fan, so the
        // master switch must not silently swallow it.
        if !mode.isAutomatic, !isControlEnabled, helperState.isUsable {
            isControlEnabled = true
        }
    }

    // MARK: - Derived values

    var cpuTemperature: Double? {
        TemperatureReader.cpuAverage(from: temperatures)
    }

    var hottestTemperature: Double? {
        temperatures.map(\.celsius).max()
    }

    var totalRPM: Double {
        fans.reduce(0) { $0 + $1.actualRPM }
    }

    var hasForcedFans: Bool {
        fans.contains { $0.isForced }
    }

    var menuBarTemperature: Double? { cpuTemperature ?? hottestTemperature }

    /// Sensors the preset editor offers, grouped for readability.
    var selectableSensors: [(id: String, label: String)] {
        var entries: [(String, String)] = [
            (TemperatureReader.cpuAverageID, L10n.string("CPU average")),
            ("hottest", L10n.string("Hottest sensor")),
        ]
        let groups = Dictionary(grouping: temperatures, by: \.group)
        for group in groups.keys.sorted(by: { $0.rank < $1.rank }) {
            for reading in (groups[group] ?? []).sorted(by: { $0.name < $1.name }) {
                entries.append((reading.id, "\(group.displayName) · \(reading.name)"))
            }
        }
        return entries.map { (id: $0.0, label: $0.1) }    }

    func temperature(forSensor id: String) -> Double? {
        TemperatureReader.value(forSensor: id, readings: temperatures)
    }

    static func machineModelName() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
