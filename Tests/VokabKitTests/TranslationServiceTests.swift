import XCTest
import GRDB
@testable import VokabKit

final class TranslationServiceTests: XCTestCase {
    func testTranslatesThenCaches() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let cache = CacheRepository(dbQueue: queue)
        let runner = MockAgyRunner(response: #"{"translation":"Chúng ta cần dọn dẹp."}"#)
        let svc = TranslationService(agy: AgyService(runner: runner, settings: VokabSettings()), cache: cache)
        let t1 = try await svc.translate("We need to clean up.", to: "vi")
        XCTAssertEqual(t1, "Chúng ta cần dọn dẹp.")
        // cached: a runner that would return something else must NOT be hit
        let svc2 = TranslationService(agy: AgyService(runner: MockAgyRunner(response: #"{"translation":"WRONG"}"#), settings: VokabSettings()), cache: cache)
        let t2 = try await svc2.translate("We need to clean up.", to: "vi")
        XCTAssertEqual(t2, "Chúng ta cần dọn dẹp.")   // from cache
    }
    func testSkipsEnglishTargetAndEmpty() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let svc = TranslationService(agy: AgyService(runner: MockAgyRunner(response: #"{"translation":"x"}"#), settings: VokabSettings()),
                                     cache: CacheRepository(dbQueue: queue))
        let en = try await svc.translate("Hello.", to: "en")
        XCTAssertNil(en)
        let empty = try await svc.translate("   ", to: "vi")
        XCTAssertNil(empty)
    }
}
