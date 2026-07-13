#if os(macOS) || os(Linux)
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// An error reported by a POSIX operation used to manage the terminal lifecycle.
public struct TerminalSystemError: Error, CustomStringConvertible, Sendable {
    public let operation: String
    public let code: Int32

    public init(operation: String, code: Int32) {
        self.operation = operation
        self.code = code
    }

    public var description: String {
        let message = String(cString: strerror(code))
        return "\(operation) failed (errno \(code)): \(message)"
    }
}
#endif
