import XCTest
@testable import VokabKit

final class AntigravityQuotaSummaryTests: XCTestCase {
    static let realJSON = #"""
    {"response":{"groups":[
      {"displayName":"Gemini Models","description":"Gemini Flash, Gemini Pro","buckets":[
        {"bucketId":"gemini-weekly","displayName":"Weekly Limit","window":"weekly","remainingFraction":0.60286415,"resetTime":"2026-06-20T04:22:36Z"},
        {"bucketId":"gemini-5h","displayName":"Five Hour Limit","window":"5h","remainingFraction":0.9556844,"resetTime":"2026-06-18T07:21:35Z"}]},
      {"displayName":"Claude and GPT models","buckets":[
        {"bucketId":"3p-weekly","displayName":"Weekly Limit","window":"weekly","remainingFraction":1,"resetTime":"2026-06-25T03:45:17Z"},
        {"bucketId":"3p-5h","displayName":"Five Hour Limit","window":"5h","remainingFraction":1,"resetTime":"2026-06-18T08:45:17Z"}]}
    ],"description":"shared limits"}}
    """#

    func test_decodesGroupsAndBuckets() throws {
        let s = try AntigravityQuotaSummary.decoder.decode(AntigravityQuotaSummary.self, from: Data(Self.realJSON.utf8))
        XCTAssertEqual(s.groups.count, 2)
        let gem = s.groups[0]
        XCTAssertEqual(gem.displayName, "Gemini Models")
        XCTAssertEqual(gem.weekly?.window, .weekly)
        XCTAssertEqual(gem.fiveHour?.remainingFraction ?? 0, 0.9556844, accuracy: 1e-6)
        XCTAssertNotNil(gem.weekly?.resetTime)
    }
    func test_utilizationAndExhaustion() throws {
        let s = try AntigravityQuotaSummary.decoder.decode(AntigravityQuotaSummary.self, from: Data(Self.realJSON.utf8))
        XCTAssertEqual(s.groups[0].weekly?.utilization ?? 0, 39.71, accuracy: 0.1)
        XCTAssertFalse(s.groups[0].weekly!.isExhausted)
    }
    func test_emptyOnGarbage() throws {
        let s = try AntigravityQuotaSummary.decoder.decode(AntigravityQuotaSummary.self, from: Data(#"{"x":1}"#.utf8))
        XCTAssertTrue(s.groups.isEmpty)
    }
}
