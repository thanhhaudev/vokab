import Foundation

public struct AntigravityProcessInfo: Equatable, Sendable {
    public let pid: Int32
    public let csrfToken: String
    public let listeningPorts: [Int]
    public init(pid: Int32, csrfToken: String, listeningPorts: [Int]) {
        self.pid = pid; self.csrfToken = csrfToken; self.listeningPorts = listeningPorts
    }
}

/// Tìm language_server của Antigravity đang chạy + lấy csrf token + ports.
public final class AntigravityProcessDetector: Sendable {
    public typealias ShellRunner = @Sendable (_ command: String, _ args: [String]) throws -> String

    static let csrfTokenRegex = try! NSRegularExpression(pattern: #"--csrf_token\s+([a-fA-F0-9-]+)"#)
    static let antigravityArgvHint = "--app_data_dir antigravity"

    let runShell: ShellRunner
    public init(runShell: @escaping ShellRunner = AntigravityProcessDetector.defaultShellRunner) {
        self.runShell = runShell
    }

    public func detect() throws -> AntigravityProcessInfo? {
        let pgrepOut = try runShell("/usr/bin/pgrep", ["-f", "language_server"])
        let pids = Self.parsePIDs(pgrepOut)
        guard !pids.isEmpty else { return nil }
        let pidList = pids.map(String.init).joined(separator: ",")
        let psOut = try runShell("/bin/ps", ["-ww", "-o", "pid,args", "-p", pidList])
        guard let (pid, csrf) = Self.parseProcess(psOut) else { return nil }
        let lsofOut: String
        do { lsofOut = try runShell("/usr/sbin/lsof", ["-Pan", "-p", "\(pid)", "-i"]) }
        catch { return AntigravityProcessInfo(pid: pid, csrfToken: csrf, listeningPorts: []) }
        return AntigravityProcessInfo(pid: pid, csrfToken: csrf, listeningPorts: Self.parsePorts(lsofOut))
    }

    public static func parseProcess(_ psOutput: String) -> (pid: Int32, csrfToken: String)? {
        for line in psOutput.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.contains("language_server"), t.contains(antigravityArgvHint) else { continue }
            let parts = t.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            let argv = String(parts[1]); let ns = argv as NSString
            guard let m = csrfTokenRegex.firstMatch(in: argv, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges >= 2 else { continue }
            return (pid, ns.substring(with: m.range(at: 1)))
        }
        return nil
    }

    public static func parsePorts(_ lsofOutput: String) -> [Int] {
        var ports: Set<Int> = []
        for line in lsofOutput.components(separatedBy: "\n") where line.contains("LISTEN") {
            if let r = line.range(of: #"127\.0\.0\.1:(\d+)"#, options: .regularExpression) {
                let m = String(line[r])
                if let colon = m.lastIndex(of: ":"), let p = Int(m[m.index(after: colon)...]) { ports.insert(p) }
            }
        }
        return ports.sorted()
    }

    public static func parsePIDs(_ output: String) -> [Int32] {
        output.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Synchronous shell runner draining stdout/stderr concurrently (pipe-buffer safe).
    public static let defaultShellRunner: ShellRunner = { command, args in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command)
        p.arguments = args
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe; p.standardError = errPipe
        final class Buf { var d = Data() }
        let buf = Buf(); let lock = NSLock()
        outPipe.fileHandleForReading.readabilityHandler = { h in
            let c = h.availableData
            if c.isEmpty { h.readabilityHandler = nil; return }
            lock.lock(); buf.d.append(c); lock.unlock()
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            if h.availableData.isEmpty { h.readabilityHandler = nil }
        }
        try p.run(); p.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        let tail = outPipe.fileHandleForReading.availableData
        _ = errPipe.fileHandleForReading.availableData
        lock.lock(); if !tail.isEmpty { buf.d.append(tail) }; let out = buf.d; lock.unlock()
        return String(data: out, encoding: .utf8) ?? ""
    }
}
