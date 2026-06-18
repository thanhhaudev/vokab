import Foundation

/// Spawn một language_server `--standalone` headless ta tự quản (csrf tự sinh),
/// chờ nó listen, trả (pid, port, csrf). Caller phải gọi `terminate(pid:)` khi xong.
public struct LanguageServerLauncher: Sendable {
    public static let defaultBinaryPath = "/Applications/Antigravity.app/Contents/Resources/bin/language_server"

    public let binaryPath: String
    public let detector: AntigravityProcessDetector
    public init(binaryPath: String = LanguageServerLauncher.defaultBinaryPath,
                detector: AntigravityProcessDetector = AntigravityProcessDetector()) {
        self.binaryPath = binaryPath; self.detector = detector
    }

    public struct Spawned: Sendable { public let pid: Int32; public let port: Int; public let csrf: String }

    public static func spawnArgs(csrf: String) -> [String] {
        ["--standalone", "--override_ide_name", "antigravity", "--subclient_type", "hub",
         "--https_server_port", "0", "--csrf_token", csrf, "--app_data_dir", "antigravity",
         "--api_server_url", "https://generativelanguage.googleapis.com",
         "--cloud_code_endpoint", "https://daily-cloudcode-pa.googleapis.com", "--enable_sidecars"]
    }

    public enum LaunchError: Error, Sendable { case binaryMissing, noPort }

    /// Spawn + poll lsof trên PID con tới khi có port LISTEN (tối đa `timeout` giây).
    public func spawn(csrf: String, timeout: TimeInterval = 15) async throws -> Spawned {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else { throw LaunchError.binaryMissing }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = Self.spawnArgs(csrf: csrf)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        let pid = p.processIdentifier
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let lsof = (try? detector.runShell("/usr/sbin/lsof", ["-Pan", "-p", "\(pid)", "-i"])) ?? ""
            if let port = AntigravityProcessDetector.parsePorts(lsof).first {
                return Spawned(pid: pid, port: port, csrf: csrf)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        if p.isRunning { p.terminate() }
        throw LaunchError.noPort
    }

    public func terminate(pid: Int32) {
        kill(pid, SIGTERM)
    }
}
