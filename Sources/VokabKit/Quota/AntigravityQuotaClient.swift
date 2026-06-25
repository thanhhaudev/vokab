import Foundation

public enum AntigravityQuotaError: Error, Equatable, Sendable {
    case transient
    case decode(String)
}

public final class AntigravityQuotaClient: Sendable {
    static let methodPath = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
    static let requestBody = #"{"metadata":{"ideName":"antigravity","extensionName":"antigravity","locale":"en"}}"#

    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    let transport: Transport
    let now: @Sendable () -> Date

    public init(transport: @escaping Transport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport; self.now = now
    }

    public static func live(now: @escaping @Sendable () -> Date = { Date() }) -> AntigravityQuotaClient {
        let session = permissiveSession
        return AntigravityQuotaClient(transport: { try await session.data(for: $0) }, now: now)
    }

    private static let permissiveSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        return URLSession(configuration: cfg, delegate: LoopbackDelegate(), delegateQueue: nil)
    }()

    private final class LoopbackDelegate: NSObject, URLSessionDelegate {
        func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge,
                        completionHandler h: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard c.protectionSpace.host == "127.0.0.1", let trust = c.protectionSpace.serverTrust
            else { h(.performDefaultHandling, nil); return }
            h(.useCredential, URLCredential(trust: trust))
        }
    }

    /// HTTPS only — instance standalone trả 400 cho http.
    public func fetchQuota(port: Int, csrfToken: String) async throws -> AntigravityQuotaSummary {
        guard let url = URL(string: "https://127.0.0.1:\(port)\(Self.methodPath)") else { throw AntigravityQuotaError.transient }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        req.httpBody = Data(Self.requestBody.utf8)
        let data: Data; let response: URLResponse
        do { (data, response) = try await transport(req) } catch { throw AntigravityQuotaError.transient }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AntigravityQuotaError.transient }
        do {
            var s = try AntigravityQuotaSummary.decoder.decode(AntigravityQuotaSummary.self, from: data)
            s.fetchedAt = now()
            return s
        } catch { throw AntigravityQuotaError.decode(String(describing: error)) }
    }
}
