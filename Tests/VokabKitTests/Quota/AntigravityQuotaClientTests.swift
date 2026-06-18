import XCTest
@testable import VokabKit

final class AntigravityQuotaClientTests: XCTestCase {
    private func resp(_ code: Int, port: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://127.0.0.1:\(port)/x")!, statusCode: code, httpVersion: nil, headerFields: nil)!
    }
    func test_fetch_returnsDecodedSummaryOn200() async throws {
        let body = Data(AntigravityQuotaSummaryTests.realJSON.utf8)
        let client = AntigravityQuotaClient(transport: { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-Codeium-Csrf-Token"), "tok")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Connect-Protocol-Version"), "1")
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"))
            return (body, self.resp(200, port: 5000))
        })
        let s = try await client.fetchQuota(port: 5000, csrfToken: "tok")
        XCTAssertEqual(s.groups.count, 2)
    }
    func test_fetch_throwsTransientWhenNo200() async {
        let client = AntigravityQuotaClient(transport: { _ in (Data(), self.resp(503, port: 5000)) })
        do { _ = try await client.fetchQuota(port: 5000, csrfToken: "tok"); XCTFail("expected throw") }
        catch AntigravityQuotaError.transient {} catch { XCTFail("wrong error: \(error)") }
    }
}
