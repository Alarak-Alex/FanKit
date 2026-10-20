import Foundation

/// Installs and removes the privileged helper.
///
/// `SMAppService` is the modern path but it requires a Developer ID signature to
/// pin the daemon to the app. FanKit is distributed unsigned, so installation
/// asks for administrator rights once and writes the daemon itself, the same way
/// many small utilities do. That prompt is the only privileged action the app
/// ever performs.
public enum HelperInstaller {
    /// Version string recorded by the installed helper, or nil when absent.
    public static var installedVersion: String? {
        guard FileManager.default.isExecutableFile(atPath: FanKitHelperConstants.installedPath)
        else { return nil }
        return FanKitHelperConstants.protocolVersion
    }

    public static var isInstalled: Bool { installedVersion != nil }

    /// True when the copy in `/Library/PrivilegedHelperTools` is missing or is
    /// not the build shipped inside this app, so it should be (re)installed.
    public static var needsInstall: Bool {
        guard let bundled = bundledHelperURL(),
              let bundledData = try? Data(contentsOf: bundled)
        else { return false }
        guard let installedData = try? Data(contentsOf:
                URL(fileURLWithPath: FanKitHelperConstants.installedPath))
        else { return true }
        return installedData != bundledData
    }

    public static var isLoaded: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(FanKitHelperConstants.label)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// The helper binary shipped inside the app bundle.
    public static func bundledHelperURL() -> URL? {
        let bundle = Bundle.main.bundleURL
        let candidates = [
            bundle.appendingPathComponent("Contents/Library/Helper/\(FanKitHelperConstants.executableName)"),
            bundle.appendingPathComponent("Contents/MacOS/\(FanKitHelperConstants.executableName)"),
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return found
        }
        // Running straight from `swift build` during development.
        let debug = bundle.appendingPathComponent(FanKitHelperConstants.executableName)
        if FileManager.default.isExecutableFile(atPath: debug.path) { return debug }
        return nil
    }

    /// True when installing on launch has not been declined.
    public static func rememberedPromptAnswer() -> Bool {
        UserDefaults.standard.object(forKey: "helperInstallDeclined") as? Bool != true
    }

    public static func rememberDeclined(_ declined: Bool) {
        UserDefaults.standard.set(declined, forKey: "helperInstallDeclined")
    }

    public static func install() throws {
        guard let source = bundledHelperURL() else { throw HelperError.notInstalled }
        let script = """
        #!/bin/bash
        set -euo pipefail
        HELPER="\(FanKitHelperConstants.installedPath)"
        PLIST="\(FanKitHelperConstants.launchDaemonPath)"
        LABEL="\(FanKitHelperConstants.label)"
        mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons
        install -m 755 -o root -g wheel "\(source.path)" "$HELPER"
        mkdir -p /var/log
        cat > "$PLIST" <<'PLIST_END'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.fankit.helper</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Library/PrivilegedHelperTools/com.fankit.helper</string>
            </array>
            <key>MachServices</key>
            <dict>
                <key>com.fankit.helper</key>
                <true/>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>/var/log/com.fankit.helper.log</string>
        </dict>
        </plist>
        PLIST_END
        chown root:wheel "$PLIST"
        chmod 644 "$PLIST"
        launchctl bootout system/"$LABEL" 2>/dev/null || true
        launchctl bootstrap system "$PLIST"
        launchctl enable system/"$LABEL"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fankit-install-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let appleScript = #"do shell script "/bin/bash \#(scriptURL.path)" with administrator privileges"#
        try runOSAScript(appleScript)
    }

    public static func uninstall() throws {
        let script = """
        #!/bin/bash
        LABEL="\(FanKitHelperConstants.label)"
        launchctl bootout system/"$LABEL" 2>/dev/null || true
        rm -f "\(FanKitHelperConstants.launchDaemonPath)" "\(FanKitHelperConstants.installedPath)"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fankit-uninstall-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let appleScript = #"do shell script "/bin/bash \#(scriptURL.path)" with administrator privileges"#
        try runOSAScript(appleScript)
    }

    private static func runOSAScript(_ source: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw HelperError.installFailed(message.isEmpty ? "osascript exited \(process.terminationStatus)" : message)
        }
    }
}
