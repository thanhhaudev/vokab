import Foundation

/// Real `AgyRunner` backed by the `agy` CLI invoked via `Process`.
///
/// Invocation matches the verified CLI surface:
///   `agy -p "<prompt>" [--model "<name>"] --print-timeout <n>s`
///
/// stdout/stderr are drained concurrently with the running process (see
/// `validateOrRun`) so output larger than the OS pipe buffer can't deadlock the
/// child against a blocked reader.
public struct AgyClient: AgyRunner {
    private let settings: VokabSettings

    public init(settings: VokabSettings) {
        self.settings = settings
    }

    public func run(prompt: String, model: String?) async throws -> String {
        let path = settings.agyPath
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw AgyError.binaryNotFound(path: path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        var args = ["-p", prompt]
        if let model { args.append(contentsOf: ["--model", model]) }
        args.append(contentsOf: ["--print-timeout", "\(settings.timeoutSeconds)s"])
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Hard wall-clock guard a few seconds beyond agy's own print-timeout.
        let hardTimeout = TimeInterval(settings.timeoutSeconds + 5)

        // Terminate the child if the awaiting task is cancelled, so a cancelled
        // capture doesn't leave an agy process running until its own timeout.
        return try await withTaskCancellationHandler {
            try await validateOrRun(process, outPipe: outPipe, errPipe: errPipe,
                                    hardTimeout: hardTimeout, path: path)
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Interprets agy stdout that has a zero exit code. agy reports failures
    /// (notably `--print-timeout` overruns) as `Error: ...` on stdout with exit
    /// code 0, so plain JSON decoding would mistake them for malformed output.
    static func validate(stdout: String) throws -> String {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("error: timed out") || lower.contains("timed out waiting for response") {
            throw AgyError.timeout
        }
        // A bare "Error: ..." with no JSON payload is an agy-level failure.
        if trimmed.hasPrefix("Error:") && !trimmed.contains("{") && !trimmed.contains("[") {
            throw AgyError.nonZeroExit(code: 0, stderr: trimmed)
        }
        return stdout
    }

    /// Per-stream capture cap. A vocabulary card is well under 100 KB even when
    /// verbose; 8 MB is generous headroom yet small enough never to pressure
    /// memory if agy misbehaves.
    static let outputCap = 8 * 1024 * 1024

    /// Reads `handle` to EOF, appending into an in-memory buffer. If the buffer
    /// exceeds `cap`, records the overflow, terminates `process` (so the sibling
    /// stream unblocks at EOF), and stops. Returns what was read.
    static func drain(_ handle: FileHandle, cap: Int, process: Process, overflow: OverflowFlag) -> Data {
        var acc = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }   // write end closed → EOF
            acc.append(chunk)
            if acc.count > cap {
                overflow.set(bytes: acc.count)
                if process.isRunning { process.terminate() }
                break
            }
        }
        return acc
    }

    private func validateOrRun(_ process: Process, outPipe: Pipe, errPipe: Pipe,
                               hardTimeout: TimeInterval, path: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let guardState = ResumeGuard(continuation)

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    guardState.resume(throwing: AgyError.binaryNotFound(path: path))
                    return
                }

                // Watchdog: terminate and report timeout if agy overruns.
                DispatchQueue.global().asyncAfter(deadline: .now() + hardTimeout) {
                    if process.isRunning {
                        process.terminate()
                        guardState.resume(throwing: AgyError.timeout)
                    }
                }

                // Drain stdout/stderr CONCURRENTLY with the process so a large
                // response (bigger than the OS pipe buffer) can't deadlock: the
                // child would block on write while we block in waitUntilExit.
                // Each stream is capped so a misbehaving agy that streams without
                // end grows memory bounded, not until the timeout: on overflow we
                // kill the process and report `.outputTooLarge`.
                let overflow = OverflowFlag()
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData = Self.drain(outPipe.fileHandleForReading,
                                         cap: Self.outputCap, process: process, overflow: overflow)
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errData = Self.drain(errPipe.fileHandleForReading,
                                         cap: Self.outputCap, process: process, overflow: overflow)
                    group.leave()
                }
                process.waitUntilExit()
                group.wait()   // both reads finish at EOF (write ends closed on exit)

                if let bytes = overflow.bytes {
                    guardState.resume(throwing: AgyError.outputTooLarge(bytes: bytes))
                    return
                }

                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    guardState.resume(throwing: AgyError.nonZeroExit(
                        code: process.terminationStatus, stderr: stderr))
                } else {
                    do {
                        guardState.resume(returning: try Self.validate(stdout: stdout))
                    } catch {
                        guardState.resume(throwing: error)
                    }
                }
            }
        }
    }
}

/// Thread-safe one-shot flag recording that a stream blew past its capture cap.
final class OverflowFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _bytes: Int?

    func set(bytes: Int) {
        lock.lock(); if _bytes == nil { _bytes = bytes }; lock.unlock()
    }

    var bytes: Int? {
        lock.lock(); defer { lock.unlock() }; return _bytes
    }
}

/// Ensures a `CheckedContinuation` is resumed exactly once across the process
/// completion path and the timeout watchdog.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: String) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(throwing: error)
    }
}
