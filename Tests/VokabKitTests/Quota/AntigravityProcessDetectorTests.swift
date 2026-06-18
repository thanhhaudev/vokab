import XCTest
@testable import VokabKit

final class AntigravityProcessDetectorTests: XCTestCase {
    func test_parseProcess_findsAntigravityProcess() {
        let line = "71236 70814 /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --https_server_port 0 --csrf_token 278ef7a5-91a5-4fdd-af7e-387b849f1812 --app_data_dir antigravity --enable_sidecars"
        let r = AntigravityProcessDetector.parseProcess(line)
        XCTAssertEqual(r?.pid, 71236)
        XCTAssertEqual(r?.csrfToken, "278ef7a5-91a5-4fdd-af7e-387b849f1812")
    }
    func test_parseProcess_returnsNilWhenNoLanguageServer() {
        XCTAssertNil(AntigravityProcessDetector.parseProcess("99 /bin/launchd"))
    }
    func test_parseProcess_ignoresGrepLine() {
        XCTAssertNil(AntigravityProcessDetector.parseProcess("99999 grep language_server"))
    }
    func test_parseProcess_distinguishesAntigravityFromOtherCodeium() {
        let cursor = "50001 /Applications/Cursor.app/Contents/Resources/bin/language_server --csrf_token aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa --app_data_dir cursor"
        let agy = "71236 /Applications/Antigravity.app/Contents/Resources/bin/language_server --csrf_token 278ef7a5-91a5-4fdd-af7e-387b849f1812 --app_data_dir antigravity"
        let r = AntigravityProcessDetector.parseProcess([cursor, agy].joined(separator: "\n"))
        XCTAssertEqual(r?.pid, 71236)
    }
    func test_parsePorts_extractsListenPorts() {
        let out = """
        language_ 71236 me 6u IPv4 0x1 0t0 TCP 127.0.0.1:49838 (LISTEN)
        language_ 71236 me 7u IPv4 0x2 0t0 TCP 127.0.0.1:49839 (LISTEN)
        """
        XCTAssertEqual(AntigravityProcessDetector.parsePorts(out), [49838, 49839])
    }
    func test_parsePorts_skipsEstablished() {
        let out = "language_ 71236 me 10u IPv4 0x 0t0 TCP 127.0.0.1:49838->127.0.0.1:55000 (ESTABLISHED)"
        XCTAssertEqual(AntigravityProcessDetector.parsePorts(out), [])
    }
    func test_parsePIDs_parsesAndTrims() {
        XCTAssertEqual(AntigravityProcessDetector.parsePIDs("  71236 \n\n71240\n"), [71236, 71240])
        XCTAssertEqual(AntigravityProcessDetector.parsePIDs("notapid\n71236"), [71236])
    }
    func test_detect_withInjectedRunner() throws {
        let detector = AntigravityProcessDetector { cmd, _ in
            switch cmd {
            case "/usr/bin/pgrep": return "71236\n"
            case "/bin/ps": return "71236 /Applications/Antigravity.app/Contents/Resources/bin/language_server --csrf_token 278ef7a5-91a5-4fdd-af7e-387b849f1812 --app_data_dir antigravity"
            case "/usr/sbin/lsof": return "language_ 71236 me 6u IPv4 0x1 0t0 TCP 127.0.0.1:49838 (LISTEN)"
            default: return ""
            }
        }
        let info = try detector.detect()
        XCTAssertEqual(info?.pid, 71236)
        XCTAssertEqual(info?.csrfToken, "278ef7a5-91a5-4fdd-af7e-387b849f1812")
        XCTAssertEqual(info?.listeningPorts, [49838])
    }
    func test_detect_returnsNilWhenNoProcess() throws {
        let detector = AntigravityProcessDetector { cmd, _ in cmd == "/usr/bin/pgrep" ? "" : { XCTFail("should not run"); return "" }() }
        XCTAssertNil(try detector.detect())
    }
}
