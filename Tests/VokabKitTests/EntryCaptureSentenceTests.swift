import XCTest
import GRDB
@testable import VokabKit

final class EntryCaptureSentenceTests: XCTestCase {
    func testRoundTripsNonNilSentence() throws {
        let queue = try VokabDatabase.makeInMemory()
        var e = Entry(rawText: "serendipity", type: "word", language: "en",
                      capturedAt: Date(timeIntervalSince1970: 1_700_000_000), aiResult: "{}",
                      captureSentence: "We embraced the serendipity of it.")
        try queue.write { db in try e.insert(db) }
        let read = try queue.read { db in try Entry.fetchOne(db) }
        XCTAssertEqual(read?.captureSentence, "We embraced the serendipity of it.")
    }

    func testDefaultsToNil() throws {
        let queue = try VokabDatabase.makeInMemory()
        var e = Entry(rawText: "x", type: "word", language: "en",
                      capturedAt: Date(timeIntervalSince1970: 1_700_000_000), aiResult: "{}")
        try queue.write { db in try e.insert(db) }
        let read = try queue.read { db in try Entry.fetchOne(db) }
        XCTAssertNil(read?.captureSentence)
    }
}
