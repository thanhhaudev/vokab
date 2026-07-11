import XCTest
@testable import VokabKit

final class ListeningSettingsTests: XCTestCase {
    func testDefaults() {
        let s = VokabSettings()
        XCTAssertTrue(s.listeningAudioFront)
        XCTAssertEqual(s.listeningUnlockInterval, 1)
        XCTAssertEqual(s.listeningUnlockReps, 2)
    }

    func testLegacyJSONMissingKeysFallsBackToDefaults() throws {
        // JSON persisted before this feature has none of the listening keys.
        let legacy = "{\"agyPath\":\"/x/agy\"}".data(using: .utf8)!
        let s = try JSONDecoder().decode(VokabSettings.self, from: legacy)
        XCTAssertTrue(s.listeningAudioFront)
        XCTAssertEqual(s.listeningUnlockInterval, 1)
        XCTAssertEqual(s.listeningUnlockReps, 2)
    }

    func testRoundTripPreservesSetValues() throws {
        var s = VokabSettings()
        s.listeningAudioFront = false
        s.listeningUnlockInterval = 4
        s.listeningUnlockReps = 5
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VokabSettings.self, from: data)
        XCTAssertFalse(back.listeningAudioFront)
        XCTAssertEqual(back.listeningUnlockInterval, 4)
        XCTAssertEqual(back.listeningUnlockReps, 5)
    }
}
