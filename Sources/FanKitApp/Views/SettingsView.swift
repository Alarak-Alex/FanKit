import FanKitCore
import SwiftUI

/// Preferences: menu bar presentation, refresh, and helper management.
struct SettingsView: View {
    @Environment(FanStore.self) private var store
    @AppStorage("menuBarStyle") private var style: MenuBarStyle = .both
    @AppStorage("menuBarTwoLines") private var twoLines = true
    @AppStorage("showAllSensors") private var showAllSensors = false
    @AppStorage(AppLanguage.defaultsKey) private var language: AppLanguage = .system

    var body: some View {
        TabView {
            Form {
                Section(L10n.string("Language")) {
                    Picker(L10n.string("Language"), selection: $language) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .onChange(of: language) { _, newValue in
                        AppLanguage.select(newValue)
                        store.reloadLocalizedText()
                    }
                }
                Section(L10n.string("Menu bar")) {
                    Picker(L10n.string("Show"), selection: $style) {
                        ForEach(MenuBarStyle.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Toggle(L10n.string("Two lines (value and fan speed)"), isOn: $twoLines)
                }
                Section(L10n.string("Sensors")) {
                    Toggle(L10n.string("List every temperature sensor"), isOn: $showAllSensors)
                }
                StartupSettings()
            }
            .formStyle(.grouped)
            .tabItem { Label(L10n.string("General"), systemImage: "gear") }

            HelperSettings()
                .tabItem { Label(L10n.string("Helper"), systemImage: "shield.lefthalf.filled") }

            AboutPane()
                .tabItem { Label(L10n.string("About"), systemImage: "info.circle") }
        }
        .frame(width: 460, height: 470)
    }
}

/// Start at login, and open straight to the menu bar when it does.
struct StartupSettings: View {
    @AppStorage("startMinimized") private var startMinimized = true
    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var errorMessage: String?

    var body: some View {
        Section(L10n.string("Startup")) {
            Toggle(L10n.string("Start FanKit at login"), isOn: $launchesAtLogin)
                .onChange(of: launchesAtLogin) { _, newValue in
                    do {
                        try LoginItem.setEnabled(newValue)
                        errorMessage = nil
                    } catch {
                        errorMessage = "\(error)"
                        launchesAtLogin = LoginItem.isEnabled
                    }
                }

            Toggle(L10n.string("Start minimized to the menu bar"), isOn: $startMinimized)
                .disabled(!launchesAtLogin)
                .help(L10n.string("When FanKit starts at login, open only the menu bar item."))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Install, inspect, and remove the privileged helper.
struct HelperSettings: View {
    @Environment(FanStore.self) private var store
    @State private var isWorking = false

    var body: some View {
        Form {
            Section(L10n.string("Status")) {
                LabeledContent(L10n.string("Helper")) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tint)
                            .frame(width: 7, height: 7)
                        Text(store.helperState.label)
                    }
                }
                LabeledContent(L10n.string("Install path")) {
                    Text(FanKitHelperConstants.installedPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                Text(L10n.string("FanKit writes fan speeds through a small background service. "
                                 + "It runs as root because the SMC only accepts writes from an "
                                 + "administrator process. Installing asks for your password once."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                HStack {
                    Button(L10n.string(store.helperState == .missing
                                       ? "Install Helper…" : "Reinstall Helper…")) {
                        isWorking = true
                        Task {
                            await store.installHelper()
                            isWorking = false
                        }
                    }
                    .disabled(isWorking)

                    Button(L10n.string("Remove Helper"), role: .destructive) {
                        isWorking = true
                        Task {
                            await store.removeHelper()
                            isWorking = false
                        }
                    }
                    .disabled(isWorking || store.helperState == .missing)

                    if isWorking {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
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

/// Version, provenance, and credits.
struct AboutPane: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "fanblades.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
            Text("FanKit")
                .font(.system(size: 17, weight: .semibold))
            Text(L10n.string("A native fan controller for Apple Silicon."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(L10n.string("Built with SwiftUI on Apple's public system interfaces."))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Text(version)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return L10n.format("Version %@ (%@)", short, build)
    }
}
