import Foundation

public enum HelperError: Error, CustomStringConvertible {
    case notInstalled
    case notReachable(String)
    case rejected(String)
    case installFailed(String)

    public var description: String {
        switch self {
        case .notInstalled:
            return "The FanKit helper is not installed"
        case .notReachable(let reason):
            return "Cannot reach the FanKit helper: \(reason)"
        case .rejected(let message):
            return "The FanKit helper rejected the request: \(message)"
        case .installFailed(let message):
            return "Installing the helper failed: \(message)"
        }
    }
}

/// A thin async wrapper around the helper's XPC connection.
public final class HelperClient {
    private let queue = DispatchQueue(label: "com.fankit.helper.client")
    private var connection: NSXPCConnection?

    public init() {}

    private func proxy() throws -> FanKitHelperProtocol {
        if let connection, let proxy = connection.remoteObjectProxy as? FanKitHelperProtocol {
            return proxy
        }
        let newConnection = NSXPCConnection(
            machServiceName: FanKitHelperConstants.machServiceName,
            options: .privileged
        )
        newConnection.remoteObjectInterface = NSXPCInterface(with: FanKitHelperProtocol.self)
        newConnection.invalidationHandler = { [weak self] in
            self?.queue.async { self?.connection = nil }
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.queue.async { self?.connection = nil }
        }
        newConnection.resume()
        connection = newConnection
        guard let proxy = newConnection.remoteObjectProxy as? FanKitHelperProtocol else {
            throw HelperError.notReachable("proxy unavailable")
        }
        return proxy
    }

    public func handshake() async throws -> String {
        let proxy = try proxy()
        return try await withCheckedThrowingContinuation { continuation in
            proxy.handshake { version in
                continuation.resume(returning: version)
            }
        }
    }

    public func apply(rpm: Double, fanIndex: Int) async throws {
        let proxy = try proxy()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.apply(rpm: rpm, fanIndex: fanIndex) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func setForced(_ forced: Bool, fanIndex: Int) async throws {
        let proxy = try proxy()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.setForced(forced, fanIndex: fanIndex) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func restoreAll() async throws {
        let proxy = try proxy()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.restoreAll { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func heartbeat() async -> Bool {
        guard let proxy = try? proxy() else { return false }
        return await withCheckedContinuation { continuation in
            proxy.heartbeat { alive in
                continuation.resume(returning: alive)
            }
        }
    }
}
