import Foundation

/// The XPC surface the privileged helper exposes.
///
/// Every method reports failure by throwing; `NSXPCConnection` forwards the
/// `NSError` to the caller's reply block.
@objc public protocol FanKitHelperProtocol {
    /// Identifies the helper so the app can refuse to talk to an impostor.
    func handshake(withReply reply: @escaping (String) -> Void)

    /// Puts `fanIndex` under manual control, or releases it back to the SMC.
    func setForced(_ forced: Bool, fanIndex: Int, withReply reply: @escaping (Error?) -> Void)

    /// Writes the target speed for a fan that is already forced.
    func setTarget(rpm: Double, fanIndex: Int, withReply reply: @escaping (Error?) -> Void)

    /// One round trip: force the fan and set its speed.
    func apply(rpm: Double, fanIndex: Int, withReply reply: @escaping (Error?) -> Void)

    /// Hands every fan back to the SMC. Called on quit and before uninstalling.
    func restoreAll(withReply reply: @escaping (Error?) -> Void)

    /// Proves the app is still alive. The helper hands the fans back to the SMC
    /// when heartbeats stop, so a crashed app cannot pin a fan at one speed.
    func heartbeat(withReply reply: @escaping (Bool) -> Void)
}

public enum FanKitHelperConstants {
    public static let machServiceName = "com.fankit.helper"
    public static let executableName = "FanKitHelper"
    public static let installedPath = "/Library/PrivilegedHelperTools/com.fankit.helper"
    public static let launchDaemonPath = "/Library/LaunchDaemons/com.fankit.helper.plist"
    public static let label = "com.fankit.helper"
    public static let protocolVersion = "FanKitHelper/1"
    /// Seconds without a heartbeat before the helper releases the fans.
    public static let watchdogTimeout: TimeInterval = 20
}
