import Foundation

/// Abstraction over "run a prompt through the agy CLI and return its stdout".
///
/// Production uses `AgyClient` (a real `Process`). Tests use a mock so the
/// engine logic can be verified offline, deterministically, without agy.
public protocol AgyRunner: Sendable {
    /// Runs `prompt` through agy and returns raw stdout.
    /// - Parameter model: optional model name (e.g. "Claude Sonnet 4.6 (Thinking)").
    func run(prompt: String, model: String?) async throws -> String
}

/// Errors surfaced by the agy layer.
public enum AgyError: Error, Equatable, Sendable {
    /// agy did not respond within the configured timeout.
    case timeout
    /// agy exited with a non-zero status.
    case nonZeroExit(code: Int32, stderr: String)
    /// agy output could not be decoded into the expected JSON shape.
    case decodeFailure(raw: String)
    /// The agy binary could not be found at the configured path.
    case binaryNotFound(path: String)
    /// agy produced more output than the capture cap; the process was killed.
    case outputTooLarge(bytes: Int)
}
