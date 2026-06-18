import XCTest
@testable import VokabKit

final class LanguageServerLauncherTests: XCTestCase {
    func test_defaultBinaryPath_isAntigravityBundle() {
        XCTAssertEqual(LanguageServerLauncher.defaultBinaryPath,
                       "/Applications/Antigravity.app/Contents/Resources/bin/language_server")
    }
    func test_spawnArgs_containEssentials() {
        let args = LanguageServerLauncher.spawnArgs(csrf: "my-token")
        XCTAssertTrue(args.contains("--standalone"))
        XCTAssertTrue(args.contains("--https_server_port"))
        XCTAssertTrue(args.contains("0"))
        XCTAssertTrue(args.contains("--csrf_token"))
        XCTAssertTrue(args.contains("my-token"))
        XCTAssertTrue(args.contains("--app_data_dir"))
        XCTAssertTrue(args.contains("antigravity"))
    }
}
