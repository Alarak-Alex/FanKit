import Foundation

/// Registers FanKit to start when the user logs in.
///
/// A per-user `LaunchAgent` is used instead of `SMAppService`: the app is
/// ad-hoc signed, and the login item service leaves such apps in a
/// "requires approval" state until the user allows them in System Settings.
/// A LaunchAgent belonging to the user needs no approval and is easy to remove.
enum LoginItem {
    static let launchedAtLoginArgument = "--launched-at-login"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.fankit.app.plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// True when this process was started by the login item rather than by the user.
    static var wasLaunchedAtLogin: Bool {
        CommandLine.arguments.contains(launchedAtLoginArgument)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try writeAgent()
        } else {
            try? FileManager.default.removeItem(at: agentURL)
        }
    }

    private static func writeAgent() throws {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else {
            throw LoginItemError.notAnAppBundle
        }
        let executable = app.appendingPathComponent("Contents/MacOS/FanKit").path
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw LoginItemError.missingExecutable(executable)
        }

        let plist: [String: Any] = [
            "Label": "com.fankit.app.login",
            "ProgramArguments": [executable, launchedAtLoginArgument],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                      format: .xml,
                                                      options: 0)
        let directory = agentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try data.write(to: agentURL, options: .atomic)
    }
}

enum LoginItemError: LocalizedError {
    case notAnAppBundle
    case missingExecutable(String)

    var errorDescription: String? {
        switch self {
        case .notAnAppBundle:
            return "FanKit has to run from an app bundle to start at login."
        case .missingExecutable(let path):
            return "The FanKit executable was not found at \(path)."
        }
    }
}
