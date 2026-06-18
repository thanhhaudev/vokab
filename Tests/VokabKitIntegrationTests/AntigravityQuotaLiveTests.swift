import XCTest
@testable import VokabKit

/// Chỉ chạy khi VOKAB_AGY_INTEGRATION=1 và Antigravity.app đã cài + đã đăng nhập.
/// Assert CẤU TRÚC (nhóm có bucket), KHÔNG assert con số.
final class AntigravityQuotaLiveTests: XCTestCase {
    func test_spawnAndFetch_returnsGroups() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VOKAB_AGY_INTEGRATION"] == "1")
        let launcher = LanguageServerLauncher()
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: launcher.binaryPath))
        let csrf = UUID().uuidString
        let spawned = try await launcher.spawn(csrf: csrf)
        defer { launcher.terminate(pid: spawned.pid) }
        let summary = try await AntigravityQuotaClient.live().fetchQuota(port: spawned.port, csrfToken: csrf)
        XCTAssertGreaterThanOrEqual(summary.groups.count, 1)
        for g in summary.groups { XCTAssertFalse(g.buckets.isEmpty) }
    }
}
