import XCTest
@testable import VokabKit

/// Regression test for the pipe-buffer deadlock: a response larger than the OS
/// pipe buffer (~64KB) must come back intact. The child blocks on `write` once
/// the buffer fills, so reading stdout only *after* `waitUntilExit()` would
/// deadlock — `AgyClient` drains stdout/stderr concurrently with the process.
final class AgyClientStreamingTests: XCTestCase {

    /// Writes a temporary executable that prints a JSON payload of `payloadBytes`
    /// of 'a' to stdout, ignoring its arguments. Returns the script path.
    private func makeFakeAgy(payloadBytes: Int) throws -> String {
        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("fake-agy-\(payloadBytes).sh")
        let script = """
        #!/bin/sh
        printf '{"meaning_en":"'
        head -c \(payloadBytes) /dev/zero | tr '\\0' 'a'
        printf '"}'
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func testLargeStdoutDoesNotDeadlock() async throws {
        let payload = 200_000   // well past the ~64KB pipe buffer
        let path = try makeFakeAgy(payloadBytes: payload)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let settings = VokabSettings(agyPath: path, timeoutSeconds: 30)
        let client = AgyClient(settings: settings)

        let out = try await client.run(prompt: "anything", model: nil)
        XCTAssertGreaterThan(out.count, payload, "full payload should survive")
        XCTAssertTrue(out.hasPrefix(#"{"meaning_en":"aaa"#))
        XCTAssertTrue(out.hasSuffix(#"a"}"#))
    }

    func testOutputBeyondCapAbortsWithBoundedError() async throws {
        // Emit more than the per-stream cap so the drain kills the process and
        // surfaces a bounded-output error instead of growing memory until timeout.
        let payload = AgyClient.outputCap + 1_000_000
        let path = try makeFakeAgy(payloadBytes: payload)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let settings = VokabSettings(agyPath: path, timeoutSeconds: 30)
        let client = AgyClient(settings: settings)

        do {
            _ = try await client.run(prompt: "anything", model: nil)
            XCTFail("expected outputTooLarge")
        } catch let AgyError.outputTooLarge(bytes) {
            XCTAssertGreaterThan(bytes, AgyClient.outputCap)
        }
    }
}
