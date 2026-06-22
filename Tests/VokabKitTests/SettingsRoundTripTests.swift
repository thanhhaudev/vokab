import XCTest
@testable import VokabKit

final class SettingsRoundTripTests: XCTestCase {
    func testEncodeDecodeRoundTrips() throws {
        var s = VokabSettings()
        s.newCardsPerDay = 33
        s.toastPosition = .bottomLeading
        s.autoDetectLanguage = false
        s.productionUnlockInterval = 10
        s.model = "Gemini 3.5 Flash (Low)"
        s.pronunciationAccent = "en-GB"
        s.autoPlayPronunciation = true
        s.clozeUnlockInterval = 5
        s.clozeUnlockReps = 3
        s.errorUnlockInterval = 8
        s.errorUnlockReps = 3
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VokabSettings.self, from: data)
        XCTAssertEqual(back, s)
    }

    func testMissingKeysFallBackToDefaults() throws {
        // Older persisted settings without the new keys must still decode.
        let json = #"{"agyPath":"/x","timeoutSeconds":60,"dailyLimit":200,"meaningLanguage":"vi","appLanguage":"en","quotaHitBehavior":"queue","jsonErrorBehavior":"retryOnce","maxConcurrent":3,"minParagraphLevel":"b1"}"#
        let back = try JSONDecoder().decode(VokabSettings.self, from: Data(json.utf8))
        XCTAssertEqual(back.newCardsPerDay, 20)
        XCTAssertEqual(back.toastPosition, .topTrailing)
        XCTAssertTrue(back.autoDetectLanguage)
        XCTAssertEqual(back.productionUnlockInterval, 7)
        XCTAssertEqual(back.startingEase, 2.5, accuracy: 0.0001)
    }

    func testClozeDefaultsWhenMissing() throws {
        let json = #"{"agyPath":"/x","timeoutSeconds":60,"dailyLimit":200,"meaningLanguage":"vi","appLanguage":"en","quotaHitBehavior":"queue","jsonErrorBehavior":"retryOnce","maxConcurrent":3,"minParagraphLevel":"b1"}"#
        let back = try JSONDecoder().decode(VokabSettings.self, from: Data(json.utf8))
        XCTAssertEqual(back.clozeUnlockInterval, 3)
        XCTAssertEqual(back.clozeUnlockReps, 2)
    }

    func testErrorDefaultsWhenMissing() throws {
        let json = #"{"agyPath":"/x","timeoutSeconds":60,"dailyLimit":200,"meaningLanguage":"vi","appLanguage":"en","quotaHitBehavior":"queue","jsonErrorBehavior":"retryOnce","maxConcurrent":3,"minParagraphLevel":"b1"}"#
        let back = try JSONDecoder().decode(VokabSettings.self, from: Data(json.utf8))
        XCTAssertEqual(back.errorUnlockInterval, 5)
        XCTAssertEqual(back.errorUnlockReps, 2)
    }

    func testPronunciationDefaultsWhenMissing() throws {
        let json = #"{"agyPath":"/x","timeoutSeconds":60,"dailyLimit":200,"meaningLanguage":"vi","appLanguage":"en","quotaHitBehavior":"queue","jsonErrorBehavior":"retryOnce","maxConcurrent":3,"minParagraphLevel":"b1"}"#
        let back = try JSONDecoder().decode(VokabSettings.self, from: Data(json.utf8))
        XCTAssertEqual(back.pronunciationAccent, "en-US")
        XCTAssertFalse(back.autoPlayPronunciation)
    }

    func test_hardBlockOnLimit_defaultsFalse_andRoundTrips() throws {
        XCTAssertFalse(VokabSettings().hardBlockOnLimit)
        var s = VokabSettings(); s.hardBlockOnLimit = true; s.dailyLimit = 50
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VokabSettings.self, from: data)
        XCTAssertTrue(back.hardBlockOnLimit)
        XCTAssertEqual(back.dailyLimit, 50)
    }
    func test_oldJSON_withoutHardBlock_decodesToFalse() throws {
        let json = #"{"dailyLimit":120}"#
        let s = try JSONDecoder().decode(VokabSettings.self, from: Data(json.utf8))
        XCTAssertFalse(s.hardBlockOnLimit)
        XCTAssertEqual(s.dailyLimit, 120)
    }

    func test_appearanceMode_defaultsSystem_andRoundTrips() throws {
        XCTAssertEqual(VokabSettings().appearanceMode, .system)
        var s = VokabSettings(); s.appearanceMode = .dark
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VokabSettings.self, from: data)
        XCTAssertEqual(back.appearanceMode, .dark)
    }

    func test_oldJSON_withoutAppearanceMode_decodesToSystem() throws {
        let json = #"{"dailyLimit":120}"#
        let s = try JSONDecoder().decode(VokabSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.appearanceMode, .system)
    }
}
