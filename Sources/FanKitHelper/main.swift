import FanKitCore
import AppKit
import Foundation

/// The privileged half of FanKit.
///
/// It is installed as a LaunchDaemon and owns the only writable `AppleSMC`
/// connection. The surface is deliberately narrow: force a fan, set its speed,
/// release everything. A watchdog hands the fans back to the SMC if the app
/// stops checking in, so a crash cannot leave a fan pinned.
private final class HelperService: NSObject, FanKitHelperProtocol {
    private let lock = NSLock()
    private var connection: SMCConnection?
    private var writer: FanWriter?
    private var lastHeartbeat = Date()

    private func hardware() throws -> (SMCConnection, FanWriter) {
        lock.lock()
        defer { lock.unlock() }
        if let connection, let writer {
            return (connection, writer)
        }
        let created = try SMCConnection()
        let writer = FanWriter(connection: created)
        connection = created
        self.writer = writer
        return (created, writer)
    }

    func handshake(withReply reply: @escaping (String) -> Void) {
        lastHeartbeat = Date()
        reply(FanKitHelperConstants.protocolVersion)
    }

    func setForced(_ forced: Bool, fanIndex: Int, withReply reply: @escaping (Error?) -> Void) {
        lastHeartbeat = Date()
        do {
            let (_, writer) = try hardware()
            try writer.setForced(forced, fanIndex: fanIndex)
            reply(nil)
        } catch {
            reply(error)
        }
    }

    func setTarget(rpm: Double, fanIndex: Int, withReply reply: @escaping (Error?) -> Void) {
        lastHeartbeat = Date()
        do {
            let (_, writer) = try hardware()
            try writer.setTarget(rpm: rpm, fanIndex: fanIndex)
            reply(nil)
        } catch {
            reply(error)
        }
    }

    func apply(rpm: Double, fanIndex: Int, withReply reply: @escaping (Error?) -> Void) {
        lastHeartbeat = Date()
        do {
            let (_, writer) = try hardware()
            try writer.setForced(true, fanIndex: fanIndex)
            try writer.setTarget(rpm: rpm, fanIndex: fanIndex)
            reply(nil)
        } catch {
            reply(error)
        }
    }

    func restoreAll(withReply reply: @escaping (Error?) -> Void) {
        do {
            let (connection, writer) = try hardware()
            let count = try FanReader(connection: connection).fanCount()
            var firstError: Error?
            for index in 0..<count {
                do {
                    try writer.setForced(false, fanIndex: index)
                } catch {
                    firstError = firstError ?? error
                }
            }
            reply(firstError)
        } catch {
            reply(error)
        }
    }

    func heartbeat(withReply reply: @escaping (Bool) -> Void) {
        lastHeartbeat = Date()
        reply(true)
    }

    /// Releases the fans once the app has been quiet for too long.
    func startWatchdog() {
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard Date().timeIntervalSince(self.lastHeartbeat) > FanKitHelperConstants.watchdogTimeout
            else { return }
            self.lastHeartbeat = Date()
            self.restoreReleased()
        }
        RunLoop.current.add(timer, forMode: .common)
    }

    private func restoreReleased() {
        guard let (connection, writer) = try? hardware() else { return }
        guard let count = try? FanReader(connection: connection).fanCount() else { return }
        var anyForced = false
        for index in 0..<count {
            let mode = (try? connection.read(.fanMode(index)).first).flatMap { $0 }
            if mode == 1 {
                anyForced = true
                try? writer.setForced(false, fanIndex: index)
            }
        }
        if anyForced {
            FileHandle.standardError.write(Data("watchdog released fans\n".utf8))
        }
    }
}

private final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    let service = HelperService()

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard Self.isTrusted(connection) else {
            FileHandle.standardError.write(Data("rejected untrusted peer\n".utf8))
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: FanKitHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }

    /// The helper runs as root and must not serve arbitrary clients.
    ///
    /// Without a Developer ID certificate there is no anchor to pin, so the
    /// check is that the caller's executable lives inside a `FanKit.app` bundle.
    private static func isTrusted(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        guard pid > 0 else { return false }
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return false }
        let path = String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
        return path.contains("/\(FanKitConstants.appName).app/Contents/MacOS/")
    }
}

private let delegate = HelperDelegate()
private let listener = NSXPCListener(machServiceName: FanKitHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
delegate.service.startWatchdog()
RunLoop.current.run()
